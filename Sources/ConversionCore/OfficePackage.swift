import Foundation

enum OfficePackage {
    static func read(_ member: String, in archive: URL, workspace: URL) async throws -> Data {
        // unzip's entry argument is a pattern. Escape wildcard characters for a literal lookup.
        let entry = member.reduce(into: "") { result, character in
            if "[]?*\\".contains(character) { result.append("\\") }
            result.append(character)
        }
        let scratch = workspace.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                        arguments: ["-p", archive.path, entry],
                                        directory: workspace, timeout: .seconds(30),
                                        outputFile: scratch, outputLimit: 64 * 1024 * 1024)
        return try Data(contentsOf: scratch)
    }

    static func write(_ entries: [String: Data], to output: URL) async throws {
        let workspace = output.deletingLastPathComponent()
        let root = workspace.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        for (name, data) in entries {
            let path = root.appendingPathComponent(name)
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: path)
        }
        _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                        arguments: ["-q", output.path] + entries.keys.sorted(),
                                        directory: root, timeout: .seconds(30))
    }

    static func xml(_ data: Data) throws -> XMLDocument {
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard document.dtd == nil else { throw WorkerError.invalidInput }
        return document
    }

    static func escape(_ value: String) -> String {
        let valid = value.unicodeScalars.filter {
            $0.value == 9 || $0.value == 10 || $0.value == 13 ||
            (0x20...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) ||
            (0x10000...0x10FFFF).contains($0.value)
        }
        return String(String.UnicodeScalarView(valid))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum LocalTools {
    static func executable(_ paths: [String]) -> URL? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
}
