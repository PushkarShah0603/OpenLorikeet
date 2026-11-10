import Foundation
import PDFKit

public struct WordTextEngine: ConversionEngine {
    public let identifier = "Word text extraction"
    public let availability: EngineAvailability = .ready
    public init() {}

    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        source == .docx && (target == .txt || target == .html)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        let document = try await OfficePackage.xml(OfficePackage.read("word/document.xml", in: request.source,
                                                                     workspace: output.deletingLastPathComponent()))
        guard document.rootElement()?.localName == "document" else { throw WorkerError.invalidInput }
        let paragraphs = try document.nodes(forXPath: "//*[local-name()='body']//*[local-name()='p']")
        let lines = try paragraphs.map { paragraph in
            try Task.checkCancellation()
            return try paragraph.nodes(forXPath: ".//*[local-name()='t' or local-name()='tab' or local-name()='br']").map { node in
                switch node.localName {
                case "tab": "\t"
                case "br": "\n"
                default: node.stringValue ?? ""
                }
            }.joined()
        }
        let result: String
        if request.targetFormat == .html {
            let body = lines.map { "<p>\(OfficePackage.escape($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }.joined(separator: "\n")
            result = "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>\(OfficePackage.escape(request.source.deletingPathExtension().lastPathComponent))</title></head><body>\(body)</body></html>\n"
        } else {
            result = lines.joined(separator: "\n") + "\n"
        }
        try result.write(to: output, atomically: true, encoding: .utf8)
    }

    public func validate(output: URL, format: FileFormat) throws {
        let text = try String(contentsOf: output, encoding: .utf8)
        guard !text.isEmpty, format != .html || text.hasPrefix("<!doctype html>") else { throw WorkerError.invalidOutput }
    }
}

public struct LibreOfficeEngine: ConversionEngine {
    public let identifier = "LibreOffice"
    private let executable: URL?
    public init() {
        self.init(executable: LocalTools.executable([
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice",
        ]))
    }
    public init(executable: URL?) { self.executable = executable }

    public var availability: EngineAvailability {
        executable.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true
            ? .ready : .unavailable("Install LibreOffice to export formatted Word documents.")
    }

    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        source == .docx && (target == .pdf || target == .odt)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        guard let executable else { throw WorkerError.engineUnavailable("Install LibreOffice.") }
        let workspace = output.deletingLastPathComponent()
        let profile = workspace.appendingPathComponent("office-profile", isDirectory: true)
        let folder = workspace.appendingPathComponent("office-output", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let filter = request.targetFormat == .pdf ? "pdf:writer_pdf_Export" : "odt:writer8"
        let result = try await ProcessRunner.run(executable: executable, arguments: [
            "-env:UserInstallation=\(profile.absoluteString)", "--headless", "--norestore",
            "--convert-to", filter, "--outdir", folder.path, request.source.path,
        ], directory: workspace)
        let produced = folder.appendingPathComponent(request.source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(request.targetFormat.fileExtension)
        guard FileManager.default.fileExists(atPath: produced.path) else {
            let details = [result.stderr, result.stdout].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkerError.engineUnavailable(details.isEmpty ? "LibreOffice created no output. Check that the document opens in LibreOffice." : details)
        }
        try FileManager.default.moveItem(at: produced, to: output)
    }

    public func validate(output: URL, format: FileFormat) async throws {
        if format == .pdf {
            guard let pdf = PDFDocument(url: output), pdf.pageCount > 0, !pdf.isLocked else { throw WorkerError.invalidOutput }
        } else {
            let mime = try await OfficePackage.read("mimetype", in: output, workspace: output.deletingLastPathComponent())
            guard String(decoding: mime, as: UTF8.self) == "application/vnd.oasis.opendocument.text" else { throw WorkerError.invalidOutput }
        }
    }
}

public extension EngineRegistry {
    static func local() -> Self { Self(engines: [LibreOfficeEngine(), WordTextEngine(), ImageEngine(), SpreadsheetEngine(), PDFEngine(), PandocEngine(), TectonicEngine()]) }
}
