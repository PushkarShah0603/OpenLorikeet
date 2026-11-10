import Foundation
import CoreGraphics
import PDFKit
import Vision

public struct PDFEngine: ConversionEngine {
    public let identifier = "PDFKit and Vision"
    public let availability: EngineAvailability = .ready
    public init() {}

    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        source == .pdf && [.txt, .docx, .png, .jpeg].contains(target)
    }

    public func supports(source: FileFormat, choice: ConversionChoice) -> Bool {
        switch choice {
        case .format(let target): supports(source: source, target: target)
        case .mergePDF, .splitPDF: source == .pdf
        default: false
        }
    }

    public func producesFolder(for request: ConversionRequest) -> Bool {
        request.choice == .splitPDF || [.png, .jpeg].contains(request.targetFormat)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        if request.choice == .mergePDF {
            let combined = PDFDocument()
            for source in request.inputs {
                let document = try load(source)
                guard combined.pageCount + document.pageCount <= 500 else { throw WorkerError.engineUnavailable("The merged PDF would exceed 500 pages.") }
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    guard let page = document.page(at: index)?.copy() as? PDFPage else { throw WorkerError.invalidInput }
                    combined.insert(page, at: combined.pageCount)
                }
            }
            guard combined.write(to: output) else { throw WorkerError.invalidOutput }
            return
        }

        let document = try load(request.source)
        if producesFolder(for: request) {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { throw WorkerError.invalidInput }
                let destination = output.appendingPathComponent(String(format: "Page %04d", index + 1))
                    .appendingPathExtension(request.targetFormat.fileExtension)
                if request.choice == .splitPDF {
                    let single = PDFDocument()
                    guard let copy = page.copy() as? PDFPage else { throw WorkerError.invalidInput }
                    single.insert(copy, at: 0)
                    guard single.write(to: destination) else { throw WorkerError.invalidOutput }
                } else {
                    let rendered = try rasterize(page, maximum: 2_400)
                    try ImageEngine.encode(rendered, format: request.targetFormat, quality: 0.9).write(to: destination)
                }
            }
            return
        }

        if request.targetFormat == .txt {
            var pages: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                pages.append(document.page(at: index)?.string ?? "")
            }
            let text = pages.joined(separator: "\n\u{000C}\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkerError.engineUnavailable("This PDF has no selectable text. Choose DOCX to recognize scanned pages.")
            }
            try text.write(to: output, atomically: true, encoding: .utf8)
            return
        }

        var blocks: [WordBlock] = []
        var readablePages = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw WorkerError.invalidInput }
            if index > 0 { blocks.append(.pageBreak) }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                let lines = try recognize(try rasterize(page, maximum: 2_800))
                if lines.isEmpty {
                    blocks.append(.paragraph("[Page \(index + 1) contains no recognized text]"))
                } else {
                    readablePages += 1
                    blocks += lines.map { .paragraph($0) }
                }
            } else {
                readablePages += 1
                blocks += editableBlocks(text, page: page)
            }
        }
        guard readablePages > 0 else { throw WorkerError.engineUnavailable("No readable text was found in the PDF.") }
        try await WordWriter.write(blocks, to: output)
    }

    private func load(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw WorkerError.invalidInput }
        guard !document.isLocked, document.allowsCopying else {
            throw WorkerError.engineUnavailable("Unlock the PDF and allow copying before converting it.")
        }
        guard document.pageCount <= 500 else { throw WorkerError.engineUnavailable("This operation supports PDFs up to 500 pages.") }
        return document
    }

    private func rasterize(_ page: PDFPage, maximum: Int) throws -> CGImage {
        let box = page.bounds(for: .cropBox)
        let maxDimension = max(box.width, box.height)
        guard box.width > 0, box.height > 0, maxDimension.isFinite else { throw WorkerError.invalidInput }
        let scale = min(3, Double(maximum) / maxDimension)
        let width = max(1, Int((box.width * scale).rounded(.up)))
        let height = max(1, Int((box.height * scale).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw WorkerError.invalidOutput }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw WorkerError.invalidOutput }
        return image
    }

    private func recognize(_ image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            throw WorkerError.engineUnavailable("Local OCR could not process the scanned page. \(error.localizedDescription)")
        }
        try Task.checkCancellation()
        return (request.results ?? []).sorted {
            let a = Int($0.boundingBox.midY * 100)
            let b = Int($1.boundingBox.midY * 100)
            return a == b ? $0.boundingBox.minX < $1.boundingBox.minX : a > b
        }.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            return text.confidence < 0.45 ? "[Check OCR] \(text.string)" : text.string
        }
    }

    private func editableBlocks(_ text: String, page: PDFPage) -> [WordBlock] {
        let fallback = text.components(separatedBy: .newlines).map(WordBlock.paragraph)
        let count = page.numberOfCharacters
        guard page.rotation == 0, count <= 8_000 else { return fallback }
        let glyphs = (0..<count).map { page.characterBounds(at: $0) }
            .filter { !$0.isEmpty && $0.width.isFinite && $0.height.isFinite && $0.width <= $0.height * 1.6 }
            .sorted { $0.midY > $1.midY }
        var rows: [[CGRect]] = []
        for glyph in glyphs {
            if Task.isCancelled { return fallback }
            if let first = rows.last?.first,
               abs(first.midY - glyph.midY) < min(first.height, glyph.height) * 0.45 {
                rows[rows.count - 1].append(glyph)
            } else {
                rows.append([glyph])
            }
        }
        struct Cell { let text: String; let x: Double }
        let cells = rows.map { glyphs -> [Cell] in
            var boxes: [CGRect] = []
            for glyph in glyphs.sorted(by: { $0.minX < $1.minX }) {
                if let last = boxes.last, glyph.minX - last.maxX < max(12, glyph.height) {
                    boxes[boxes.count - 1] = last.union(glyph)
                } else {
                    boxes.append(glyph)
                }
            }
            return boxes.compactMap { box in
                guard let selected = page.selection(for: box.insetBy(dx: -0.25, dy: -0.25))?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty else { return nil }
                return Cell(text: selected, x: box.minX)
            }
        }
        // Short rows with repeated column positions are likely tables. Retain the
        // PDF's text order when no such run is present, including many column layouts.
        var blocks: [WordBlock] = []
        var foundTable = false
        var index = 0
        while index < cells.count {
            let row = cells[index]
            var end = index + 1
            if (2...10).contains(row.count), row.allSatisfy({ $0.text.count <= 70 }) {
                while end < cells.count, cells[end].count == row.count,
                      zip(row, cells[end]).allSatisfy({ abs($0.x - $1.x) <= 12 && $1.text.count <= 70 }) {
                    end += 1
                }
            }
            if end - index >= 3 {
                blocks.append(.table(cells[index..<end].map { $0.map(\.text) }))
                foundTable = true
                index = end
            } else {
                blocks.append(.paragraph(row.map(\.text).joined(separator: "  ")))
                index += 1
            }
        }
        return foundTable ? blocks : fallback
    }

    public func validate(output: URL, format: FileFormat) async throws {
        switch format {
        case .docx: try await WordWriter.validate(output)
        case .txt:
            guard !(try String(contentsOf: output, encoding: .utf8)).isEmpty else { throw WorkerError.invalidOutput }
        case .pdf, .png, .jpeg:
            let files = output.hasDirectoryPath ? try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) : [output]
            guard !files.isEmpty else { throw WorkerError.invalidOutput }
            for file in files {
                try Task.checkCancellation()
                if format == .pdf {
                    guard let pdf = PDFDocument(url: file), pdf.pageCount > 0 else { throw WorkerError.invalidOutput }
                } else {
                    try await ImageEngine().validate(output: file, format: format)
                }
            }
        default: throw WorkerError.invalidOutput
        }
    }
}
