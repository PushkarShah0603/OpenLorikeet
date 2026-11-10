import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit

public struct ImageEngine: ConversionEngine {
    public let identifier = "ImageIO"
    public let availability: EngineAvailability = .ready
    public init() {}

    static let imageFormats: Set<FileFormat> = [.jpeg, .png, .heic]
    static let encoders: Set<FileFormat> = {
        let formats = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        guard let bitmap = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = bitmap.makeImage() else { return [] }
        return Set(imageFormats.filter {
            guard let type = type(for: $0), formats.contains(type.identifier),
                  let data = try? encode(image, format: $0, quality: 0.8),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
            return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        })
    }()

    static func type(for format: FileFormat) -> UTType? {
        switch format {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        default: nil
        }
    }

    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        guard Self.imageFormats.contains(source), source != target else { return false }
        if target == .pdf { return true }
        if target == .docx { return source == .png || source == .jpeg }
        return Self.encoders.contains(target)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        let image = try Self.decode(request.source)
        try Task.checkCancellation()
        switch request.targetFormat {
        case .pdf:
            let scale = min(1, 612 / Double(image.width), 792 / Double(image.height))
            var page = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
            guard let consumer = CGDataConsumer(url: output as CFURL),
                  let pdf = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw WorkerError.invalidOutput }
            pdf.beginPDFPage(nil)
            pdf.setFillColor(CGColor(gray: 1, alpha: 1))
            pdf.fill(page)
            pdf.draw(image, in: page)
            pdf.endPDFPage()
            pdf.closePDF()
        case .docx:
            let format = request.sourceFormat
            let data = try Self.encode(image, format: format, quality: 0.94)
            try await WordWriter.write([.image(data, extensionName: format.fileExtension, width: image.width, height: image.height)], to: output)
        default:
            try Self.encode(image, format: request.targetFormat, quality: 0.86).write(to: output)
        }
    }

    public func validate(output: URL, format: FileFormat) async throws {
        switch format {
        case .pdf:
            guard PDFDocument(url: output)?.pageCount == 1 else { throw WorkerError.invalidOutput }
        case .docx: try await WordWriter.validate(output)
        default:
            guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                  CGImageSourceGetType(source) as String? == Self.type(for: format)?.identifier,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw WorkerError.invalidOutput }
        }
    }

    static func decode(_ input: URL, maximum: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
              let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 64_000_000,
              CGImageSourceGetCount(source) == 1 else { throw WorkerError.invalidInput }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maximum ?? max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw WorkerError.invalidInput }
        return image
    }

    static func encode(_ image: CGImage, format: FileFormat, quality: Double) throws -> Data {
        let prepared: CGImage
        if format == .jpeg || format == .heic {
            guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw WorkerError.invalidOutput }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(bounds)
            ctx.draw(image, in: bounds)
            guard let flattened = ctx.makeImage() else { throw WorkerError.invalidOutput }
            prepared = flattened
        } else {
            prepared = image
        }
        let data = NSMutableData()
        guard let type = type(for: format),
              let encoder = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw WorkerError.invalidOutput }
        let properties: [CFString: Any] = format == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(encoder, prepared, properties as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw WorkerError.invalidOutput }
        return data as Data
    }
}
