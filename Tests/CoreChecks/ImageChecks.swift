import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import ConversionCore

func checkImageRoutes() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("image-check-\(UUID())")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let input = folder.appendingPathComponent("Transparent image.png")
    let bitmap = CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.9, alpha: 0.5))
    bitmap.fill(CGRect(x: 16, y: 16, width: 64, height: 64))
    let encoder = CGImageDestinationCreateWithURL(input as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, bitmap.makeImage()!, nil)
    check(CGImageDestinationFinalize(encoder), "PNG fixture encoded")
    let registry = EngineRegistry.local()
    let queue = ConversionQueue(registry: registry)
    let targets = registry.targets(for: [input])
    check(targets.contains(.jpeg) && targets.contains(.pdf) && targets.contains(.docx), "Image routes ready")
    let jobs = try targets.map { try ConversionRequest(source: input, targetFormat: $0) }
    await queue.submit(jobs)
    await queue.waitUntilIdle()
    for job in jobs {
        let state = await queue.state(for: job.id)
        guard case .succeeded(let output) = state else { fatalError("Image route \(job.targetFormat): \(String(describing: state))") }
        switch job.targetFormat {
        case .pdf:
            check(PDFDocument(url: output)?.pageCount == 1, "Image PDF contains one page")
        case .docx:
            let structure = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                       arguments: ["-p", output.path, "word/document.xml"], directory: folder)
            check(structure.stdout.contains("<w:drawing>"), "Image embedded in a Word drawing")
            let media = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                   arguments: ["-l", output.path], directory: folder)
            check(media.stdout.contains("word/media/image1.png"), "Embedded media present")
            let pdfJob = try ConversionRequest(source: output, targetFormat: .pdf)
            await queue.submit([pdfJob])
            await queue.waitUntilIdle()
            guard case .succeeded(let wordPDF) = await queue.state(for: pdfJob.id),
                  let page = PDFDocument(url: wordPDF)?.page(at: 0)?.pageRef else {
                fatalError("Word to PDF could not render an image-only document")
            }
            let box = page.getBoxRect(.mediaBox)
            let preview = CGContext(data: nil, width: 306, height: 396, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            let bounds = CGRect(x: 0, y: 0, width: 306, height: 396)
            preview.setFillColor(CGColor(gray: 1, alpha: 1))
            preview.fill(bounds)
            preview.scaleBy(x: bounds.width / box.width, y: bounds.height / box.height)
            preview.drawPDFPage(page)
            let pixels = preview.data!.assumingMemoryBound(to: UInt8.self)
            check(UnsafeBufferPointer(start: pixels, count: preview.bytesPerRow * preview.height).contains { $0 < 225 },
                  "The Word PDF contains the embedded image")
            // Word compatibility shapes before a picture used to make native
            // import discard that picture and report a successful text-only PDF.
            let marker = "<w:drawing>"
            let drawingStart = structure.stdout.range(of: marker)!.lowerBound
            let drawingEnd = structure.stdout.range(of: "</w:drawing>")!.upperBound
            let drawing = String(structure.stdout[drawingStart..<drawingEnd])
            let extra = """
            <w:p><w:r><w:br w:type="page"/></w:r></w:p>
            <w:p><w:r><mc:AlternateContent><mc:Choice Requires="wps">
            <w:drawing><wp:anchor><a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
            <wps:wsp><wps:txbx><w:txbxContent><w:p><w:r><w:t>Picture label</w:t></w:r></w:p></w:txbxContent></wps:txbx></wps:wsp>
            </a:graphicData></a:graphic></wp:anchor></w:drawing>
            </mc:Choice><mc:Fallback><w:pict/></mc:Fallback></mc:AlternateContent></w:r><w:r>\(drawing)</w:r></w:p>
            """
            let amended = structure.stdout.replacingOccurrences(of: "<w:document ",
                with: "<w:document xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\" ")
                .replacingOccurrences(of: "<w:sectPr>", with: extra + "<w:sectPr>")
            let parts = folder.appendingPathComponent("picture-parts")
            try fm.createDirectory(at: parts.appendingPathComponent("word"), withIntermediateDirectories: true)
            try amended.write(to: parts.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)
            let repeated = folder.appendingPathComponent("Word compatibility pictures.docx")
            try fm.copyItem(at: output, to: repeated)
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                           arguments: ["-q", repeated.path, "word/document.xml"], directory: parts)
            let pictureJob = try ConversionRequest(source: repeated, targetFormat: .pdf)
            await queue.submit([pictureJob])
            await queue.waitUntilIdle()
            guard case .succeeded(let picturePDF) = await queue.state(for: pictureJob.id),
                  let pictureDocument = PDFDocument(url: picturePDF), pictureDocument.pageCount == 2 else {
                fatalError("Word compatibility picture export failed")
            }
            for index in 0..<2 {
                let page = pictureDocument.page(at: index)!.pageRef!
                var resources: CGPDFDictionaryRef?
                var objects: CGPDFDictionaryRef?
                check(CGPDFDictionaryGetDictionary(page.dictionary!, "Resources", &resources) &&
                      CGPDFDictionaryGetDictionary(resources!, "XObject", &objects) &&
                      CGPDFDictionaryGetCount(objects!) > 0, "Every picture page contains embedded image data")
            }
            check(pictureDocument.string?.contains("Picture label") == true, "Word textbox labels survive normalization")
        default:
            guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Image output is unreadable") }
            check(image.width == 128 && image.height == 96, "Image dimensions preserved")
            if job.targetFormat == .jpeg {
                check([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "JPEG alpha flattened")
            }
        }
    }
    let rotatedInput = folder.appendingPathComponent("Rotated JPEG.jpg")
    let jpeg = CGImageDestinationCreateWithURL(rotatedInput as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(jpeg, bitmap.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
    check(CGImageDestinationFinalize(jpeg), "Rotated JPEG fixture encoded")
    let rotatedJob = try ConversionRequest(source: rotatedInput, targetFormat: .png)
    await queue.submit([rotatedJob])
    await queue.waitUntilIdle()
    guard case .succeeded(let rotated) = await queue.state(for: rotatedJob.id),
          let source = CGImageSourceCreateWithURL(rotated as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Rotated JPEG export failed") }
    check(image.width == 96 && image.height == 128, "EXIF orientation is applied to output pixels")
    print("PASS: image routes \(targets.map(\.rawValue).joined(separator: ", ")), readable outputs, expected dimensions, and Word image package")
}
