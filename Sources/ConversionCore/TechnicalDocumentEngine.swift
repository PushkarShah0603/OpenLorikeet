import Foundation
import ImageIO
import PDFKit

public struct TectonicEngine: ConversionEngine {
    public let identifier = "Tectonic"
    private let executable: URL?
    public init() {
        executable = LocalTools.executable(["/opt/homebrew/bin/tectonic", "/usr/local/bin/tectonic", "/opt/local/bin/tectonic"])
    }
    public var availability: EngineAvailability {
        executable == nil ? .unavailable("Install Tectonic and cache your project’s TeX packages.") : .ready
    }
    public func supports(source: FileFormat, target: FileFormat) -> Bool { source == .latex && target == .pdf }
    public func convert(_ request: ConversionRequest, to output: URL) async throws { try await compile(request.source, to: output) }

    func compile(_ source: URL, to output: URL) async throws {
        guard let executable else { throw WorkerError.engineUnavailable("Install Tectonic to compile PDF.") }
        let workspace = output.deletingLastPathComponent()
        let folder = workspace.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            _ = try await ProcessRunner.run(executable: executable, arguments: [
                "-X", "compile", "--only-cached", "--untrusted", "--outdir", folder.path, source.path,
            ], directory: source.deletingLastPathComponent())
        } catch ProcessFailure.failed(let code, let message) {
            throw ProcessFailure.failed(code, "Offline TeX compilation failed. Check project files and cached packages.\n\(message)")
        }
        let pdf = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("pdf")
        try FileManager.default.moveItem(at: pdf, to: output)
    }

    public func validate(output: URL, format: FileFormat) throws {
        guard let pdf = PDFDocument(url: output), pdf.pageCount > 0, !pdf.isLocked else { throw WorkerError.invalidOutput }
    }
}

