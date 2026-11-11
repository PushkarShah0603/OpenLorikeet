import AppKit
import ConversionCore

@MainActor
final class ConversionFeedback: NSObject {
    private lazy var bird = LorikeetView(frame: .zero)
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel batch", target: nil, action: nil)
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var outputs: [URL] = []
    private var progressDismissed = false
    private var screen: NSScreen?
    private var readyHeading = "Choose an output format"
    var onCancel: (() -> Void)?

    func ready(at point: NSPoint, fileCount: Int, available: Bool, tools: Bool) {
        progressDismissed = false
        screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        readyHeading = available ? (tools ? "Choose a PDF tool" : "Choose an output format") : "No available formats"
        let detail = available ? "\(fileCount) selected"
            : (fileCount > 1 ? "Choose files that share an output format." : "Check Conversion engines in the menu bar.")
        show(title: readyHeading, detail: detail, pose: .ready)
    }

    func hover(_ choice: ConversionChoice?, look: NSPoint) {
        title.stringValue = choice.map { $0.label } ?? readyHeading
        bird.look = look
    }

    func progress(completed: Int, total: Int) {
        guard !progressDismissed else { return }
        show(title: "Converting \(total) \(total == 1 ? "file" : "files")",
             detail: "\(completed) of \(total) finished", pose: .working, cancellable: true)
    }

    func finish(states: [JobState], requests: [ConversionRequest]) {
        progressDismissed = false
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
            let suffix = cancelled > 0 ? ", \(cancelled) cancelled" : ""
            show(title: "\(urls.count) saved, \(failures.count) failed" + suffix, detail: first, pose: .failed, outputs: urls)
        } else if cancelled > 0 {
            show(title: "\(cancelled) cancelled", detail: "\(urls.count) converted copies saved",
                 pose: .ready, outputs: urls)
        } else {
            var message = urls.count == 1 ? urls[0].lastPathComponent : "Saved beside the originals"
            if urls.count == 1, let request = requests.first,
               [.compress, .fit500KB, .compressPDF].contains(request.choice),
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
        if let panel {
            bird.stop()
            panel.orderOut(nil)
        }
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
        let width = min(412, frame.width - 16)
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - 132, width: width, height: 124), display: false)
        if !panel.isVisible || bird.pose != pose { bird.animate(pose) }
        panel.orderFrontRegardless()
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 412, height: 124),
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
            bird.widthAnchor.constraint(equalToConstant: 112),
            bird.heightAnchor.constraint(equalToConstant: 108),
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
    @objc private func closePanel() {
        if !cancelButton.isHidden { progressDismissed = true }
        hide()
    }
}
