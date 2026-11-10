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
        default:
            guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Image output is unreadable") }
            check(image.width == 128 && image.height == 96, "Image dimensions preserved")
            if job.targetFormat == .jpeg {
                check([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "JPEG alpha flattened")
            }
        }
    }
    print("PASS: image routes \(targets.map(\.rawValue).joined(separator: ", ")), readable outputs, expected dimensions, and Word image package")
}
