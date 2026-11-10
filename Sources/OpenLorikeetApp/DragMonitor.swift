import AppKit
import ApplicationServices
import ConversionCore

/// Observes without consuming Finder events. No Accessibility prompt is raised.
@MainActor
final class DragMonitor {
    private var timer: Timer?
    private var escapeMonitor: Any?
    private var localMonitor: Any?
    private var trigger = DragTrigger()
    private let pasteboard = NSPasteboard(name: .drag)
    private let target = DropTargetController()
    private var cachedGeneration: Int?
    private var cachedURLs: [URL] = []
    private var anchor: NSPoint?

    func start() {
        guard timer == nil else { return }
        // Prime the baseline before accepting a gesture.
        tick()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.cancel() }
            }
            return event
        }
        // Global key monitoring is optional and only installed with existing trust.
        if AXIsProcessTrusted() {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    MainActor.assumeIsolated { self?.cancel() }
                }
            }
        }
        target.onDrop = { [weak self] urls in
            self?.trigger.cancel()
            self?.anchor = nil
            self?.target.showReceipt(count: urls.count)
        }
        target.onCancel = { [weak self] in self?.cancel() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        escapeMonitor = nil
        localMonitor = nil
        cancel()
    }

    private func cancel() {
        trigger.cancel()
        anchor = nil
        target.hide()
    }

    private func tick() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let generation = pasteboard.changeCount
        // Read drag metadata only; the general clipboard is never read.
        if generation != cachedGeneration {
            cachedURLs = Self.fileURLs(from: pasteboard)
            cachedGeneration = generation
        }
        let wasVisible = trigger.isVisible
        let visible = trigger.update(
            pressed: pressed, shift: NSEvent.modifierFlags.contains(.shift),
            generation: generation, hasFiles: !cachedURLs.isEmpty
        )
        if visible {
            if !wasVisible {
                anchor = NSEvent.mouseLocation
                target.show(near: anchor!, count: cachedURLs.count)
            }
        } else if wasVisible {
            // Let AppKit finish performDragOperation before ordering out the panel.
            if !pressed {
                DispatchQueue.main.async { [weak self] in self?.target.hideUnlessReceipt() }
            } else {
                target.hideUnlessReceipt()
            }
            anchor = nil
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalized = url.standardizedFileURL
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &directory),
                  !directory.boolValue, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}
