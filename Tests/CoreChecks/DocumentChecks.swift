import Foundation
import ConversionCore
import PDFKit

func checkDocumentRoutes() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("word-check-\(UUID())")
    let parts = folder.appendingPathComponent("parts")
    try fm.createDirectory(at: parts.appendingPathComponent("word"), withIntermediateDirectories: true)
    try fm.createDirectory(at: parts.appendingPathComponent("_rels"), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let xml: [String: String] = [
        "[Content_Types].xml": """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """,
        "_rels/.rels": """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """,
        "word/document.xml": """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>Unicode café &amp; &lt;tag&gt;</w:t><w:tab/><w:t>column</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Table cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:r><w:br w:type="page"/><w:t>Second page</w:t></w:r></w:p>
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """,
    ]
    for (path, data) in xml { try data.write(to: parts.appendingPathComponent(path), atomically: true, encoding: .utf8) }
    let word = folder.appendingPathComponent("Document with spaces.docx")
    _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                    arguments: ["-q", word.path] + xml.keys.sorted(), directory: parts)
    let queue = ConversionQueue(registry: .local())
    let textJob = try ConversionRequest(source: word, targetFormat: .txt)
    let htmlJob = try ConversionRequest(source: word, targetFormat: .html)
    await queue.submit([textJob, htmlJob])
    await queue.waitUntilIdle()
    guard case .succeeded(let text) = await queue.state(for: textJob.id),
          case .succeeded(let html) = await queue.state(for: htmlJob.id) else {
        let states = await queue.states(for: [textJob.id, htmlJob.id])
        fatalError("Word text/HTML conversion failed: \(states)")
    }
    check(try String(contentsOf: text, encoding: .utf8).contains("Unicode café & <tag>\tcolumn\nTable cell"), "DOCX text preserves order, tabs, Unicode, and entities")
    check(try String(contentsOf: html, encoding: .utf8).contains("&amp; &lt;tag&gt;"), "HTML escapes document text")
    let builtIn = EngineRegistry.local().engineStatuses.contains { $0.name == "macOS Word to PDF" && $0.availability == .ready }
    check(builtIn, "The macOS Word renderer is always registered")
    let pdfJob = try ConversionRequest(source: word, targetFormat: .pdf)
    await queue.submit([pdfJob])
    await queue.waitUntilIdle()
    let pdfState = await queue.state(for: pdfJob.id)
    guard case .succeeded(let pdfURL) = pdfState, let rendered = PDFDocument(url: pdfURL) else {
        fatalError("Word to PDF failed: \(String(describing: pdfState))")
    }
    check(rendered.pageCount == 2 && rendered.page(at: 0)?.string?.contains("Table cell") == true &&
          rendered.page(at: 1)?.string?.contains("Second page") == true, "Word PDF preserves text, tables, and explicit page breaks")
    let damaged = folder.appendingPathComponent("Corrupt.docx")
    try Data("not a ZIP".utf8).write(to: damaged)
    let bad = try ConversionRequest(source: damaged, targetFormat: .txt)
    await queue.submit([bad])
    await queue.waitUntilIdle()
    guard case .failed = await queue.state(for: bad.id) else { fatalError("Corrupt DOCX must fail") }
    if LibreOfficeEngine().availability == .ready {
        let pdf = try ConversionRequest(source: word, targetFormat: .pdf)
        let odt = try ConversionRequest(source: word, targetFormat: .odt)
        await queue.submit([pdf, odt])
        await queue.waitUntilIdle()
        guard case .succeeded(let url) = await queue.state(for: pdf.id),
              case .succeeded = await queue.state(for: odt.id) else { fatalError("LibreOffice export failed") }
        check(PDFDocument(url: url)?.pageCount == 2, "LibreOffice preserves the explicit page break")
    } else {
        print("SKIP: LibreOffice PDF and ODT integration requires LibreOffice")
    }
    print("PASS: native Word text/HTML, escaped Unicode content, damaged input isolation")
}
