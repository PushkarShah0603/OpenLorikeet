import AppKit
import ConversionCore

@MainActor
enum PDFToolDialog {
    static func configure(_ request: ConversionRequest) throws -> ConversionRequest? {
        guard request.choice == .metadataPDF || request.choice == .organizePDF else { return request }
        let info = try PDFEngine().editingInfo(for: request.source)
        let alert = NSAlert()
        alert.messageText = request.choice == .metadataPDF ? "PDF metadata" : "Organize PDF pages"
        alert.addButton(withTitle: "Save Copy")
        alert.addButton(withTitle: "Cancel")

        let options: PDFOptions
        if request.choice == .metadataPDF {
            alert.informativeText = request.source.lastPathComponent
            let metadata = info.metadata
            let originalKeywords = metadata.keywords.joined(separator: ", ")
            let fields = [metadata.title, metadata.author, metadata.subject, originalKeywords]
                .map(NSTextField.init(string:))
            let labels = ["Title", "Author", "Subject", "Keywords (comma-separated)"]
            alert.accessoryView = form(labels: labels, fields: fields)
            alert.window.initialFirstResponder = fields[0]
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let keywords = fields[3].stringValue == originalKeywords ? metadata.keywords
                : fields[3].stringValue.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            options = .metadata(PDFMetadata(title: fields[0].stringValue, author: fields[1].stringValue,
                                            subject: fields[2].stringValue, keywords: keywords))
        } else {
            alert.informativeText = "Choose which of the \(info.pages) pages to keep, in the order you want."
            let field = NSTextField(string: info.pages == 1 ? "1" : "1-\(info.pages)")
            alert.accessoryView = form(labels: ["Page order, such as 3, 1-2"], fields: [field])
            alert.window.initialFirstResponder = field
            NSApp.activate()
            while true {
                guard alert.runModal() == .alertFirstButtonReturn else { return nil }
                do {
                    options = try .pageOrder(PDFOptions.pageIndices(field.stringValue, count: info.pages))
                    break
                } catch {
                    alert.informativeText = error.localizedDescription
                }
            }
        }
        return try ConversionRequest(inputs: request.inputs, choice: request.choice, pdfOptions: options)
    }

    private static func form(labels: [String], fields: [NSTextField]) -> NSView {
        let rows = zip(labels, fields).flatMap { label, field -> [NSView] in
            let caption = NSTextField(labelWithString: label)
            caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            field.setAccessibilityLabel(label)
            return [caption, field]
        }
        let form = NSStackView(views: rows)
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 5
        form.frame.size = NSSize(width: 310, height: CGFloat(fields.count) * 46)
        for field in fields { field.widthAnchor.constraint(equalToConstant: 310).isActive = true }
        return form
    }
}
