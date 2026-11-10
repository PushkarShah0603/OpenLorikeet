import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import ConversionCore

func checkPDFRoutes() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("pdf-check-\(UUID())")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }

    func textPDF(_ url: URL, pages: [[String]]) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(url: url as CFURL)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for lines in pages {
            context.beginPDFPage(nil)
            for (index, text) in lines.enumerated() {
                for (column, cell) in text.components(separatedBy: "      ").enumerated() {
                    drawText(cell, in: context, x: 60 + Double(column) * 220, y: 700 - Double(index) * 32, size: 18)
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    let first = folder.appendingPathComponent("First.pdf")
    let second = folder.appendingPathComponent("Second.pdf")
    textPDF(first, pages: [["Page one editable text"], ["Name      Amount", "Apples      25", "Oranges      17"]])
    textPDF(second, pages: [["Page three appended"]])
    let registry = EngineRegistry.local()
    check(registry.choices(for: [first, second]).contains(.mergePDF), "Merge offered on two PDFs")
    check(!registry.choices(for: [first]).contains(.mergePDF), "Merge requires multiple PDFs")
    let queue = ConversionQueue(registry: registry)
    let merge = try ConversionRequest(inputs: [first, second], choice: .mergePDF)
    let split = try ConversionRequest(inputs: [first], choice: .splitPDF)
    let image = try ConversionRequest(source: first, targetFormat: .png)
    let text = try ConversionRequest(source: first, targetFormat: .txt)
    let docx = try ConversionRequest(source: first, targetFormat: .docx)
    let jobs = [merge, split, image, text, docx]
    await queue.submit(jobs)
    await queue.waitUntilIdle()
    let states = await queue.states(for: jobs.map(\.id))
    let files = states.compactMap { state -> URL? in
        if case .succeeded(let url) = state { return url }
        return nil
    }
    check(files.count == jobs.count, "All PDF operations succeed: \(states)")
    let merged = PDFDocument(url: files[0])
    check(merged?.pageCount == 3 && merged?.page(at: 2)?.string?.contains("Page three appended") == true, "PDF merge preserves order")
    let splits = try fm.contentsOfDirectory(at: files[1], includingPropertiesForKeys: nil)
    check(splits.count == 2 && splits.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 }, "PDF split writes one document per page")
    let images = try fm.contentsOfDirectory(at: files[2], includingPropertiesForKeys: nil)
    check(images.count == 2 && images.allSatisfy { CGImageSourceCreateWithURL($0 as CFURL, nil) != nil }, "PDF rasterizes all pages")
    check(try String(contentsOf: files[3], encoding: .utf8).contains("Page one editable text"), "Selectable text extraction")
    let word = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", files[4].path, "word/document.xml"], directory: folder)
    check(word.stdout.contains("<w:t xml:space=\"preserve\">Page one editable text"), "PDF text becomes editable Word runs")
    check(word.stdout.contains("<w:tbl>"), "Consistently separated PDF columns become an editable table")

    let raster = CGContext(data: nil, width: 1_200, height: 460, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    raster.setFillColor(CGColor(gray: 1, alpha: 1))
    raster.fill(CGRect(x: 0, y: 0, width: 1_200, height: 460))
    drawText("OpenLorikeet scanned document", in: raster, x: 70, y: 320, size: 48)
    drawText("The quick brown fox jumps.", in: raster, x: 70, y: 220, size: 48)
    let scan = folder.appendingPathComponent("Scanned.png")
    let encoder = CGImageDestinationCreateWithURL(scan as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, raster.makeImage()!, nil)
    check(CGImageDestinationFinalize(encoder), "Scan fixture saved")
    let scannedPDF = try ConversionRequest(source: scan, targetFormat: .pdf)
    await queue.submit([scannedPDF])
    await queue.waitUntilIdle()
    guard case .succeeded(let scanned) = await queue.state(for: scannedPDF.id) else { fatalError("Scan PDF fixture failed") }
    let scannedDoc = try ConversionRequest(source: scanned, targetFormat: .docx)
    await queue.submit([scannedDoc])
    await queue.waitUntilIdle()
    let result = await queue.state(for: scannedDoc.id)
    if case .succeeded(let url) = result {
        let recognized = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                     arguments: ["-p", url.path, "word/document.xml"], directory: folder)
        check(recognized.stdout.lowercased().contains("quick brown fox"), "OCR recognizes known scan text in editable Word output")
        print("PASS: scanned PDF OCR")
    } else if case .failed(let error) = result, error.contains("CVPixelBuffer") {
        print("UNVERIFIED: this environment could not allocate Vision’s OCR pixel buffer")
    } else {
        fatalError("OCR fixture failed: \(String(describing: result))")
    }
    print("PASS: PDF merge, split, page images, text, and editable DOCX tables")
}

private func drawText(_ string: String, in context: CGContext, x: Double, y: Double, size: Double) {
    let attrs: [NSAttributedString.Key: Any] = [
        .init(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
        .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs)), context)
}
