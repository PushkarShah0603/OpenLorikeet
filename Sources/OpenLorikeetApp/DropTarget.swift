import AppKit
import ConversionCore

@MainActor
final class DropTargetController {
    var registry = EngineRegistry()
    var onDrop: (([ConversionRequest]) -> Void)?
    var onCancel: (() -> Void)?
    var onHover: ((FileFormat?, Double) -> Void)?
    private var panel: NSPanel?
    private var view: RadialDropView?
    private var receiptTask: Task<Void, Never>?
    private var showingReceipt = false

    func show(near point: NSPoint, urls: [URL]) {
        receiptTask?.cancel()
        showingReceipt = false
        if panel == nil { makePanel() }
        guard let panel, let view else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: point.x - 200, y: point.y - 200, width: 400, height: 400)
        panel.setFrame(RadialGeometry.frame(near: point, in: visible), display: false)
        view.configure(urls: urls, targets: registry.targets(for: urls))
        panel.orderFrontRegardless()
    }

    func showReceipt(requests: [ConversionRequest]) {
        showingReceipt = true
        view?.receipt = "\(requests.count) → \(requests.first?.targetFormat.fileExtension.uppercased() ?? "")"
        receiptTask?.cancel()
        receiptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hideUnlessReceipt() { if !showingReceipt { hide() } }

    func hide() {
        receiptTask?.cancel()
        receiptTask = nil
        showingReceipt = false
        panel?.orderOut(nil)
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 340),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = RadialDropView(frame: NSRect(x: 0, y: 0, width: 340, height: 340))
        view.autoresizingMask = [.width, .height]
        view.onDrop = { [weak self] requests in self?.onDrop?(requests) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        view.onHover = { [weak self] format, look in self?.onHover?(format, look) }
        panel.contentView = view
        self.panel = panel
        self.view = view
    }
}

@MainActor
private final class RadialDropView: NSView {
    var onDrop: (([ConversionRequest]) -> Void)?
    var onCancel: (() -> Void)?
    var onHover: ((FileFormat?, Double) -> Void)?
    var receipt: String? { didSet { needsDisplay = true } }
    private var session = PickerSession(sources: [])
    private var selected: Int? {
        didSet {
            needsDisplay = true
            updateAccessibility()
            if let selected {
                let angle = Double(selected) * 2 * .pi / Double(session.targets.count)
                onHover?(session.targets[selected], sin(angle))
            } else if oldValue != nil {
                onHover?(nil, 0)
            }
        }
    }
    private var geometry: RadialGeometry {
        RadialGeometry(center: CGPoint(x: bounds.midX, y: bounds.midY), innerRadius: bounds.width * 0.23,
                       outerRadius: bounds.width / 2 - 8, count: session.targets.count)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { nil }

    func configure(urls: [URL], targets: [FileFormat]) {
        session = PickerSession(sources: urls, targets: targets)
        receipt = nil
        selected = nil
        needsDisplay = true
    }

    private func updateAccessibility() {
        let label = selected.map { session.targets[$0].fileExtension.uppercased() } ?? "Choose a planned format"
        setAccessibilityLabel("OpenLorikeet. \(label).")
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry
        let n = session.targets.count
        if n > 0 {
            let step = 360.0 / Double(n)
            let gap = g.gapRadians * 180 / .pi
            for index in 0..<n {
                let angle = 90 - Double(index) * step
                let start = angle + step / 2 - gap / 2
                let end = angle - step / 2 + gap / 2
                let path = NSBezierPath()
                path.appendArc(withCenter: g.center, radius: g.outerRadius, startAngle: start, endAngle: end, clockwise: true)
                path.appendArc(withCenter: g.center, radius: g.innerRadius, startAngle: end, endAngle: start, clockwise: false)
                path.close()
                (selected == index ? NSColor.systemGreen.withAlphaComponent(0.9)
                                  : NSColor(calibratedWhite: 0.14, alpha: 0.96)).setFill()
                path.fill()
                let theta = angle * .pi / 180
                let radius = (g.innerRadius + g.outerRadius) / 2
                drawCentered(session.targets[index].fileExtension.uppercased(),
                             at: CGPoint(x: g.center.x + cos(theta) * radius, y: g.center.y + sin(theta) * radius),
                             size: 13, color: .white)
            }
        }
        let disk = NSRect(x: g.center.x - g.innerRadius + 5, y: g.center.y - g.innerRadius + 5,
                          width: g.innerRadius * 2 - 10, height: g.innerRadius * 2 - 10)
        NSColor(calibratedWhite: 0.08, alpha: 0.98).setFill()
        NSBezierPath(ovalIn: disk).fill()
        let title = receipt ?? selected.map { session.targets[$0].fileExtension.uppercased() }
            ?? (n == 0 ? "No engines" : "Choose format")
        drawCentered(title, at: CGPoint(x: g.center.x, y: g.center.y + 12), size: 13, color: .white)
        drawCentered(receipt == nil ? "Choose output" : "Queued", at: CGPoint(x: g.center.x, y: g.center.y - 8), size: 10, color: .systemYellow)
        drawCentered(receipt == nil ? (n == 0 ? "Engines required" : "Drop on a format") : "Processing pending", at: CGPoint(x: g.center.x, y: g.center.y - 25), size: 9, color: .lightGray)
    }

    private func drawCentered(_ text: String, at point: CGPoint, size: Double, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
    }

    private func updateSelection(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard receipt == nil, !session.consumed, NSEvent.modifierFlags.contains(.shift),
              sender.draggingSourceOperationMask.contains(.copy) else {
            selected = nil
            return []
        }
        selected = geometry.segment(at: convert(sender.draggingLocation, from: nil))
        return selected == nil ? [] : .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateSelection(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateSelection(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { selected = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { updateSelection(sender) == .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard updateSelection(sender) == .copy, let selected else { return false }
        do {
            guard let requests = try session.select(session.targets[selected], droppedURLs: DragMonitor.fileURLs(from: sender.draggingPasteboard)) else { return false }
            onDrop?(requests)
            return true
        } catch { return false }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
