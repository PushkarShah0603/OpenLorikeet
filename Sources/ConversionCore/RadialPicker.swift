import Foundation
import CoreGraphics

/// Planned choices for interaction prototyping, not an executable capability registry.
public enum PlannedChoices {
    public static func targets(for source: FileFormat) -> [FileFormat] {
        switch source {
        case .docx: [.pdf, .txt, .html, .odt, .markdown, .latex]
        case .pdf: [.docx, .txt, .jpeg, .png]
        case .csv: [.xlsx, .pdf, .tsv]
        case .tsv: [.xlsx, .pdf, .csv]
        case .xlsx: [.pdf, .csv, .tsv]
        case .markdown: [.html, .docx, .latex, .pdf]
        case .latex: [.pdf]
        case .jpeg: [.png, .heic, .pdf, .docx]
        case .png: [.jpeg, .heic, .pdf, .docx]
        case .heic: [.jpeg, .png, .pdf]
        case .txt, .html, .odt: []
        }
    }

    public static func commonTargets(for urls: [URL]) -> [FileFormat] {
        let formats = urls.compactMap { FileFormat(fileExtension: $0.pathExtension) }
        guard formats.count == urls.count, let first = formats.first else { return [] }
        return targets(for: first).filter { target in
            formats.allSatisfy { targets(for: $0).contains(target) }
        }
    }
}

public struct PickerSession: Sendable {
    public let sources: [URL]
    public let targets: [FileFormat]
    public private(set) var consumed = false

    public init(sources: [URL]) {
        self.sources = sources
        targets = PlannedChoices.commonTargets(for: sources)
    }

    /// Capture a drop once, only if the source set still matches the active drag.
    public mutating func select(_ target: FileFormat, droppedURLs: [URL]) throws -> [ConversionRequest]? {
        guard !consumed, targets.contains(target), sources.count == droppedURLs.count,
              Set(sources.map(\.standardizedFileURL)) == Set(droppedURLs.map(\.standardizedFileURL)) else { return nil }
        let requests = try sources.map { try ConversionRequest(source: $0, targetFormat: target) }
        consumed = true
        return requests
    }
}

public struct RadialGeometry: Sendable {
    public let center: CGPoint
    public let innerRadius: Double
    public let outerRadius: Double
    public let count: Int
    public let gapRadians: Double

    public init(center: CGPoint, innerRadius: Double, outerRadius: Double, count: Int, gapRadians: Double = 0.06) {
        self.center = center
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.count = count
        self.gapRadians = gapRadians
    }

    /// Index zero is at 12 o'clock; subsequent segments proceed clockwise.
    public func segment(at point: CGPoint) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x, dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let step = 2 * Double.pi / Double(count)
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        let index = Int(floor((angle + step / 2) / step)) % count
        let distance = abs(atan2(sin(angle - Double(index) * step), cos(angle - Double(index) * step)))
        guard distance <= step / 2 - gapRadians / 2 else { return nil }
        return index
    }

    public static func frame(near point: CGPoint, in screen: CGRect) -> CGRect {
        let available = screen.insetBy(dx: 8, dy: 8)
        let side = max(1, min(340, available.width, available.height))
        return CGRect(
            x: min(max(point.x - side / 2, available.minX), available.maxX - side),
            y: min(max(point.y - side / 2, available.minY), available.maxY - side),
            width: side, height: side
        )
    }
}
