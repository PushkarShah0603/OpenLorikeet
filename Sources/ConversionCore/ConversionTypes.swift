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

public enum ConversionChoice: Hashable, Sendable {
    case format(FileFormat)
    case compress, fit500KB, resize1600
    case mergePDF, splitPDF, compressPDF, metadataPDF, organizePDF

    public var label: String {
        switch self {
        case .format(let format): format.fileExtension.uppercased()
        case .compress, .compressPDF: "Compress"
        case .fit500KB: "500 KB"
        case .resize1600: "1600 px"
        case .mergePDF: "Merge"
        case .splitPDF: "Split"
        case .metadataPDF: "Metadata"
        case .organizePDF: "Organize"
        }
    }

    public func target(for source: FileFormat) -> FileFormat {
        switch self {
        case .format(let format): format
        case .compress, .fit500KB, .resize1600: source
        case .mergePDF, .splitPDF, .compressPDF, .metadataPDF, .organizePDF: .pdf
        }
    }

    var outputSuffix: String {
        switch self {
        case .format: ""
        case .compress, .compressPDF: " (compressed)"
        case .fit500KB: " (500 KB)"
        case .resize1600: " (1600 px)"
        case .mergePDF: " (merged)"
        case .splitPDF: " (pages)"
        case .metadataPDF: " (metadata)"
        case .organizePDF: " (organized)"
        }
    }
}

public struct PDFMetadata: Sendable {
    public var title: String
    public var author: String
    public var subject: String
    public var keywords: [String]

    public init(title: String = "", author: String = "", subject: String = "", keywords: [String] = []) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
    }
}

public enum PDFOptions: Sendable {
    case metadata(PDFMetadata)
    case pageOrder([Int])

    /// Parses one-based numbers and ranges into zero-based page indices.
    public static func pageIndices(_ text: String, count: Int) throws -> [Int] {
        let error = WorkerError.engineUnavailable("Enter page numbers from 1 to \(count) without repeats. Ranges can run in either direction.")
        var pages: [Int] = []
        var seen = Set<Int>()
        for token in text.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = token.split(separator: "-", omittingEmptySubsequences: false)
            let bounds = parts.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard bounds.count == parts.count, (1...2).contains(parts.count),
                  bounds.allSatisfy({ $0 >= 1 && $0 <= count }),
                  let first = bounds.first, let last = bounds.last else { throw error }
            for page in stride(from: first, through: last, by: first <= last ? 1 : -1) {
                guard seen.insert(page).inserted else { throw error }
                pages.append(page - 1)
            }
        }
        guard !pages.isEmpty else { throw error }
        return pages
    }
}

public struct ConversionRequest: Identifiable, Sendable {
    public let id: UUID
    public let inputs: [URL]
    public var source: URL { inputs[0] }
    public let sourceFormat: FileFormat
    public let targetFormat: FileFormat
    public let choice: ConversionChoice
    public let pdfOptions: PDFOptions?

    public init(source: URL, targetFormat: FileFormat) throws {
        try self.init(inputs: [source], choice: .format(targetFormat))
    }

    public init(inputs: [URL], choice: ConversionChoice, pdfOptions: PDFOptions? = nil) throws {
        guard let source = inputs.first, inputs.allSatisfy(\.isFileURL) else { throw ConversionError.inputMustBeLocalFile }
        guard let format = FileFormat(fileExtension: source.pathExtension) else {
            throw ConversionError.unsupportedInput(source.lastPathComponent)
        }
        if choice == .mergePDF {
            guard inputs.count > 1, Set(inputs.map(\.standardizedFileURL)).count == inputs.count,
                  inputs.allSatisfy({ FileFormat(fileExtension: $0.pathExtension) == .pdf }) else { throw WorkerError.invalidInput }
        } else if inputs.count != 1 {
            throw WorkerError.invalidInput
        }
        self.id = UUID()
        self.inputs = inputs.map(\.standardizedFileURL)
        self.sourceFormat = format
        self.targetFormat = choice.target(for: format)
        self.choice = choice
        self.pdfOptions = pdfOptions
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
    func supports(source: FileFormat, choice: ConversionChoice) -> Bool
    func producesFolder(for request: ConversionRequest) -> Bool
    /// Write only to the supplied staging URL; honor cancellation in long-running work.
    func convert(_ request: ConversionRequest, to stagingURL: URL) async throws
    /// Decode/inspect the output for this format; existence alone is not validation.
    func validate(output: URL, format: FileFormat) async throws
}


public extension ConversionEngine {
    func supports(source: FileFormat, choice: ConversionChoice) -> Bool {
        guard case .format(let target) = choice else { return false }
        return supports(source: source, target: target)
    }

    func producesFolder(for request: ConversionRequest) -> Bool { false }
}
