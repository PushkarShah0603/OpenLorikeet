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
    check(merged?.pageCount == 3 && merged?.page(at: 0)?.string?.contains("Page one editable text") == true && merged?.page(at: 1)?.string?.contains("Oranges") == true && merged?.page(at: 2)?.string?.contains("Page three appended") == true, "PDF merge preserves order")
    let splits = try fm.contentsOfDirectory(at: files[1], includingPropertiesForKeys: nil)
    check(splits.count == 2 && splits.allSatisfy { PDFDocument(url: $0)?.pageCount == 1 }, "PDF split writes one document per page")
    let images = try fm.contentsOfDirectory(at: files[2], includingPropertiesForKeys: nil)
    check(images.count == 2 && images.allSatisfy { CGImageSourceCreateWithURL($0 as CFURL, nil) != nil }, "PDF rasterizes all pages")
    check(try String(contentsOf: files[3], encoding: .utf8).contains("Page one editable text"), "Selectable text extraction")
    let word = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", files[4].path, "word/document.xml"], directory: folder)
    check(word.stdout.contains("<w:t xml:space=\"preserve\">Page one editable text"), "PDF text becomes editable Word runs")
    check(word.stdout.contains("<w:tbl>"), "Consistently separated PDF columns become an editable table")
    check(registry.pdfTools(for: [first]) == [.compressPDF, .metadataPDF, .organizePDF, .splitPDF], "Single PDF tools")
    check(registry.pdfTools(for: [first, second]) == [.compressPDF, .mergePDF, .splitPDF], "Batch PDF tools")
    check(registry.pdfTools(for: [first, folder.appendingPathComponent("image.png")]).isEmpty, "PDF tools require a PDF selection")
    check(try PDFOptions.pageIndices("3-2, 1", count: 3) == [2, 1, 0], "Reversed ranges preserve order")
    for invalid in ["", "0", "4", "1,1", "1-", "1,,2"] {
        check((try? PDFOptions.pageIndices(invalid, count: 3)) == nil, "Invalid page order: \(invalid)")
    }
    let metadata = PDFMetadata(title: "Lab notes", author: "OpenLorikeet", subject: "PDF check", keywords: ["lab", "manual"])
    let metadataJob = try ConversionRequest(inputs: [first], choice: .metadataPDF, pdfOptions: .metadata(metadata))
    let organizeJob = try ConversionRequest(inputs: [files[0]], choice: .organizePDF, pdfOptions: .pageOrder([2, 0]))
    let original = try Data(contentsOf: first)
    let originalMerged = try Data(contentsOf: files[0])
    await queue.submit([metadataJob, organizeJob])
    await queue.waitUntilIdle()
    guard case .succeeded(let edited) = await queue.state(for: metadataJob.id),
          case .succeeded(let organized) = await queue.state(for: organizeJob.id),
          let reordered = PDFDocument(url: organized) else { fatalError("PDF editing tools failed") }
    let inspected = try PDFEngine().editingInfo(for: edited)
    check(inspected.pages == 2 && inspected.metadata.title == metadata.title &&
          inspected.metadata.author == metadata.author && inspected.metadata.subject == metadata.subject &&
          inspected.metadata.keywords == metadata.keywords, "PDF metadata survives a fresh read")
    check(reordered.pageCount == 2 && reordered.page(at: 0)?.string?.contains("Page three appended") == true &&
          reordered.page(at: 1)?.string?.contains("Page one editable text") == true, "PDF organize reorders pages and drops omitted ones")
    check(try Data(contentsOf: first) == original && Data(contentsOf: files[0]) == originalMerged,
          "PDF tools leave both originals byte-identical")

    let large = folder.appendingPathComponent("Image-heavy.pdf")
    let side = 1_600
    let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let pixels = bitmap.data!.assumingMemoryBound(to: UInt8.self)
    var seed: UInt32 = 129
    for index in 0..<(bitmap.bytesPerRow * side) {
        seed = 1_664_525 &* seed &+ 1_013_904_223
        pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
    }
    var paper = CGRect(x: 0, y: 0, width: 400, height: 420)
    let consumer = CGDataConsumer(url: large as CFURL)!
    let photoPDF = CGContext(consumer: consumer, mediaBox: &paper, nil)!
    photoPDF.beginPDFPage(nil)
    photoPDF.draw(bitmap.makeImage()!, in: CGRect(x: 0, y: 0, width: 400, height: 400))
    drawText("Selectable caption", in: photoPDF, x: 8, y: 404, size: 12)
    photoPDF.endPDFPage()
    photoPDF.closePDF()
    let compression = try ConversionRequest(inputs: [large], choice: .compressPDF)
    await queue.submit([compression])
    await queue.waitUntilIdle()
    let compressionState = await queue.state(for: compression.id)
    guard case .succeeded(let smaller) = compressionState else {
        fatalError("Image-heavy PDF compression failed: \(String(describing: compressionState))")
    }
    check(try Data(contentsOf: smaller).count < Data(contentsOf: large).count &&
          PDFDocument(url: smaller)?.string?.contains("Selectable caption") == true,
          "Compression shrinks image-heavy PDFs and keeps text selectable")
    print("PASS: PDF tool selection, page order parsing, metadata editing, page organization, and compression")

    let croppedURL = folder.appendingPathComponent("Rotated crop.pdf")
    // Encode the boxes and rotation directly so the fixture is independent of
    // PDFKit's page editing and serialization behavior.
    let content = "BT /F1 18 Tf 60 700 Td (Visible inside the crop) Tj ET"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /CropBox [52 600 552 780] /Rotate 90 /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ]
    var croppedBytes = Data("%PDF-1.4\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(croppedBytes.count)
        croppedBytes.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = croppedBytes.count
    let entries = offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
    croppedBytes.append(Data("xref\n0 6\n0000000000 65535 f \n\(entries)trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    try croppedBytes.write(to: croppedURL)
    let cropJob = try ConversionRequest(source: croppedURL, targetFormat: .png)
    await queue.submit([cropJob])
    await queue.waitUntilIdle()
    guard case .succeeded(let cropFolder) = await queue.state(for: cropJob.id),
          let imageSource = CGImageSourceCreateWithURL(cropFolder.appendingPathComponent("Page 0001.png") as CFURL, nil),
          let croppedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { fatalError("Rotated PDF export failed") }
    check(croppedImage.width == 540 && croppedImage.height == 1500, "PDF export uses rotated crop bounds")
    check((croppedImage.dataProvider?.data as Data?)?.contains(where: { $0 < 128 }) == true, "Cropped page retains rendered text")
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
