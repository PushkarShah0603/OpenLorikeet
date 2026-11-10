import Foundation

/// Formats describe intent, not currently available conversion routes.
public enum FileFormat: String, CaseIterable, Codable, Sendable {
    case docx, pdf, txt, html, odt, markdown, latex, csv, tsv, xlsx
    case jpeg, png, heic

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": self = .jpeg
        case "md", "markdown": self = .markdown
        case "tex": self = .latex
        default:
            guard let format = Self(rawValue: fileExtension.lowercased()) else { return nil }
            self = format
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .markdown: "md"
        case .latex: "tex"
        default: rawValue
        }
    }
}

public enum ConversionError: Error, LocalizedError, Equatable, Sendable {
    case inputMustBeLocalFile
    case unsupportedInput(String)
    case unsupportedRoute(FileFormat, FileFormat)

    public var errorDescription: String? {
        switch self {
        case .inputMustBeLocalFile: "Choose a file on this Mac."
        case .unsupportedInput(let name): "The file format of \(name) is not supported."
        case .unsupportedRoute(let source, let target):
            "Conversion from \(source.rawValue.uppercased()) to \(target.rawValue.uppercased()) is not available."
        }
    }
}

public struct ConversionRequest: Identifiable, Sendable {
    public let id: UUID
    public let source: URL
    public let sourceFormat: FileFormat
    public let targetFormat: FileFormat

    public init(source: URL, targetFormat: FileFormat) throws {
        guard source.isFileURL else { throw ConversionError.inputMustBeLocalFile }
        guard let format = FileFormat(fileExtension: source.pathExtension) else {
            throw ConversionError.unsupportedInput(source.lastPathComponent)
        }
        self.id = UUID()
        self.source = source.standardizedFileURL
        self.sourceFormat = format
        self.targetFormat = targetFormat
    }
}

/// A future engine reports success only after its output has been validated.
public struct ConversionResult: Sendable {
    public let requestID: UUID
    public let outputURLs: [URL]

    public init(requestID: UUID, outputURLs: [URL]) {
        self.requestID = requestID
        self.outputURLs = outputURLs
    }
}

public enum EngineAvailability: Equatable, Sendable {
    case ready
    case unavailable(String)
}

public protocol ConversionEngine: Sendable {
    var identifier: String { get }
    var availability: EngineAvailability { get }
    func supports(source: FileFormat, target: FileFormat) -> Bool
    /// Write only to the supplied staging URL; honor cancellation in long-running work.
    func convert(_ request: ConversionRequest, to stagingURL: URL) async throws
    /// Decode/inspect the output for this format; existence alone is not validation.
    func validate(output: URL, format: FileFormat) throws
}
