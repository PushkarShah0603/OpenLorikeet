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
    private let queue: ConversionQueue
    private let feedback = ConversionFeedback()
    private var tracked: [ConversionRequest] = []
    private var trackingTask: Task<Void, Never>?

    init(registry: EngineRegistry = EngineRegistry()) {
        queue = ConversionQueue(registry: registry)
        target.registry = registry
    }
    private var cachedGeneration: Int?
    private var cachedURLs: [URL] = []

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
        target.onDrop = { [weak self] requests in
            guard let self else { return }
            self.trigger.cancel()
            self.target.hide()
            Task {
                await self.queue.submit(requests)
                self.tracked.append(contentsOf: requests)
                self.trackJobs()
            }
        }
        target.onCancel = { [weak self] in self?.cancel() }
        target.onHover = { [weak self] format, look in
            guard let self, self.tracked.isEmpty else { return }
            self.feedback.hover(format, look: look)
        }
        feedback.onCancel = { [weak self] in
            guard let self else { return }
            Task { await self.queue.cancelAll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        escapeMonitor = nil
        localMonitor = nil
        cancel()
        trackingTask?.cancel()
        trackingTask = nil
        feedback.hide()
    }

    private func trackJobs() {
        guard trackingTask == nil else { return }
        trackingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let requests = self.tracked
                let ids = requests.map(\.id)
                let states = await self.queue.states(for: ids)
                guard !Task.isCancelled else { return }
                if ids != self.tracked.map(\.id) { continue }
                let completed = states.filter { $0 != .running && $0 != .queued }.count
                if completed == states.count {
                    self.tracked.removeAll()
                    self.trackingTask = nil
                    self.feedback.finish(states: states, requests: requests)
                    return
                }
                self.feedback.progress(completed: completed, total: states.count)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func cancelJobsAndWait() async {
        await queue.shutdown()
        await queue.waitUntilIdle()
    }

    private func cancel() {
        trigger.cancel()
        target.hide()
        if tracked.isEmpty { feedback.hide() }
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
                let point = NSEvent.mouseLocation
                let available = target.show(near: point, urls: cachedURLs)
                if tracked.isEmpty { feedback.ready(at: point, fileCount: cachedURLs.count, available: available) }
            }
        } else if wasVisible {
            if tracked.isEmpty { feedback.hide() }
            // Let AppKit finish performDragOperation before ordering out the panel.
            if !pressed {
                DispatchQueue.main.async { [weak self] in self?.target.hide() }
            } else {
                target.hide()
            }
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
