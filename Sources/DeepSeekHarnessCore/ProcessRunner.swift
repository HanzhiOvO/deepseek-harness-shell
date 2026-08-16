import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

public enum ProcessRunnerError: LocalizedError {
    case launchFailed(executable: String, message: String)
    case timedOut(executable: String)
    case nonZeroExit(executable: String, code: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let message):
            return "无法启动 \(executable)：\(message)"
        case .timedOut(let executable):
            return "\(executable) 执行超时"
        case .nonZeroExit(let executable, let code, let stderr):
            let tail = stderr.split(separator: "\n").suffix(4).joined(separator: "\n")
            return "\(executable) 退出码 \(code)\(tail.isEmpty ? "" : "：\(tail)")"
        }
    }
}

/// 对 `Process` 的轻量封装：短命令走 `run`，长任务（安装、服务）走 `stream`。
/// 全部输出按行读取，使用系统 Pipe + DispatchQueue，不引入轮询定时器。
public enum ProcessRunner {
    /// 同步运行短命令（版本探测、配置读取等），带超时。
    public static func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval = 20
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(
                executable: executableURL.lastPathComponent,
                message: error.localizedDescription
            )
        }

        let reader = DispatchQueue(label: "dsh-shell.short-read", attributes: .concurrent)
        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()

        group.enter()
        reader.async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        reader.async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let started = Date()
        var timedOut = false
        while process.isRunning {
            if Date().timeIntervalSince(started) > timeout {
                timedOut = true
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        _ = group.wait(timeout: .now() + 3)

        let out = String(data: stdoutData, encoding: .utf8) ?? ""
        let err = String(data: stderrData, encoding: .utf8) ?? ""
        let code = process.terminationStatus
        if timedOut {
            throw ProcessRunnerError.timedOut(executable: executableURL.lastPathComponent)
        }
        if code != 0 {
            throw ProcessRunnerError.nonZeroExit(
                executable: executableURL.lastPathComponent,
                code: code,
                stderr: err
            )
        }
        return ProcessResult(exitCode: code, stdout: out, stderr: err)
    }

    /// 流式运行长任务。`onOutput(line, isStderr)` 与 `onExit` 均回调到主线程。
    @discardableResult
    public static func stream(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: @escaping (String, Bool) -> Void,
        onExit: @escaping (Int32, String?) -> Void
    ) throws -> ManagedProcess {
        let managed = ManagedProcess(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            onOutput: onOutput,
            onExit: onExit
        )
        try managed.start()
        return managed
    }

    /// `stream` 的 async 版本，等待进程自然退出并返回结果。
    public static func streamAndWait(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: @escaping (String, Bool) -> Void
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            var finished = false
            var stderrTail: [String] = []
            // 必须持有 ManagedProcess，否则短命令退出时对象提前释放，
            // terminationHandler 不会触发，continuation 会永久挂起。
            var managed: ManagedProcess?
            do {
                let process = try stream(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: environment,
                    currentDirectoryURL: currentDirectoryURL
                ) { line, isStderr in
                    onOutput(line, isStderr)
                    if isStderr {
                        stderrTail.append(line)
                        if stderrTail.count > 12 { stderrTail.removeFirst(stderrTail.count - 12) }
                    }
                } onExit: { code, spawnError in
                    guard !finished else { return }
                    finished = true
                    managed = nil
                    let message = spawnError ?? stderrTail.joined(separator: "\n")
                    continuation.resume(returning: ProcessResult(exitCode: code, stdout: "", stderr: message, timedOut: false))
                }
                managed = process
                _ = managed // 持有到退出回调，防止短命令提前释放进程对象
            } catch {
                guard !finished else { return }
                finished = true
                continuation.resume(returning: ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false))
            }
        }
    }
}

/// 一个受管子进程：负责 stdout/stderr 按行流式回调、优雅停止（SIGTERM → SIGKILL）。
public final class ManagedProcess {
    private let process = Process()
    private let queue = DispatchQueue(label: "dsh-shell.managed-process")
    private let onOutput: (String, Bool) -> Void
    private let onExit: (Int32, String?) -> Void

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var stdoutEOF = false
    private var stderrEOF = false
    private var didFinish = false
    private var spawnError: String?
    private var stopRequested = false

    public private(set) var processIdentifier: Int32 = 0
    public var isRunning: Bool { process.isRunning }

    public init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: @escaping (String, Bool) -> Void,
        onExit: @escaping (Int32, String?) -> Void
    ) {
        self.onOutput = onOutput
        self.onExit = onExit
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }
        process.standardInput = FileHandle.nullDevice
    }

    public func start() throws {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                self?.markEOF(stderr: false)
            } else {
                self?.ingest(data, stderr: false)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                self?.markEOF(stderr: true)
            } else {
                self?.ingest(data, stderr: true)
            }
        }

        process.terminationHandler = { [weak self] process in
            self?.finish(exitCode: process.terminationStatus)
        }

        do {
            try process.run()
            processIdentifier = process.processIdentifier
        } catch {
            spawnError = error.localizedDescription
            onExit(-1, spawnError)
            throw error
        }
    }

    /// 先 SIGTERM，宽限期后仍存活则 SIGKILL。
    public func stop(grace: TimeInterval = 2.0) {
        stopRequested = true
        let pid = process.processIdentifier
        guard process.isRunning else { return }
        process.terminate()
        queue.asyncAfter(deadline: .now() + grace) { [process] in
            guard process.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    private func ingest(_ data: Data, stderr: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            var buffer = stderr ? self.stderrBuffer : self.stdoutBuffer
            buffer.append(data)

            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                let line: String
                if let decoded = String(data: lineData, encoding: .utf8) {
                    line = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                } else {
                    line = String(decoding: lineData, as: UTF8.self)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                }
                lines.append(line)
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            if stderr { self.stderrBuffer = buffer } else { self.stdoutBuffer = buffer }

            DispatchQueue.main.async {
                for line in lines {
                    self.onOutput(line, stderr)
                }
            }
        }
    }

    private func markEOF(stderr: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if stderr { self.stderrEOF = true } else { self.stdoutEOF = true }
        }
    }

    private func finish(exitCode: Int32) {
        queue.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.didFinish = true
            let remaining = (self.stdoutBuffer.isEmpty ? "" : String(data: self.stdoutBuffer, encoding: .utf8) ?? "") + "\n"
                + (self.stderrBuffer.isEmpty ? "" : String(data: self.stderrBuffer, encoding: .utf8) ?? "")
            let error = self.spawnError
            let requested = self.stopRequested
            DispatchQueue.main.async {
                let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    self.onOutput(tail, true)
                }
                self.onExit(exitCode, error)
                _ = requested
            }
        }
    }
}
