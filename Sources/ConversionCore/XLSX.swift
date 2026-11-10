import Foundation

enum XLSX {
    static func write(rows: [[String]], to output: URL) async throws {
        let contentTypes = """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
        """
        let rootRelationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        let workbook = """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let workbookRelationships = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """
        var cells = ""
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            let rowNumber = index + 1
            cells += "<row r=\"\(rowNumber)\">"
            for (column, field) in row.enumerated() {
                // String cells preserve identifiers and never create spreadsheet formulas.
                let reference = columnName(column) + String(rowNumber)
                cells += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(OfficePackage.escape(encodeString(field)))</t></is></c>"
            }
            cells += "</row>"
        }
        let sheet = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultColWidth="18"/><sheetData>\(cells)</sheetData></worksheet>
        """
        let entries = [
            "[Content_Types].xml": contentTypes, "_rels/.rels": rootRelationships,
            "xl/workbook.xml": workbook, "xl/_rels/workbook.xml.rels": workbookRelationships,
            "xl/worksheets/sheet1.xml": sheet,
        ].mapValues { Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + $0).utf8) }
        try await OfficePackage.write(entries, to: output)
    }

    static func read(_ input: URL, workspace: URL) async throws -> [Sheet] {
        func xml(_ name: String) async throws -> XMLDocument {
            try await OfficePackage.xml(OfficePackage.read(name, in: input, workspace: workspace))
        }
        let workbook = try await xml("xl/workbook.xml")
        let relationships = try await xml("xl/_rels/workbook.xml.rels")
        let relationshipNodes = try relationships.nodes(forXPath: "//*[local-name()='Relationship']")
        var targets: [String: String] = [:]
        var sharedPart: String?
        for case let node as XMLElement in relationshipNodes {
            guard node.attribute(forName: "TargetMode")?.stringValue != "External",
                  let target = node.attribute(forName: "Target")?.stringValue,
                  let id = node.attribute(forName: "Id")?.stringValue,
                  let type = node.attribute(forName: "Type")?.stringValue else { continue }
            let part = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard part.hasPrefix("xl/"), !part.split(separator: "/").contains(".."),
                  !part.contains("\\"), !part.contains(":") else { continue }
            if type.hasSuffix("/worksheet") { targets[id] = part }
            if type.hasSuffix("/sharedStrings") { sharedPart = part }
        }
        var shared: [String] = []
        if let sharedPart {
            let strings = try await xml(sharedPart)
            shared = try strings.nodes(forXPath: "//*[local-name()='si']").map {
                try $0.nodes(forXPath: ".//*[local-name()='t' and not(ancestor::*[local-name()='rPh'])]").compactMap(\.stringValue).map(decodeString).joined()
            }
        }
        var sheets: [Sheet] = []
        var cellBudget = 1_000_000
        let nodes = try workbook.nodes(forXPath: "//*[local-name()='sheets']/*[local-name()='sheet']")
        guard !nodes.isEmpty, nodes.count <= 100 else { throw WorkerError.invalidInput }
        for case let node as XMLElement in nodes {
            try Task.checkCancellation()
            guard let name = node.attribute(forName: "name")?.stringValue,
                  let id = node.attributes?.first(where: { $0.localName == "id" })?.stringValue,
                  let part = targets[id] else { throw WorkerError.engineUnavailable("A workbook sheet uses an unsupported relationship.") }
            let worksheet = try await xml(part)
            var rows: [[String]] = []
            for case let row as XMLElement in try worksheet.nodes(forXPath: "//*[local-name()='sheetData']/*[local-name()='row']") {
                try Task.checkCancellation()
                let index = row.attribute(forName: "r")?.stringValue.flatMap { Int($0) } ?? (rows.count + 1)
                guard index > rows.count, index <= 100_000 else { throw WorkerError.invalidInput }
                while rows.count < index - 1 { rows.append([]) }
                var values: [String] = []
                for case let cell as XMLElement in row.children ?? [] where cell.localName == "c" {
                    let ref = cell.attribute(forName: "r")?.stringValue
                    let column = try ref.map(columnIndex) ?? values.count
                    guard column >= values.count, column < 1_024 else { throw WorkerError.invalidInput }
                    let type = cell.attribute(forName: "t")?.stringValue
                    let value = cell.children?.first { $0.localName == "v" }?.stringValue ?? ""
                    let text: String
                    if type == "s" {
                        guard let i = Int(value), shared.indices.contains(i) else { throw WorkerError.invalidInput }
                        text = shared[i]
                    } else if type == "inlineStr" {
                        text = try cell.nodes(forXPath: ".//*[local-name()='t' and not(ancestor::*[local-name()='rPh'])]").compactMap(\.stringValue).map(decodeString).joined()
                    } else if type == "b" {
                        text = type == "str" ? decodeString(value) : value.isEmpty ? "" : (value == "1" ? "TRUE" : "FALSE")
                    } else {
                        text = type == "str" ? decodeString(value) : value
                    }
                    let added = column - values.count + 1
                    cellBudget -= added
                    guard cellBudget >= 0 else { throw WorkerError.engineUnavailable("The workbook exceeds one million cells.") }
                    values += Array(repeating: "", count: added - 1)
                    values.append(text)
                }
                rows.append(values)
            }
            sheets.append(Sheet(name: name, rows: rows))
        }
        return sheets
    }

    private static let escapedCode = try! NSRegularExpression(pattern: "_x([0-9a-fA-F]{4})_")

    private static func encodeString(_ string: String) -> String {
        let literal = escapedCode.stringByReplacingMatches(in: string, range: NSRange(string.startIndex..., in: string),
                                                            withTemplate: "_x005F_x$1_")
        return literal.unicodeScalars.map { scalar in
            if scalar.value == 13 || (scalar.value < 32 && scalar.value != 9 && scalar.value != 10)
                || scalar.value == 0xFFFE || scalar.value == 0xFFFF {
                return String(format: "_x%04X_", scalar.value)
            }
            return String(scalar)
        }.joined()
    }

    private static func decodeString(_ string: String) -> String {
        let utf16 = Array(string.utf16)
        var decoded: [UInt16] = []
        var position = 0
        for match in escapedCode.matches(in: string, range: NSRange(location: 0, length: utf16.count)) {
            let digits = String(decoding: utf16[match.range(at: 1).location..<NSMaxRange(match.range(at: 1))], as: UTF16.self)
            guard let code = UInt16(digits, radix: 16) else { continue }
            decoded.append(contentsOf: utf16[position..<match.range.location])
            decoded.append(code)
            position = NSMaxRange(match.range)
        }
        decoded.append(contentsOf: utf16[position...])
        return String(decoding: decoded, as: UTF16.self)
    }

    private static func columnName(_ index: Int) -> String {
        var number = index + 1
        var result = ""
        while number > 0 {
            number -= 1
            result.insert(Character(UnicodeScalar(65 + number % 26)!), at: result.startIndex)
            number /= 26
        }
        return result
    }

    private static func columnIndex(_ ref: String) throws -> Int {
        let letters = ref.utf8.prefix { (65...90).contains($0) }
        guard !letters.isEmpty, letters.count <= 3 else { throw WorkerError.invalidInput }
        return letters.reduce(0) { $0 * 26 + Int($1) - 64 } - 1
    }
}
