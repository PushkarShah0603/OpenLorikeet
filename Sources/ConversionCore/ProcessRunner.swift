import Foundation
import Darwin

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessFailure: Error, LocalizedError {
    case failed(Int32, String)
    case outputTooLarge
    public var errorDescription: String? {
        switch self {
        case .failed(let code, let message): "Converter exited with status \(code): \(message)"
        case .outputTooLarge: "The converter exceeded its output size limit."
        }
    }
}

/// Argument-array execution, bounded diagnostic reads, and no pipe-buffer deadlocks.
public enum ProcessRunner {
    public static func run(executable: URL, arguments: [String], directory: URL,
                           timeout: Duration = .seconds(120),
                           outputFile: URL? = nil, outputLimit: Int = 16 * 1024 * 1024) async throws -> ProcessOutput {
        try Task.checkCancellation()
        guard executable.isFileURL, directory.isFileURL,
              !([executable.path, directory.path] + arguments).contains(where: { $0.utf8.contains(0) }) else {
            throw WorkerError.invalidInput
        }
        let fm = FileManager.default
        let logs = directory.appendingPathComponent("process-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: logs) }
        let outURL = outputFile ?? logs.appendingPathComponent("stdout")
        let errURL = logs.appendingPathComponent("stderr")
        func outputIsTooLarge() -> Bool {
            let outSize = (try? fm.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
            let errSize = (try? fm.attributesOfItem(atPath: errURL.path)[.size] as? Int) ?? 0
            return outSize > outputLimit || errSize > 16 * 1024 * 1024
        }
        let pid = try spawn(executable: executable, arguments: arguments, directory: directory,
                            stdout: outURL, stderr: errURL)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let status: Int32
        do {
            while true {
                try Task.checkCancellation()
                if let exit = try reap(pid) {
                    status = exit
                    break
                }
                if outputIsTooLarge() { throw ProcessFailure.outputTooLarge }
                if ContinuousClock.now >= deadline { throw WorkerError.timedOut }
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch let error as POSIXError {
            // A waitpid failure gives us no reliable ownership of the PID.
            throw error
        } catch {
            // The detached cleanup task can sleep even if the caller is cancelled.
            await Task.detached { await stopAndReap(pid) }.value
            throw error
        }
        try Task.checkCancellation()
        if outputIsTooLarge() { throw ProcessFailure.outputTooLarge }
        func read(_ url: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return String(decoding: try handle.read(upToCount: 16_384) ?? Data(), as: UTF8.self)
        }
        let result = try ProcessOutput(status: status, stdout: outputFile == nil ? read(outURL) : "", stderr: read(errURL))
        guard result.status == 0 else { throw ProcessFailure.failed(result.status, result.stderr) }
        return result
    }

    private static func spawn(executable: URL, arguments: [String], directory: URL,
                              stdout: URL, stderr: URL) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        try requireSuccess(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            try requireSuccess(posix_spawn_file_actions_addchdir(&actions, directory.path))
        } else {
            try requireSuccess(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        }
        #else
        try requireSuccess(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        #endif
        try requireSuccess(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        for (fd, url) in [(STDOUT_FILENO, stdout), (STDERR_FILENO, stderr)] {
            try requireSuccess(posix_spawn_file_actions_addopen(&actions, fd, url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600))
        }
        var attributes: posix_spawnattr_t?
        try requireSuccess(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try requireSuccess(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)))
        try requireSuccess(posix_spawnattr_setpgroup(&attributes, 0))
        var argv = ([executable.path] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        guard argv.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        argv.append(nil)
        var pid: pid_t = 0
        try requireSuccess(posix_spawn(&pid, executable.path, &actions, &attributes, &argv, environ))
        return pid
    }

    private static func requireSuccess(_ code: Int32) throws {
        if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }

    private static func reap(_ pid: pid_t) throws -> Int32? {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == 0 || (result == -1 && errno == EINTR) { return nil }
        if result == -1 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private static func stopAndReap(_ pid: pid_t) async {
        // Keep the leader unreaped during the grace period so its group ID stays reserved.
        kill(-pid, SIGTERM)
        try? await Task.sleep(for: .milliseconds(200))
        kill(-pid, SIGKILL)
        do {
            while try reap(pid) == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            // If the child is already gone, there is nothing left to reap.
        }
    }

}
