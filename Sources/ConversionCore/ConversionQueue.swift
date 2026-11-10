import Foundation
import Darwin

public enum WorkerError: Error, LocalizedError, Sendable {
    case engineUnavailable(String)
    case timedOut
    case invalidOutput
    case invalidInput
    case publishFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable(let message): message
        case .timedOut: "Conversion exceeded its time limit."
        case .invalidOutput: "The engine did not produce a valid, nonempty file."
        case .invalidInput: "The source file is missing, unreadable, or not a regular file."
        case .publishFailed(let code): "Could not save the converted copy (system error \(code))."
        }
    }
}

public enum JobState: Equatable, Sendable {
    case queued, running, succeeded(URL), failed(String), cancelled
}

public actor ConversionQueue {
    private let registry: EngineRegistry
    private let limit: Int
    private let timeout: Duration
    private var pending: [ConversionRequest] = []
    private var active: [UUID: Task<Void, Never>] = [:]
    private var states: [UUID: JobState] = [:]
    private var accepting = true
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(registry: EngineRegistry, concurrency: Int = 2, timeout: Duration = .seconds(120)) {
        self.registry = registry
        limit = max(1, concurrency)
        self.timeout = timeout
    }

    /// Repeated submission of the same request ID cannot create duplicate work.
    public func submit(_ requests: [ConversionRequest]) {
        guard accepting else { return }
        for request in requests where states[request.id] == nil {
            states[request.id] = .queued
            pending.append(request)
        }
        pump()
    }

    public func state(for id: UUID) -> JobState? { states[id] }

    public func states(for ids: [UUID]) -> [JobState] { ids.map { states[$0] ?? .queued } }

    public func cancel(_ id: UUID) {
        if let task = active[id] {
            task.cancel()
        } else if states[id] == .queued {
            pending.removeAll { $0.id == id }
            states[id] = .cancelled
            notifyIdle()
        }
    }

    public func cancelAll() {
        for request in pending { states[request.id] = .cancelled }
        pending.removeAll()
        for task in active.values { task.cancel() }
        notifyIdle()
    }

    public func shutdown() {
        accepting = false
        cancelAll()
    }

    public func waitUntilIdle() async {
        if active.isEmpty && pending.isEmpty { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func pump() {
        while active.count < limit && !pending.isEmpty {
            let request = pending.removeFirst()
            states[request.id] = .running
            let registry = registry, timeout = timeout
            active[request.id] = Task {
                let state: JobState
                do {
                    let url = try await Self.execute(request, registry: registry, timeout: timeout)
                    state = .succeeded(url)
                } catch is CancellationError {
                    state = .cancelled
                } catch {
                    state = .failed(error.localizedDescription)
                }
                self.finish(request.id, state: state)
            }
        }
        notifyIdle()
    }

    private func finish(_ id: UUID, state: JobState) {
        active[id] = nil
        states[id] = state
        pump()
    }

    private func notifyIdle() {
        guard active.isEmpty && pending.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private nonisolated static func execute(_ request: ConversionRequest, registry: EngineRegistry, timeout: Duration) async throws -> URL {
        try Task.checkCancellation()
        guard let engine = registry.engine(source: request.sourceFormat, choice: request.choice) else {
            let reasons = registry.unavailableReasons(source: request.sourceFormat, target: request.targetFormat)
            if !reasons.isEmpty { throw WorkerError.engineUnavailable(reasons.joined(separator: "\n")) }
            throw ConversionError.unsupportedRoute(request.sourceFormat, request.targetFormat)
        }
        let fm = FileManager.default
        for input in request.inputs {
            guard (try? input.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  fm.isReadableFile(atPath: input.path) else { throw WorkerError.invalidInput }
        }
        // Staging beside the source guarantees an atomic, same-volume publication.
        let directory = request.source.deletingLastPathComponent()
        let workspace = directory.appendingPathComponent(".openlorikeet-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let folder = engine.producesFolder(for: request)
        let staging = workspace.appendingPathComponent(folder ? "output" : "output.\(request.targetFormat.fileExtension)", isDirectory: folder)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await engine.convert(request, to: staging) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WorkerError.timedOut
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
        try Task.checkCancellation()
        var metadata = stat()
        guard lstat(staging.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == (folder ? S_IFDIR : S_IFREG), metadata.st_size > 0 else { throw WorkerError.invalidOutput }
        try await engine.validate(output: staging, format: request.targetFormat)
        try Task.checkCancellation()
        let sourceName = request.source.deletingPathExtension().lastPathComponent
        let actionSuffix = request.choice.outputSuffix
        let base = sourceName + (folder && actionSuffix.isEmpty ? " (\(request.targetFormat.fileExtension.uppercased()))" : actionSuffix)
        for index in 1...10_000 {
            try Task.checkCancellation()
            let suffix = index == 1 ? "" : " (\(index))"
            let extensionSuffix = folder ? "" : ".\(request.targetFormat.fileExtension)"
            let destination = directory.appendingPathComponent(base + suffix + extensionSuffix, isDirectory: folder)
            if renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return destination }
            let code = errno
            if code != EEXIST { throw WorkerError.publishFailed(code) }
        }
        throw WorkerError.publishFailed(EEXIST)
    }
}