public struct PandocEngine: ConversionEngine {
    public let identifier = "Pandoc"
    private let executable = LocalTools.executable(["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc", "/opt/local/bin/pandoc"])
    private let tectonic = TectonicEngine()
    public init() {}
    public var availability: EngineAvailability {
        executable == nil ? .unavailable("Install Pandoc for Markdown and LaTeX document export.") : .ready
    }
    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        switch source {
        case .docx: [.markdown, .latex].contains(target)
        case .markdown: [.docx, .html, .latex].contains(target) || (target == .pdf && tectonic.availability == .ready)
        case .latex: [.docx, .markdown].contains(target)
        default: false
        }
    }
    public func producesFolder(for request: ConversionRequest) -> Bool {
        [.markdown, .latex].contains(request.targetFormat)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        guard let executable else { throw WorkerError.engineUnavailable("Install Pandoc.") }
        let fm = FileManager.default
        let workspace = output.deletingLastPathComponent()
        let folder: URL
        if producesFolder(for: request) {
            folder = output
        } else {
            folder = workspace.appendingPathComponent("pandoc", isDirectory: true)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let target = request.targetFormat == .pdf ? .latex : request.targetFormat
        let result = (producesFolder(for: request) || request.targetFormat == .pdf)
            ? folder.appendingPathComponent("document.\(target.fileExtension)") : output
        let writer = target == .html ? "html5" : target.rawValue
        if request.sourceFormat == .docx {
            _ = try await ProcessRunner.run(executable: executable, arguments: [
                "--sandbox", "--from=docx", "--to=\(writer)", "--standalone",
                "--extract-media=assets", "--fail-if-warnings", "--output", result.path, request.source.path,
            ], directory: folder)
        } else {
            // Parse with Pandoc's sandbox and resolve image references ourselves.
            let intermediate = workspace.appendingPathComponent("pandoc-input.json")
            let reader = request.sourceFormat == .markdown ? "markdown-raw_html-raw_tex" : "latex"
            _ = try await ProcessRunner.run(executable: executable, arguments: [
                "--sandbox", "--from=\(reader)", "--to=json", "--fail-if-warnings",
                "--output", intermediate.path, request.source.path,
            ], directory: folder)
            let size = try intermediate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 32 * 1024 * 1024 else { throw WorkerError.invalidInput }
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: intermediate))
            guard var document = raw as? [String: Any], let blocks = document["blocks"] else { throw WorkerError.invalidInput }
            let inputRoot = request.source.deletingLastPathComponent().resolvingSymlinksInPath()
            var imageCount = 0
            var imageBytes = 0
            func rewrite(_ value: Any) throws -> Any {
                try Task.checkCancellation()
                if let list = value as? [Any] { return try list.map(rewrite) }
                guard var node = value as? [String: Any] else { return value }
                if node["t"] as? String == "Image",
                   var content = node["c"] as? [Any], let last = content.indices.last,
                   let pair = content[last] as? [String], pair.count == 2 {
                    let link = pair[0]
                    guard let decoded = link.removingPercentEncoding, !decoded.isEmpty,
                          !decoded.hasPrefix("/"), !decoded.contains(":"), !decoded.contains("\\") else {
                        throw WorkerError.engineUnavailable("Document images must be local files inside the source folder.")
                    }
                    let url = inputRoot.appendingPathComponent(decoded).resolvingSymlinksInPath().standardizedFileURL
                    guard url.path.hasPrefix(inputRoot.path + "/"),
                          let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                          size.isRegularFile == true, let bytes = size.fileSize,
                          bytes > 0, bytes <= 12 * 1024 * 1024 else {
                        throw WorkerError.engineUnavailable("An image is missing, outside the source folder, or too large.")
                    }
                    imageBytes += bytes
                    imageCount += 1
                    guard imageBytes <= 48 * 1024 * 1024, imageCount <= 100,
                          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let uti = CGImageSourceGetType(source) as String?,
                          ["public.png", "public.jpeg"].contains(uti) else {
                        throw WorkerError.engineUnavailable("Use local PNG or JPEG images within the document size limits.")
                    }
                    let png = uti == "public.png"
                    let data = try Data(contentsOf: url)
                    let rewritten: String
                    if target == .html || target == .docx {
                        rewritten = "data:image/\(png ? "png" : "jpeg");base64,\(data.base64EncodedString())"
                    } else {
                        let assets = folder.appendingPathComponent("assets", isDirectory: true)
                        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
                        let name = "image-\(imageCount).\(png ? "png" : "jpg")"
                        try data.write(to: assets.appendingPathComponent(name))
                        rewritten = "assets/" + name
                    }
                    content[last] = [rewritten, pair[1]]
                    node["c"] = content
                    return node
                }
                if let tag = node["t"] as? String, tag == "RawBlock" || tag == "RawInline" {
                    throw WorkerError.engineUnavailable("Raw embedded markup is unsupported in this export.")
                }
                for (key, item) in node { node[key] = try rewrite(item) }
                return node
            }
            document["blocks"] = try rewrite(blocks)
            // Writer metadata can reference external templates and resources.
            document["meta"] = [:]
            try JSONSerialization.data(withJSONObject: document).write(to: intermediate)
            _ = try await ProcessRunner.run(executable: executable, arguments: [
                "--sandbox", "--from=json", "--to=\(writer)", "--standalone",
                "--fail-if-warnings", "--output", result.path, intermediate.path,
            ], directory: folder)
        }
        if request.targetFormat == .pdf { try await tectonic.compile(result, to: output) }
    }

    public func validate(output: URL, format: FileFormat) async throws {
        switch format {
        case .pdf: try tectonic.validate(output: output, format: .pdf)
        case .docx: try await WordWriter.validate(output)
        default:
            let file = output.hasDirectoryPath ? output.appendingPathComponent("document.\(format.fileExtension)") : output
            let text = try String(contentsOf: file, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkerError.invalidOutput }
        }
    }
}
