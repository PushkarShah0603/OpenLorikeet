import Foundation
import PDFKit
import ConversionCore

func checkTableRoutes() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("table-check-\(UUID())")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Wide table.csv")
    let header = "Identifier,Long ID,Name,Details,Formula,City,Region,Last column"
    let data = "000123,9999999999999999999,\"café, quoted\",\"First line\r\nSecond line\",=1+2,Ahmedabad,Gujarat,Final value _x0041_"
    try (header + "\r\n" + Array(repeating: data, count: 58).joined(separator: "\r\n") + "\r\n")
        .write(to: source, atomically: true, encoding: .utf8)
    let queue = ConversionQueue(registry: .local())
    let workbook = try ConversionRequest(source: source, targetFormat: .xlsx)
    let pdf = try ConversionRequest(source: source, targetFormat: .pdf)
    await queue.submit([workbook, pdf])
    await queue.waitUntilIdle()
    let first = await queue.states(for: [workbook.id, pdf.id])
    guard case .succeeded(let book) = first[0], case .succeeded(let pages) = first[1] else { fatalError("Table routes failed: \(first)") }
    guard let rendered = PDFDocument(url: pages) else { fatalError("Unreadable table PDF") }
    check(rendered.pageCount > 2, "Wide, tall tables paginate")
    check(rendered.string?.contains("Identifier") == true && rendered.string?.contains("Final value") == true, "PDF includes first and last columns")
    let sheet = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", book.path, "xl/worksheets/sheet1.xml"], directory: folder)
    check(sheet.stdout.contains("t=\"inlineStr\"") && !sheet.stdout.contains("<f>"), "XLSX uses string cells for formula-like inputs")
    let back = try ConversionRequest(source: book, targetFormat: .csv)
    let tsv = try ConversionRequest(source: book, targetFormat: .tsv)
    await queue.submit([back, tsv])
    await queue.waitUntilIdle()
    let second = await queue.states(for: [back.id, tsv.id])
    guard case .succeeded(let csvFolder) = second[0], case .succeeded(let tsvFolder) = second[1] else { fatalError("Spreadsheet export failed: \(second)") }
    let files = try fm.contentsOfDirectory(at: csvFolder, includingPropertiesForKeys: nil)
    check(files.count == 1, "One output per sheet")
    let recovered = try String(contentsOf: files[0], encoding: .utf8)
    check(recovered.contains(data), "Leading zeros, long IDs, Unicode, quoted delimiters and newlines round-trip")
    check(try fm.contentsOfDirectory(at: tsvFolder, includingPropertiesForKeys: nil).first?.pathExtension == "tsv", "TSV export")
    let multi = folder.appendingPathComponent("Two sheets.xlsx")
    try fm.copyItem(at: book, to: multi)
    let parts = folder.appendingPathComponent("extra-parts")
    let additions: [String: (String, String)] = [
        "[Content_Types].xml": ("</Types>", "<Override PartName=\"/xl/worksheets/sheet2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"),
        "xl/workbook.xml": ("</sheets>", "<sheet name=\"Cached values\" sheetId=\"2\" r:id=\"rId2\"/></sheets>"),
        "xl/_rels/workbook.xml.rels": ("</Relationships>", "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet2.xml\"/></Relationships>"),
    ]
    for (name, replacement) in additions {
        let output = parts.appendingPathComponent(name)
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let escaped = name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let original = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                   arguments: ["-p", book.path, escaped], directory: folder)
        try original.stdout.replacingOccurrences(of: replacement.0, with: replacement.1).write(to: output, atomically: true, encoding: .utf8)
    }
    let sheetPart = "xl/worksheets/sheet2.xml"
    let sheetFile = parts.appendingPathComponent(sheetPart)
    try fm.createDirectory(at: sheetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Cached formula result</t></is></c></row>
    <row r="2"><c r="A2"><f>1+2</f><v>3</v></c></row>
    </sheetData></worksheet>
    """.write(to: sheetFile, atomically: true, encoding: .utf8)
    _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                    arguments: ["-q", multi.path] + additions.keys.sorted() + [sheetPart], directory: parts)
    let multiCSV = try ConversionRequest(source: multi, targetFormat: .csv)
    let multiPDF = try ConversionRequest(source: multi, targetFormat: .pdf)
    await queue.submit([multiCSV, multiPDF])
    await queue.waitUntilIdle()
    let multiStates = await queue.states(for: [multiCSV.id, multiPDF.id])
    guard case .succeeded(let sheetFolder) = multiStates[0],
          case .succeeded(let sheetPDF) = multiStates[1] else { fatalError("Multi-sheet export failed: \(multiStates)") }
    let sheetFiles = try fm.contentsOfDirectory(at: sheetFolder, includingPropertiesForKeys: nil)
    check(sheetFiles.count == 2, "Multi-sheet XLSX exports separate tables")
    let cached = try String(contentsOf: sheetFolder.appendingPathComponent("2 - Cached values.csv"), encoding: .utf8)
    check(cached == "Cached formula result\r\n3\r\n", "Export uses the formula's stored result")
    check(PDFDocument(url: sheetPDF)?.string?.contains("Cached formula result") == true, "PDF includes the second sheet")
    let bad = folder.appendingPathComponent("Malformed.csv")
    try Data("A,B\n\"unterminated".utf8).write(to: bad)
    let malformed = try ConversionRequest(source: bad, targetFormat: .xlsx)
    await queue.submit([malformed])
    await queue.waitUntilIdle()
    guard case .failed = await queue.state(for: malformed.id) else { fatalError("Malformed CSV must fail") }
    print("PASS: spreadsheet round-trip, formula-like strings, malformed CSV, multi-sheet export, cached values, and wide/long PDF pagination")
}
