import AppKit
import ImageIO

/// macOS Word import can discard DrawingML pictures. Preserve their positions with
/// text markers, then supply decoded attachments directly to the text layout engine.
enum WordPictures {
    struct Picture {
        let marker: String
        let data: Data
        let size: NSSize
        let maximumCellWidth: Double?
        let crop: CGRect
    }

    static func prepare(document: XMLDocument, source: URL, workspace: URL) async throws -> (URL, [Picture]) {
        // Unsupported compatibility drawings can also cause Word import to skip
        // the runs that follow them. Retain textbox labels as ordinary text.
        for alternate in elements(named: "AlternateContent", in: document) {
            guard elements(named: "blip", in: alternate).isEmpty,
                  let parent = alternate.parent as? XMLElement,
                  let index = parent.children?.firstIndex(where: { $0 === alternate }) else { continue }
            let choice = alternate.children?.first { $0.localName == "Choice" } ?? alternate
            let label = elements(named: "t", in: choice).compactMap(\.stringValue).joined()
            let prefix = document.rootElement()?.prefix.map { $0 + ":" } ?? ""
            let replacement = XMLElement(name: prefix + "t", uri: document.rootElement()?.uri)
            replacement.stringValue = label
            parent.replaceChild(at: index, with: replacement)
        }
        let drawings = elements(named: "drawing", in: document)
        let pictures = drawings.filter { !elements(named: "blip", in: $0).isEmpty }
        guard !pictures.isEmpty else { return (source, []) }
        guard pictures.count <= 1_000 else { throw WorkerError.invalidInput }
        let relationships = try await OfficePackage.xml(OfficePackage.read(
            "word/_rels/document.xml.rels", in: source, workspace: workspace
        ))
        var targets: [String: String] = [:]
        for relationship in elements(named: "Relationship", in: relationships) {
            guard relationship.attribute(forName: "Type")?.stringValue?.hasSuffix("/image") == true,
                  relationship.attribute(forName: "TargetMode")?.stringValue != "External",
                  let id = relationship.attribute(forName: "Id")?.stringValue,
                  let target = relationship.attribute(forName: "Target")?.stringValue else { continue }
            let member = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            guard member.hasPrefix("word/media/"), !member.split(separator: "/").contains(".."),
                  !member.contains("\\"), !member.contains(":") else { throw WorkerError.invalidInput }
            targets[id] = member
        }
        var result: [Picture] = []
        var cache: [String: Data] = [:]
        var totalBytes = 0
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        for drawing in pictures {
            try Task.checkCancellation()
            let blips = elements(named: "blip", in: drawing)
            // Grouped drawing layouts need an Office renderer to preserve their composition.
            guard blips.count == 1, let blip = blips.first,
                  let id = blip.attributes?.first(where: { $0.localName == "embed" })?.stringValue,
                  let member = targets[id] else {
                throw WorkerError.engineUnavailable("This Word drawing needs LibreOffice for PDF export. Install LibreOffice and relaunch OpenLorikeet.")
            }
            let data: Data
            if let cached = cache[member] {
                data = cached
            } else {
                data = try await OfficePackage.read(member, in: source, workspace: workspace)
                totalBytes += data.count
                guard totalBytes <= 100 * 1024 * 1024 else { throw WorkerError.invalidInput }
                cache[member] = data
            }
            let extent = elements(named: "extent", in: drawing).first
            let width = extent?.attribute(forName: "cx")?.stringValue.flatMap(Double.init).map { $0 / 12_700 } ?? 0
            let height = extent?.attribute(forName: "cy")?.stringValue.flatMap(Double.init).map { $0 / 12_700 } ?? 0
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw WorkerError.invalidInput }
            let transform = elements(named: "xfrm", in: drawing).first
            guard transform?.attribute(forName: "rot")?.stringValue.flatMap(Int.init) ?? 0 == 0,
                  transform?.attribute(forName: "flipH")?.stringValue != "1",
                  transform?.attribute(forName: "flipV")?.stringValue != "1" else {
                throw WorkerError.engineUnavailable("Rotated Word pictures need LibreOffice for PDF export.")
            }
            let rectangle = elements(named: "srcRect", in: drawing).first
            func inset(_ name: String) -> Double {
                (rectangle?.attribute(forName: name)?.stringValue.flatMap(Double.init) ?? 0) / 100_000
            }
            let crop = CGRect(x: inset("l"), y: inset("t"),
                              width: 1 - inset("l") - inset("r"), height: 1 - inset("t") - inset("b"))
            guard crop.minX >= 0, crop.minY >= 0, crop.maxX <= 1, crop.maxY <= 1,
                  crop.width > 0, crop.height > 0 else { throw WorkerError.invalidInput }
            var ancestor = drawing.parent
            while ancestor != nil, ancestor?.localName != "tc" { ancestor = ancestor?.parent }
            let cell = ancestor.flatMap { elements(named: "tcW", in: $0).first }
            let cellType = cell?.attributes?.first(where: { $0.localName == "type" })?.stringValue
            var cellWidth: Double?
            if cellType == "dxa",
               let widthText = cell?.attributes?.first(where: { $0.localName == "w" })?.stringValue,
               let widthTwips = Double(widthText), widthTwips > 240 {
                cellWidth = widthTwips / 20 - 12
            }
            let marker = "LORIKEETPICTURE" + token + "P" + String(result.count) + "END"
            result.append(Picture(marker: marker, data: data, size: NSSize(width: width, height: height),
                                  maximumCellWidth: cellWidth, crop: crop))
            guard let parent = drawing.parent as? XMLElement,
                  let index = parent.children?.firstIndex(where: { $0 === drawing }) else { throw WorkerError.invalidInput }
            let prefix = drawing.prefix.map { $0 + ":" } ?? ""
            let text = XMLElement(name: prefix + "t", uri: drawing.uri)
            text.stringValue = marker
            parent.replaceChild(at: index, with: text)
        }
        let parts = workspace.appendingPathComponent("word-picture-parts", isDirectory: true)
        try FileManager.default.createDirectory(at: parts.appendingPathComponent("word"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parts) }
        try document.xmlData.write(to: parts.appendingPathComponent("word/document.xml"))
        let copy = workspace.appendingPathComponent("word-pictures.docx")
        try FileManager.default.copyItem(at: source, to: copy)
        _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zip"),
                                        arguments: ["-q", copy.path, "word/document.xml"], directory: parts)
        return (copy, result)
    }

    private static func elements(named name: String, in root: XMLNode) -> [XMLElement] {
        var remaining = (root.children ?? []).reversed().map { $0 }
        var result: [XMLElement] = []
        while let node = remaining.popLast() {
            if node.localName == name, let element = node as? XMLElement { result.append(element) }
            remaining.append(contentsOf: (node.children ?? []).reversed())
        }
        return result
    }

    static func restore(_ pictures: [Picture], in text: NSMutableAttributedString, contentSize: NSSize) throws {
        for picture in pictures {
            try Task.checkCancellation()
            let range = (text.string as NSString).range(of: picture.marker)
            guard range.location != NSNotFound else {
                throw WorkerError.engineUnavailable("The Word importer lost a picture position. Use LibreOffice for this document.")
            }
            guard let source = CGImageSourceCreateWithData(picture.data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 64_000_000,
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw WorkerError.engineUnavailable("An embedded Word image could not be decoded within the image size limits.")
            }
            let bounds = CGRect(x: picture.crop.minX * Double(width), y: picture.crop.minY * Double(height),
                                width: picture.crop.width * Double(width), height: picture.crop.height * Double(height))
            guard let image = decoded.cropping(to: bounds) else {
                throw WorkerError.engineUnavailable("An embedded Word image has invalid cropping bounds.")
            }
            let maximumWidth = min(contentSize.width, picture.maximumCellWidth ?? contentSize.width)
            let scale = min(1, maximumWidth / picture.size.width, (contentSize.height - 36) / picture.size.height)
            guard scale.isFinite, scale > 0 else { throw WorkerError.invalidInput }
            let size = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
            let attachment = NSTextAttachment()
            attachment.image = NSImage(cgImage: image, size: size)
            attachment.bounds = CGRect(origin: .zero, size: size)
            let replacement = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            // Keep table-cell paragraph formatting and alignment from the imported text.
            if let paragraph = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) {
                replacement.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: replacement.length))
            }
            text.replaceCharacters(in: range, with: replacement)
        }
    }
}
