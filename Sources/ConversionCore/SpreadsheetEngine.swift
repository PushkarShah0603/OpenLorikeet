import Foundation
import PDFKit

public struct SpreadsheetEngine: ConversionEngine {
    public let identifier = "Local spreadsheet converter"
    public let availability: EngineAvailability = .ready
    public init() {}

    public func supports(source: FileFormat, target: FileFormat) -> Bool {
        switch source {
        case .csv: [.tsv, .xlsx, .pdf].contains(target)
        case .tsv: [.csv, .xlsx, .pdf].contains(target)
        case .xlsx: [.csv, .tsv, .pdf].contains(target)
        default: false
        }
    }

    public func producesFolder(for request: ConversionRequest) -> Bool {
        request.sourceFormat == .xlsx && [.csv, .tsv].contains(request.targetFormat)
    }

    public func convert(_ request: ConversionRequest, to output: URL) async throws {
        let sheets: [Sheet]
        if request.sourceFormat == .xlsx {
            sheets = try await XLSX.read(request.source, workspace: output.deletingLastPathComponent())
        } else {
            let rows = try DelimitedTable.read(request.source, delimiter: request.sourceFormat == .csv ? "," : "\t")
            sheets = [Sheet(name: request.source.deletingPathExtension().lastPathComponent, rows: rows)]
        }
        switch request.targetFormat {
        case .xlsx: try await XLSX.write(rows: sheets[0].rows, to: output)
        case .pdf: try TablePDF.write(sheets, to: output)
        case .csv, .tsv:
            let delimiter: Character = request.targetFormat == .csv ? "," : "\t"
            if producesFolder(for: request) {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                for (index, sheet) in sheets.enumerated() {
                    let safe = sheet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    let file = output.appendingPathComponent("\(index + 1) - \(safe.prefix(64))").appendingPathExtension(request.targetFormat.fileExtension)
                    try DelimitedTable.write(sheet.rows, delimiter: delimiter, to: file)
                }
            } else {
                try DelimitedTable.write(sheets[0].rows, delimiter: delimiter, to: output)
            }
        default: throw WorkerError.invalidInput
        }
    }

    public func validate(output: URL, format: FileFormat) async throws {
        switch format {
        case .xlsx:
            guard !(try await XLSX.read(output, workspace: output.deletingLastPathComponent())).isEmpty else { throw WorkerError.invalidOutput }
        case .pdf:
            guard let pdf = PDFDocument(url: output), pdf.pageCount > 0 else { throw WorkerError.invalidOutput }
        case .csv, .tsv:
            let delimiter: Character = format == .csv ? "," : "\t"
            let files = output.hasDirectoryPath ? try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil) : [output]
            guard !files.isEmpty else { throw WorkerError.invalidOutput }
            for file in files { _ = try DelimitedTable.read(file, delimiter: delimiter) }
        default: throw WorkerError.invalidOutput
        }
    }
}
