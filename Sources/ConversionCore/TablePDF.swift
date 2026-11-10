import Foundation
import CoreGraphics
import CoreText

enum TablePDF {
    static func write(_ sheets: [Sheet], to output: URL) throws {
        var page = CGRect(x: 0, y: 0, width: 792, height: 612)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw WorkerError.invalidOutput }
        let margin = 34.0, lineHeight = 13.0, cellPadding = 5.0
        var y = 0.0
        var pageOpen = false
        defer {
            if pageOpen { context.endPDFPage() }
            context.closePDF()
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let bold = CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil)
        func makeLines(_ string: String, width: Double, heading: Bool) -> [CTLine] {
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): heading ? bold : font,
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: heading ? 1 : 0.13, alpha: 1),
            ]
            let text = NSAttributedString(string: string.isEmpty ? " " : string, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var index = 0
            var lines: [CTLine] = []
            while index < text.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, index, width))
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: index, length: count)))
                index += count
            }
            return lines
        }
        func drawRow(_ cells: [[CTLine]], start: Int, count: Int, width: Double, header: Bool, alternating: Bool) {
            let height = Double(count) * lineHeight + 2 * cellPadding
            for (column, lines) in cells.enumerated() {
                let x = margin + Double(column) * width
                let box = CGRect(x: x, y: y - height, width: width, height: height)
                context.setFillColor(header ? CGColor(red: 0.12, green: 0.23, blue: 0.32, alpha: 1)
                                           : CGColor(gray: alternating ? 0.95 : 1, alpha: 1))
                context.fill(box)
                context.setStrokeColor(CGColor(gray: 0.82, alpha: 1))
                context.setLineWidth(0.35)
                context.stroke(box)
                context.saveGState()
                context.clip(to: box)
                for offset in 0..<count where start + offset < lines.count {
                    context.textPosition = CGPoint(x: x + cellPadding, y: y - cellPadding - 10 - Double(offset) * lineHeight)
                    CTLineDraw(lines[start + offset], context)
                }
                context.restoreGState()
            }
            y -= height
        }
        for sheet in sheets {
            let columns = max(1, sheet.rows.map(\.count).max() ?? 0)
            for startColumn in stride(from: 0, to: columns, by: 6) {
                try Task.checkCancellation()
                let endColumn = min(startColumn + 6, columns)
                let width = (page.width - 2 * margin) / Double(endColumn - startColumn)
                func lines(_ row: [String], header: Bool) -> [[CTLine]] {
                    (startColumn..<endColumn).map { column in
                        makeLines(column < row.count ? row[column] : "", width: width - 2 * cellPadding, heading: header)
                    }
                }
                let header = lines(sheet.rows.first ?? ["Empty sheet"], header: true)
                let headerCount = header.map(\.count).max() ?? 1
                guard headerCount <= 20 else { throw WorkerError.engineUnavailable("A column heading is too long for the page.") }
                func nextPage() {
                    if pageOpen { context.endPDFPage() }
                    context.beginPDFPage(nil)
                    pageOpen = true
                    context.textMatrix = .identity
                    y = page.height - margin
                    let heading = columns > 6 ? "\(sheet.name)   Columns \(startColumn + 1)–\(endColumn)" : sheet.name
                    for line in makeLines(heading, width: page.width - 2 * margin, heading: false).prefix(2) {
                        context.textPosition = CGPoint(x: margin, y: y)
                        CTLineDraw(line, context)
                        y -= lineHeight
                    }
                    y -= 9
                    drawRow(header, start: 0, count: headerCount, width: width, header: true, alternating: false)
                }
                nextPage()
                for (index, row) in sheet.rows.dropFirst().enumerated() {
                    try Task.checkCancellation()
                    let cells = lines(row, header: false)
                    var offset = 0
                    let total = cells.map(\.count).max() ?? 1
                    while offset < total {
                        var room = Int((y - margin - 2 * cellPadding) / lineHeight)
                        if room <= 0 {
                            nextPage()
                            room = Int((y - margin - 2 * cellPadding) / lineHeight)
                        }
                        let count = min(room, total - offset)
                        drawRow(cells, start: offset, count: count, width: width, header: false, alternating: index % 2 == 1)
                        offset += count
                    }
                }
            }
        }
    }
}
