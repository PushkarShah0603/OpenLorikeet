import Foundation

public struct EngineRegistry: Sendable {
    private let engines: [any ConversionEngine]

    public init(engines: [any ConversionEngine] = []) { self.engines = engines }

    public func engine(source: FileFormat, target: FileFormat) -> (any ConversionEngine)? {
        engines.first { $0.availability == .ready && $0.supports(source: source, target: target) }
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
