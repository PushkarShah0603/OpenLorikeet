import AppKit

@MainActor
final class DropTargetController {
    var onDrop: (([URL]) -> Void)?
    var onCancel: (() -> Void)?
    private var panel: NSPanel?
    private var view: FileDropView?
    private var receiptTask: Task<Void, Never>?
    private var showingReceipt = false

    func show(near point: NSPoint, count: Int) {
        receiptTask?.cancel()
        showingReceipt = false
        if panel == nil { makePanel() }
        guard let panel, let view else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: point.x - 200, y: point.y - 100, width: 400, height: 200)
        let size = panel.frame.size
        // Offset to let the user move onto the target; do not swallow the active pointer.
        let x = min(max(point.x + 24, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(point.y - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        view.message = "Drop \(count == 1 ? "file" : "\(count) files") here"
        view.detail = "Gesture prototype · conversion comes later"
        view.acceptsFiles = true
        view.highlighted = false
        panel.orderFrontRegardless()
    }

    func showReceipt(count: Int) {
        showingReceipt = true
        view?.acceptsFiles = false
        view?.highlighted = false
        view?.message = "Received \(count == 1 ? "1 file" : "\(count) files")"
        view?.detail = "Gesture confirmed · no files changed"
        receiptTask?.cancel()
        receiptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hideUnlessReceipt() {
        if !showingReceipt { hide() }
    }

    func hide() {
        receiptTask?.cancel()
        receiptTask = nil
        showingReceipt = false
        panel?.orderOut(nil)
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let view = FileDropView(frame: NSRect(x: 0, y: 0, width: 310, height: 100))
        view.onDrop = { [weak self] urls in self?.onDrop?(urls) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        panel.contentView = view
        self.panel = panel
        self.view = view
    }
}

@MainActor
private final class FileDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onCancel: (() -> Void)?
    var acceptsFiles = true
    var message = "Drop file here" { didSet { needsDisplay = true } }
    var detail = "" { didSet { needsDisplay = true } }
    var highlighted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("OpenLorikeet temporary file drop target")
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: highlighted ? 0.18 : 0.10, alpha: 0.97).setFill()
        shape.fill()
        (highlighted ? NSColor.systemGreen : NSColor.darkGray).setStroke()
        shape.lineWidth = 2
        shape.stroke()
        (message as NSString).draw(at: NSPoint(x: 18, y: 53), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: NSColor.white,
        ])
        (detail as NSString).draw(at: NSPoint(x: 18, y: 25), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.lightGray,
        ])
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        acceptsFiles && NSEvent.modifierFlags.contains(.shift)
            && sender.draggingSourceOperationMask.contains(.copy)
            && !DragMonitor.fileURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = canAccept(sender)
        return highlighted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { canAccept(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAccept(sender) else { return false }
        let urls = DragMonitor.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        acceptsFiles = false
        onDrop?(urls)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}
