import AppKit
import ConversionCore

@MainActor
final class ConversionFeedback: NSObject {
    private let bird = LorikeetView(frame: .zero)
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel batch", target: nil, action: nil)
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var outputs: [URL] = []
    private var screen: NSScreen?
    var onCancel: (() -> Void)?

    func ready(at point: NSPoint, fileCount: Int, available: Bool) {
        screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let heading = available ? "Choose an output format" : "No available formats"
        let detail = available ? "\(fileCount) selected"
            : (fileCount > 1 ? "Choose files that share an output format." : "Check Conversion engines in the menu bar.")
        show(title: heading, detail: detail, pose: .ready)
    }

    func hover(_ choice: ConversionChoice?, look: NSPoint) {
        title.stringValue = choice.map { $0.label } ?? "Choose an output format"
        bird.look = look
    }

    func progress(completed: Int, total: Int) {
        show(title: "Converting \(total) \(total == 1 ? "file" : "files")",
             detail: "\(completed) of \(total) finished", pose: .working, cancellable: true)
    }

    func finish(states: [JobState], requests: [ConversionRequest]) {
        let urls = states.compactMap { state -> URL? in
            if case .succeeded(let url) = state { return url }
            return nil
        }
        let failures = zip(states, requests).compactMap { state, request -> String? in
            if case .failed(let message) = state { return request.source.lastPathComponent + " · " + message }
            return nil
        }
        let cancelled = states.filter { $0 == .cancelled }.count
        if let first = failures.first {
            show(title: "\(urls.count) saved, \(failures.count) failed", detail: first, pose: .failed, outputs: urls)
        } else if cancelled > 0 {
            show(title: "\(cancelled) cancelled", detail: "\(urls.count) converted copies saved",
                 pose: .ready, outputs: urls)
        } else {
            var message = urls.count == 1 ? urls[0].lastPathComponent : "Saved beside the originals"
            if urls.count == 1, let request = requests.first,
               [.compress, .fit500KB].contains(request.choice),
               let original = try? request.source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               let saved = try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize, original > saved {
                message = "Saved " + ByteCountFormatter.string(fromByteCount: Int64(original - saved), countStyle: .file)
            }
            show(title: urls.count == 1 ? "Conversion complete" : "\(urls.count) files converted",
                 detail: message, pose: .happy, outputs: urls)
        }
        if failures.isEmpty {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(urls.isEmpty ? 2 : 8))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        bird.stop()
        panel?.orderOut(nil)
        outputs = []
    }

    private func show(title heading: String, detail message: String, pose: LorikeetView.Pose,
                      outputs: [URL] = [], cancellable: Bool = false) {
        dismissTask?.cancel()
        dismissTask = nil
        if panel == nil { makePanel() }
        guard let panel, let display = screen ?? NSScreen.main else { return }
        title.stringValue = heading
        detail.stringValue = message
        self.outputs = outputs
        openButton.isHidden = outputs.count != 1
        revealButton.isHidden = outputs.isEmpty
        cancelButton.isHidden = !cancellable
        let frame = display.visibleFrame
        let width = min(384, frame.width - 16)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - 116, width: width, height: 108), display: false)
        if !panel.isVisible || bird.pose != pose { bird.animate(pose) }
        panel.orderFrontRegardless()
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 384, height: 108),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .withinWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        let dismiss = NSButton(title: "Close", target: self, action: #selector(closePanel))
        for (button, action) in [(openButton, #selector(openOutput)), (revealButton, #selector(revealOutputs)), (cancelButton, #selector(cancelJobs))] {
            button.target = self
            button.action = action
        }
        let buttons = NSStackView(views: [openButton, revealButton, cancelButton, dismiss])
        buttons.spacing = 5
        for button in [openButton, revealButton, cancelButton, dismiss] { button.controlSize = .small }
        let labels = NSStackView(views: [title, detail, buttons])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let row = NSStackView(views: [bird, labels])
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            bird.widthAnchor.constraint(equalToConstant: 66),
            bird.heightAnchor.constraint(equalToConstant: 82),
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        self.panel = panel
    }

    @objc private func openOutput() { if let first = outputs.first { NSWorkspace.shared.open(first) } }
    @objc private func revealOutputs() { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    @objc private func cancelJobs() { onCancel?() }
    @objc private func closePanel() { hide() }
}

@MainActor
private final class LorikeetView: NSView {
    enum Pose { case ready, working, happy, failed }
    private(set) var pose: Pose = .ready
    var look = NSPoint.zero { didSet { needsDisplay = true } }
    private var timer: Timer?
    private var began = ProcessInfo.processInfo.systemUptime

    func animate(_ pose: Pose) {
        stop()
        self.pose = pose
        look = .zero
        began = ProcessInfo.processInfo.systemUptime
        needsDisplay = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, pose != .failed else { return }
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.needsDisplay = true
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ||
                    (self.pose == .happy && ProcessInfo.processInfo.systemUptime - self.began > 1.7) { self.stop() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }

    override func draw(_ dirtyRect: NSRect) {
        let t = timer == nil ? 0 : ProcessInfo.processInfo.systemUptime - began
        let jump = pose == .happy && timer != nil ? max(0, sin(t * 10)) * max(0, 1 - t) * 8 : 0
        let bob = timer == nil ? 0 : sin(t * 4) * 1.4
        let peek = timer != nil && pose == .ready ? 12 * max(0, 1 - t / 0.22) : 0
        let offset = jump + bob - peek
        func oval(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y + offset, width: w, height: h)).fill()
        }
        let wing = pose == .happy && timer != nil ? sin(t * 22) * 5 : 0
        oval(13, 13, 39, 36, .systemGreen)
        oval(21, 16, 27, 28, .systemOrange)
        oval(12, 15 + wing, 18, 26, .systemGreen.blended(withFraction: 0.3, of: .black) ?? .systemGreen)
        let direction = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? NSPoint.zero : look
        let headOffset = pose == .failed ? -3.0 : direction.x * 3
        oval(14 + headOffset, 37, 39, 35, .systemBlue)
        oval(40 + headOffset, 44, 18, 10, .systemOrange)
        let blink = timer != nil && t.truncatingRemainder(dividingBy: 3.1) > 2.95
        oval(38 + headOffset, 53, 10, blink ? 2 : 10, .white)
        if !blink { oval(41 + headOffset + direction.x * 2, 55 + direction.y * 2, 5, 5, .black) }
        if pose == .happy && timer != nil && UserDefaults.standard.object(forKey: "FeatherCelebrations") as? Bool != false {
            for index in 0..<7 {
                let age = t - Double(index) * 0.085
                guard age > 0, age < 1.15 else { continue }
                let x = 7 + Double(index) * 8 + sin(age * 6 + Double(index)) * 4
                let y = 74 - age * 57
                let colors: [NSColor] = [.systemTeal, .systemOrange, .systemBlue, .systemGreen]
                colors[index % colors.count].withAlphaComponent(max(0, 1 - age / 1.15)).setFill()
                let feather = NSBezierPath()
                feather.move(to: NSPoint(x: x, y: y))
                feather.curve(to: NSPoint(x: x + 5, y: y + 12),
                              controlPoint1: NSPoint(x: x + 7, y: y + 2), controlPoint2: NSPoint(x: x + 8, y: y + 9))
                feather.curve(to: NSPoint(x: x, y: y),
                              controlPoint1: NSPoint(x: x + 1, y: y + 10), controlPoint2: NSPoint(x: x - 3, y: y + 4))
                feather.close()
                feather.fill()
            }
        }
    }
}
