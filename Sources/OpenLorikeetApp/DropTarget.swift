import AppKit
import ConversionCore

@MainActor
final class DropTargetController {
    var registry = EngineRegistry()
    var onDrop: (([ConversionRequest]) -> Void)?
    var onCancel: (() -> Void)?
    var onHover: ((ConversionChoice?, NSPoint) -> Void)?
    private var panel: NSPanel?
    private var view: RadialDropView?

    @discardableResult
    func show(near point: NSPoint, urls: [URL]) -> Bool {
        if panel == nil { makePanel() }
        guard let panel, let view else { return false }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: point.x - 200, y: point.y - 200, width: 400, height: 400)
        panel.setFrame(RadialGeometry.frame(near: point, in: visible), display: false)
        let choices = registry.choices(for: urls)
        view.configure(urls: urls, choices: choices)
        panel.orderFrontRegardless()
        return !choices.isEmpty
    }

    func hide() { panel?.orderOut(nil) }

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
    var onHover: ((ConversionChoice?, NSPoint) -> Void)?
    private var session = PickerSession(sources: [])
    private var selected: Int? {
        didSet {
            needsDisplay = true
            updateAccessibility()
            if let selected {
                let angle = Double(selected) * 2 * .pi / Double(session.choices.count)
                onHover?(session.choices[selected], NSPoint(x: sin(angle), y: cos(angle)))
            } else if oldValue != nil {
                onHover?(nil, .zero)
            }
        }
    }
    private var geometry: RadialGeometry {
        RadialGeometry(center: CGPoint(x: bounds.midX, y: bounds.midY), innerRadius: bounds.width * 0.23,
                       outerRadius: bounds.width / 2 - 8, count: session.choices.count)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { nil }

    func configure(urls: [URL], choices: [ConversionChoice]) {
        session = PickerSession(sources: urls, choices: choices)
        selected = nil
        needsDisplay = true
    }

    private func updateAccessibility() {
        let label = selected.map { session.choices[$0].label } ?? "Choose an available format"
        setAccessibilityLabel("OpenLorikeet. \(label).")
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry
        let n = session.choices.count
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
                drawCentered(session.choices[index].label,
                             at: CGPoint(x: g.center.x + cos(theta) * radius, y: g.center.y + sin(theta) * radius),
                             size: n > 7 ? 10 : 13, color: .white)
            }
        }
        let disk = NSRect(x: g.center.x - g.innerRadius + 5, y: g.center.y - g.innerRadius + 5,
                          width: g.innerRadius * 2 - 10, height: g.innerRadius * 2 - 10)
        NSColor(calibratedWhite: 0.08, alpha: 0.98).setFill()
        NSBezierPath(ovalIn: disk).fill()
        let title = selected.map { session.choices[$0].label } ?? (n == 0 ? "No formats" : "Choose format")
        drawCentered(title, at: CGPoint(x: g.center.x, y: g.center.y + 12), size: n > 7 ? 10 : 13, color: .white)
        drawCentered(n == 0 ? "Check selected files" : "Drop on a format",
                     at: CGPoint(x: g.center.x, y: g.center.y - 9), size: 10, color: .lightGray)
    }

    private func drawCentered(_ text: String, at point: CGPoint, size: Double, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: color]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
    }

    private func updateSelection(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !session.consumed, NSEvent.modifierFlags.contains(.shift),
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
            guard let requests = try session.select(session.choices[selected], droppedURLs: DragMonitor.fileURLs(from: sender.draggingPasteboard)) else { return false }
            onDrop?(requests)
            return true
        } catch { return false }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
