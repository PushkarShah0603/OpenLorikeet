import Foundation

struct Sheet {
    let name: String
    let rows: [[String]]
}

enum DelimitedTable {
    static func read(_ input: URL, delimiter: Character) throws -> [[String]] {
        let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 32 * 1024 * 1024 else { throw WorkerError.invalidInput }
        var text = try String(contentsOf: input, encoding: .utf8)
        if text.first == "\u{FEFF}" { text.removeFirst() }
        return try parse(text, delimiter: delimiter)
    }

    static func parse(_ text: String, delimiter: Character) throws -> [[String]] {
        enum Mode { case beginning, plain, quoted, quoteEnded }
        var mode = Mode.beginning
        var rows: [[String]] = [], row: [String] = []
        var field = ""
        var cellCount = 0
        func addField() throws {
            cellCount += 1
            guard row.count < 1_024, cellCount <= 1_000_000, field.utf16.count <= 32_767 else {
                throw WorkerError.engineUnavailable("The table exceeds the supported row, column, or cell size.")
            }
            row.append(field)
            field = ""
            mode = .beginning
        }
        func addRow() throws {
            try Task.checkCancellation()
            try addField()
            guard rows.count < 100_000 else { throw WorkerError.invalidInput }
            rows.append(row)
            row = []
        }
        for character in text {
            let newline = character == "\n" || character == "\r" || character == "\r\n"
            if mode == .quoted {
                if character == "\"" { mode = .quoteEnded } else { field.append(character) }
            } else if mode == .quoteEnded && character == "\"" {
                field.append("\"")
                mode = .quoted
            } else if character == delimiter {
                try addField()
            } else if newline {
                try addRow()
            } else if mode == .beginning && character == "\"" {
                mode = .quoted
            } else {
                guard mode != .quoteEnded, character != "\"" else {
                    throw WorkerError.engineUnavailable("Malformed quoted field on row \(rows.count + 1).")
                }
                field.append(character)
                mode = .plain
            }
        }
        guard mode != .quoted else { throw WorkerError.engineUnavailable("An opening quote has no closing quote.") }
        if !row.isEmpty || mode != .beginning { try addRow() }
        guard !rows.isEmpty else { throw WorkerError.invalidInput }
        return rows
    }

    static func write(_ rows: [[String]], delimiter: Character, to output: URL) throws {
        let encoded = try rows.map { row in
            try Task.checkCancellation()
            return row.map { field in
                if field.contains(delimiter) || field.contains("\"") || field.contains(where: \.isNewline) {
                    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return field
            }.joined(separator: String(delimiter))
        }.joined(separator: "\r\n") + "\r\n"
        try encoded.write(to: output, atomically: true, encoding: .utf8)
    }
}
