import AppKit
import ApplicationServices
import ConversionCore

enum DragWheelMode: Equatable {
    case convert, pdfTools

    static var current: Self? {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .pdfTools }
        if flags.contains(.shift) { return .convert }
        return nil
    }
}

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
    private var isStopping = false

    init(registry: EngineRegistry = EngineRegistry()) {
        queue = ConversionQueue(registry: registry)
        target.registry = registry
    }
    private var cachedGeneration: Int?
    private var cachedURLs: [URL] = []
    private var wheelAnchor: NSPoint?
    private var wheelMode: DragWheelMode?

    func start() {
        guard timer == nil, !isStopping else { return }
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
            guard let self, !self.isStopping else { return }
            self.trigger.cancel()
            self.wheelAnchor = nil
            self.target.hide()
            if self.tracked.isEmpty { self.feedback.hide() }
            Task {
                self.submit(requests)
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

    func submit(_ requests: [ConversionRequest]) {
        guard !isStopping else { return }
        let configured = requests.compactMap { request in
            do { return try PDFToolDialog.configure(request) }
            catch {
                NSAlert(error: error).runModal()
                return nil
            }
        }
        guard !configured.isEmpty else { return }
        Task {
            await queue.submit(configured)
            guard !isStopping else { return }
            tracked.append(contentsOf: configured)
            trackJobs()
        }
    }

    func stop() {
        isStopping = true
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
        wheelAnchor = nil
        wheelMode = nil
        target.hide()
        if tracked.isEmpty { feedback.hide() }
    }

    private func tick() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        let mode = DragWheelMode.current
        let generation = pasteboard.changeCount
        let previousURLs = cachedURLs
        // A drag source may publish URLs lazily without advancing changeCount.
        // Read them only while a wheel modifier and the left button are held.
        if !pressed || mode == nil {
            cachedGeneration = nil
            cachedURLs = []
        } else if generation != cachedGeneration || cachedURLs.isEmpty {
            cachedURLs = Self.fileURLs(from: pasteboard)
            cachedGeneration = generation
        }
        let wasVisible = trigger.isVisible
        let visible = trigger.update(pressed: pressed, shift: mode != nil, generation: generation, hasFiles: !cachedURLs.isEmpty)
        if visible, let mode {
            if !wasVisible || cachedURLs != previousURLs || mode != wheelMode {
                let point = wheelAnchor ?? NSEvent.mouseLocation
                wheelAnchor = point
                wheelMode = mode
                let available = target.show(near: point, urls: cachedURLs, mode: mode)
                if tracked.isEmpty {
                    if mode == .pdfTools && !available { feedback.hide() }
                    else { feedback.ready(at: point, fileCount: cachedURLs.count, available: available, tools: mode == .pdfTools) }
                }
            }
        } else if wasVisible {
            wheelAnchor = nil
            wheelMode = nil
            if tracked.isEmpty { feedback.hide() }
            // Let AppKit finish performDragOperation before ordering out the panel.
            if !pressed {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.trigger.isVisible else { return }
                    self.target.hide()
                }
            } else {
                target.hide()
            }
        }
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if urls.isEmpty {
            urls = (pasteboard.pasteboardItems ?? []).compactMap { item in
                guard let value = item.string(forType: .fileURL) else { return nil }
                return URL(string: value)
            }
        }
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
