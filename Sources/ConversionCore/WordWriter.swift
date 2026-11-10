import Foundation

enum WordBlock {
    case paragraph(String)
    case pageBreak
    case table([[String]])
    case image(Data, extensionName: String, width: Int, height: Int)
}

enum WordWriter {
    static func write(_ blocks: [WordBlock], to output: URL) async throws {
        var entries: [String: Data] = [:]
        var relationships: [String] = []
        var body = ""
        var imageIndex = 0
        func paragraph(_ text: String) -> String {
            let runs = text.components(separatedBy: "\n").map {
                "<w:t xml:space=\"preserve\">\(OfficePackage.escape($0))</w:t>"
            }.joined(separator: "<w:br/>")
            return "<w:p><w:r>\(runs)</w:r></w:p>"
        }
        for block in blocks {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let text): body += paragraph(text)
            case .pageBreak: body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            case .table(let rows):
                guard let count = rows.map(\.count).max(), count > 0 else { continue }
                let width = max(1, 9360 / count)
                body += "<w:tbl><w:tblPr><w:tblW w:w=\"9360\" w:type=\"dxa\"/><w:tblBorders><w:top w:val=\"single\"/><w:left w:val=\"single\"/><w:bottom w:val=\"single\"/><w:right w:val=\"single\"/><w:insideH w:val=\"single\"/><w:insideV w:val=\"single\"/></w:tblBorders></w:tblPr><w:tblGrid>"
                for _ in 0..<count { body += "<w:gridCol w:w=\"\(width)\"/>" }
                body += "</w:tblGrid>"
                for row in rows {
                    body += "<w:tr>"
                    for index in 0..<count {
                        body += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/></w:tcPr>\(paragraph(index < row.count ? row[index] : ""))</w:tc>"
                    }
                    body += "</w:tr>"
                }
                body += "</w:tbl>"
            case .image(let data, let ext, let width, let height):
                imageIndex += 1
                let filename = "image\(imageIndex).\(ext)"
                let relationship = "rId\(imageIndex)"
                let scale = min(9_525, 5_943_600 / Double(width), 7_772_400 / Double(height))
                let cx = max(1, Int(Double(width) * scale)), cy = max(1, Int(Double(height) * scale))
                entries["word/media/\(filename)"] = data
                relationships.append("<Relationship Id=\"\(relationship)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(filename)\"/>")
                body += """
                <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(imageIndex)" name="Image \(imageIndex)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="\(filename)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationship)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
                """
            }
        }
        func add(_ name: String, _ xml: String) {
            entries[name] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + xml).utf8)
        }
        add("[Content_Types].xml", """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
        """)
        add("_rels/.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """)
        if !relationships.isEmpty {
            add("word/_rels/document.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships.joined())</Relationships>")
        }
        add("word/document.xml", """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>
        """)
        try await OfficePackage.write(entries, to: output)
    }

    static func validate(_ output: URL) async throws {
        let data = try await OfficePackage.read("word/document.xml", in: output, workspace: output.deletingLastPathComponent())
        let xml = try OfficePackage.xml(data)
        guard xml.rootElement()?.localName == "document",
              !(try xml.nodes(forXPath: "//*[local-name()='body']/*[local-name()='p' or local-name()='tbl']")).isEmpty else {
            throw WorkerError.invalidOutput
        }
    }
}
