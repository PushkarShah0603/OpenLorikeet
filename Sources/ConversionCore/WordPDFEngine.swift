import AppKit
import CoreGraphics
import PDFKit

struct WordPDFEngine: ConversionEngine {
    let identifier = "macOS Word to PDF"
    let availability: EngineAvailability = .ready

    func supports(source: FileFormat, target: FileFormat) -> Bool {
        source == .docx && target == .pdf
    }

    func convert(_ request: ConversionRequest, to output: URL) async throws {
        let size = try request.source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 100 * 1024 * 1024 else { throw WorkerError.invalidInput }
        // Check the package before handing it to the native Word importer.
        let xml = try await OfficePackage.xml(OfficePackage.read(
            "word/document.xml", in: request.source, workspace: output.deletingLastPathComponent()
        ))
        guard xml.rootElement()?.localName == "document" else { throw WorkerError.invalidInput }
        try Task.checkCancellation()
        let (importURL, pictures) = try await WordPictures.prepare(
            document: xml, source: request.source, workspace: output.deletingLastPathComponent()
        )

        var attributes: NSDictionary?
        let text = try NSMutableAttributedString(url: importURL,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: &attributes)
        guard text.length <= 2_000_000 else { throw WorkerError.invalidInput }
        let paper = attributes?[NSAttributedString.DocumentAttributeKey.paperSize] as? NSValue
        let sizeInPoints = paper?.sizeValue ?? NSSize(width: 612, height: 792)
        let width = sizeInPoints.width, height = sizeInPoints.height
        guard (144...2880).contains(width), (144...2880).contains(height) else { throw WorkerError.invalidInput }
        func margin(_ key: NSAttributedString.DocumentAttributeKey, limit: CGFloat) -> CGFloat {
            let value = (attributes?[key] as? NSNumber)?.doubleValue ?? 54
            return value.isFinite ? min(max(0, value), limit / 3) : 54
        }
        let left = margin(.leftMargin, limit: width), right = margin(.rightMargin, limit: width)
        let top = margin(.topMargin, limit: height), bottom = margin(.bottomMargin, limit: height)
        let contentSize = NSSize(width: width - left - right, height: height - top - bottom)
        try WordPictures.restore(pictures, in: text, contentSize: contentSize)
        var box = CGRect(origin: .zero, size: sizeInPoints)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw WorkerError.invalidOutput }
        defer { pdf.closePDF() }

        // The Word importer exposes explicit page breaks as form feeds.
        let string = text.string as NSString
        var start = 0
        var pages = 0
        repeat {
            try Task.checkCancellation()
            let remaining = NSRange(location: start, length: string.length - start)
            let separator = string.range(of: "\u{000C}", options: [], range: remaining)
            let end = separator.location == NSNotFound ? string.length : separator.location
            let section = text.attributedSubstring(from: NSRange(location: start, length: end - start))
            let storage = NSTextStorage(attributedString: section)
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            var printed = 0
            repeat {
                try Task.checkCancellation()
                guard pages < 500 else { throw WorkerError.engineUnavailable("Word export supports up to 500 pages.") }
                let container = NSTextContainer(size: contentSize)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let glyphs = layout.glyphRange(for: container)
                guard glyphs.length > 0 || storage.length == 0 else {
                    throw WorkerError.engineUnavailable("Word content could not fit on the page.")
                }
                pdf.beginPDFPage(nil)
                pdf.saveGState()
                pdf.translateBy(x: left, y: height - top)
                pdf.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
                layout.drawBackground(forGlyphRange: glyphs, at: .zero)
                layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
                NSGraphicsContext.restoreGraphicsState()
                pdf.restoreGState()
                pdf.endPDFPage()
                printed = NSMaxRange(glyphs)
                pages += 1
            } while printed < layout.numberOfGlyphs
            start = end + 1
        } while start <= string.length
    }

    func validate(output: URL, format: FileFormat) throws {
        guard let pdf = PDFDocument(url: output), pdf.pageCount > 0, !pdf.isLocked else {
            throw WorkerError.invalidOutput
        }
    }
}
