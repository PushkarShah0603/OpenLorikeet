import Foundation

public struct EngineRegistry: Sendable {
    private let engines: [any ConversionEngine]

    public init(engines: [any ConversionEngine] = []) { self.engines = engines }

    public var engineStatuses: [(name: String, availability: EngineAvailability)] {
        engines.map { ($0.identifier, $0.availability) }
    }

    public func engine(source: FileFormat, target: FileFormat) -> (any ConversionEngine)? {
        engines.first { $0.availability == .ready && $0.supports(source: source, target: target) }
    }

    func engine(source: FileFormat, choice: ConversionChoice) -> (any ConversionEngine)? {
        engines.first { $0.availability == .ready && $0.supports(source: source, choice: choice) }
    }

    public func choices(for urls: [URL]) -> [ConversionChoice] {
        let formats = urls.compactMap { $0.isFileURL ? FileFormat(fileExtension: $0.pathExtension) : nil }
        guard !formats.isEmpty, formats.count == urls.count else { return [] }
        let formatsOnly = targets(for: urls).map(ConversionChoice.format)
        let actions: [ConversionChoice] = [.compress, .fit500KB, .resize1600, .mergePDF, .splitPDF]
        return formatsOnly + actions.filter { action in
            if action == .mergePDF && urls.count < 2 { return false }
            return formats.allSatisfy { engine(source: $0, choice: action) != nil }
        }
    }

    public func pdfTools(for urls: [URL]) -> [ConversionChoice] {
        guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL && FileFormat(fileExtension: $0.pathExtension) == .pdf }) else { return [] }
        let tools: [ConversionChoice] = urls.count == 1
            ? [.compressPDF, .metadataPDF, .organizePDF, .splitPDF]
            : [.compressPDF, .mergePDF, .splitPDF]
        return tools.filter { engine(source: .pdf, choice: $0) != nil }
    }

    public func targets(for urls: [URL]) -> [FileFormat] {
        guard !urls.isEmpty else { return [] }
        return FileFormat.allCases.filter { target in
            urls.allSatisfy { url in
                guard url.isFileURL, let source = FileFormat(fileExtension: url.pathExtension), source != target else { return false }
                return engine(source: source, target: target) != nil
            }
        }
    }

    public func unavailableReasons(source: FileFormat, target: FileFormat) -> [String] {
        engines.compactMap { engine in
            guard engine.supports(source: source, target: target),
                  case .unavailable(let reason) = engine.availability else { return nil }
            return "\(engine.identifier): \(reason)"
        }
    }
}
