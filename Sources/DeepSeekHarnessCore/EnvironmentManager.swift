import Foundation
import Combine

public struct ToolInfo: Sendable {
    public let name: String
    public let path: String
    public let version: String?

    public init(name: String, path: String, version: String?) {
        self.name = name
        self.path = path
        self.version = version
    }
}

public struct Toolchain: Sendable {
    public let dsh: ToolInfo?
    public let node: ToolInfo?
    public let npm: ToolInfo?
    public let pnpm: ToolInfo?
    public let git: ToolInfo?
    public let brew: ToolInfo?
    public let knownBinDirectories: [String]

    public init(
        dsh: ToolInfo? = nil,
        node: ToolInfo? = nil,
        npm: ToolInfo? = nil,
        pnpm: ToolInfo? = nil,
        git: ToolInfo? = nil,
        brew: ToolInfo? = nil,
        knownBinDirectories: [String] = []
    ) {
        self.dsh = dsh
        self.node = node
        self.npm = npm
        self.pnpm = pnpm
        self.git = git
        self.brew = brew
        self.knownBinDirectories = knownBinDirectories
    }

    public static let empty = Toolchain()

    public var orderedTools: [ToolInfo] {
        [dsh, node, npm, pnpm, git, brew].compactMap { $0 }
    }
}

public enum EnvironmentState: Equatable {
    case idle
    case checking
    case ready
    case missingDsh(canInstall: Bool, detail: String)
    case missingNode(canInstall: Bool, detail: String)
    case missingNpm(String)
    case installing(String)
    case failed(String)

    public var label: String {
        switch self {
        case .idle: return "等待检测"
        case .checking: return "正在检测环境…"
        case .ready: return "环境就绪"
        case .missingDsh: return "缺少 dsh"
        case .missingNode: return "缺少 Node.js"
        case .missingNpm: return "缺少 npm"
        case .installing(let step): return step
        case .failed(let message): return message
        }
    }
}

/// 环境自检与一键配置：
/// 1. 按 PATH → Homebrew → `~/.local/bin` → nvm 的顺序探测工具链；
/// 2. 没有 dsh 时用 npm 用户级前缀安装（不需要 sudo）；
/// 3. 没有 Node 时优先走 Homebrew，否则引导下载官方 pkg。
@MainActor
public final class EnvironmentManager: ObservableObject {
    @Published public private(set) var state: EnvironmentState = .idle
    @Published public private(set) var tools: Toolchain = .empty
    @Published public private(set) var spawnEnvironment: [String: String] = [:]
    @Published public private(set) var isWorking = false

    public let logs = LogStore(limit: 700)
    private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
        self.spawnEnvironment = Self.baseEnvironment(extraBinDirectories: [])
    }

    // MARK: - 便捷访问

    public var dshExecutable: URL? {
        if let path = tools.dsh?.path { return URL(fileURLWithPath: path) }
        return nil
    }

    public var npmExecutable: URL? {
        if let path = tools.npm?.path { return URL(fileURLWithPath: path) }
        return nil
    }

    public var pnpmExecutable: URL? {
        if let path = tools.pnpm?.path { return URL(fileURLWithPath: path) }
        return nil
    }

    // MARK: - 检测

    public func detect() async {
        guard !isWorking else { return }
        isWorking = true
        state = .checking
        logs.append(.info, "开始检测 DeepSeek Harness 运行环境")

        let detected = await Self.probe(customDshPath: settings.customDshPath)
        tools = detected
        spawnEnvironment = Self.baseEnvironment(extraBinDirectories: detected.knownBinDirectories)
        applySettingsOverrides()

        let toolSummary = detected.orderedTools
            .map { "\($0.name) \($0.version ?? "?")" }
            .joined(separator: ", ")
        logs.append(.info, toolSummary.isEmpty ? "未检测到任何工具链" : "检测到工具链：\(toolSummary)")

        if detected.dsh != nil {
            state = .ready
            logs.append(.success, "dsh 可用：\(detected.dsh?.version ?? "?")")
        } else if detected.node != nil, detected.npm != nil {
            state = .missingDsh(canInstall: true, detail: "检测到 Node.js 与 npm，可自动安装 @deepseek-ai/dsh")
            logs.append(.warning, "未找到 dsh；将通过 npm 用户级前缀安装 @deepseek-ai/dsh")
        } else if let node = detected.node {
            let version = node.version ?? "?"
            state = .missingNpm("已检测到 Node.js v\(version)（\(node.path)），但 npm 不可用。请确认 Node.js 安装完整后重新检测。")
            logs.append(.warning, "检测到 Node.js，但 npm 不可用：\(node.path)")
        } else if detected.brew != nil {
            state = .missingNode(canInstall: true, detail: "检测到 Homebrew，可自动安装 Node.js（需要几分钟）")
            logs.append(.warning, "未找到 Node.js；将通过 Homebrew 安装")
        } else {
            state = .missingNode(canInstall: false, detail: "未找到 Node.js，也未找到 Homebrew。请从 https://nodejs.org 安装 Node.js 22.19+ 或 24+")
            logs.append(.warning, "未找到 Node.js / Homebrew，需要手动安装 Node.js")
        }
        isWorking = false
    }

    public func recheck() async {
        isWorking = false
        await detect()
    }

    /// 设置项（DSH_HOME 等）变化后刷新子进程环境。
    public func refreshOverrides() {
        applySettingsOverrides()
    }

    // MARK: - 自动安装

    /// 安装/修复 dsh。优先使用当前 npm 全局前缀；不可写则退回 `~/.local`。
    @discardableResult
    public func installDsh() async -> Bool {
        await installOrUpdateDsh(verb: "安装", packageSpec: "@deepseek-ai/dsh")
    }

    /// 将 dsh 升级到 npm 上的最新版本（复用与安装相同的用户级前缀策略）。
    @discardableResult
    public func updateDsh() async -> Bool {
        await installOrUpdateDsh(verb: "升级", packageSpec: "@deepseek-ai/dsh@latest")
    }

    private func installOrUpdateDsh(verb: String, packageSpec: String) async -> Bool {
        guard tools.npm != nil else {
            state = .failed("缺少 npm，无法\(verb) dsh")
            return false
        }
        isWorking = true
        state = .installing("正在\(verb) @deepseek-ai/dsh…")
        logs.append(.command, "准备\(verb) @deepseek-ai/dsh")

        let prefix = npmWritableGlobalPrefix(fallback: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true).path)
        createDirectoryIfNeeded(prefix)
        createDirectoryIfNeeded((prefix as NSString).appendingPathComponent("bin"))

        var env = spawnEnvironment
        env["npm_config_prefix"] = prefix
        env["npm_config_loglevel"] = "warn"

        logs.append(.command, "npm install --global --prefix \(prefix) \(packageSpec)")
        let result = await ProcessRunner.streamAndWait(
            executableURL: npmExecutable!,
            arguments: ["install", "--global", "--prefix", prefix, packageSpec],
            environment: env
        ) { [weak self] line, isStderr in
            self?.logs.append(isStderr ? .stderr : .stdout, line)
        }

        if result.succeeded {
            // 确保新 prefix/bin 进入后续子进程 PATH
            spawnEnvironment = Self.baseEnvironment(
                extraBinDirectories: tools.knownBinDirectories + [(prefix as NSString).appendingPathComponent("bin")]
            )
            applySettingsOverrides()
            logs.append(.success, "@deepseek-ai/dsh \(verb)完成")
            isWorking = false
            await detect()
            return tools.dsh != nil
        } else {
            state = .failed(result.stderr.isEmpty
                ? "npm \(verb)失败（退出码 \(result.exitCode)）"
                : result.stderr)
            logs.append(.error, state.label)
            isWorking = false
            return false
        }
    }

    /// 通过 Homebrew 安装 Node.js。
    @discardableResult
    public func installNode() async -> Bool {
        guard let brew = tools.brew else {
            state = .failed("未找到 Homebrew")
            return false
        }
        isWorking = true
        state = .installing("正在通过 Homebrew 安装 Node.js（可能需要几分钟）…")
        logs.append(.command, "brew install node")
        let result = await ProcessRunner.streamAndWait(
            executableURL: URL(fileURLWithPath: brew.path),
            arguments: ["install", "node"],
            environment: spawnEnvironment
        ) { [weak self] line, isStderr in
            self?.logs.append(isStderr ? .stderr : .stdout, line)
        }
        if result.succeeded {
            logs.append(.success, "Node.js 安装完成")
            isWorking = false
            await detect()
            return tools.dsh != nil || tools.node != nil
        } else {
            state = .failed("brew install node 失败：\(result.stderr)")
            logs.append(.error, state.label)
            isWorking = false
            return false
        }
    }

    /// 确保 pnpm 可用（dsh 的 plugin 子命令实际转发给 pnpm）。
    @discardableResult
    public func ensurePnpm() async -> Bool {
        if tools.pnpm != nil { return true }

        guard tools.npm != nil else {
            logs.append(.error, "缺少 npm，无法安装 pnpm")
            return false
        }
        logs.append(.info, "未检测到 pnpm，正在安装…")

        // 优先 Corepack（Node 自带、无需额外全局包）。
        // Corepack 在部分机器上不会创建全局 pnpm 符号链接，因此我们在应用目录
        // 生成一个 exec corepack 的 shim，并放到子进程 PATH 的最前面。
        if let corepack = Self.firstExistingExecutable(named: "corepack", extraDirectories: tools.knownBinDirectories) {
            let result = await ProcessRunner.streamAndWait(
                executableURL: URL(fileURLWithPath: corepack),
                arguments: ["prepare", "pnpm@latest", "--activate"],
                environment: spawnEnvironment
            ) { [weak self] line, isStderr in
                self?.logs.append(isStderr ? .stderr : .stdout, line)
            }
            if result.succeeded, let shimDirectory = Self.applicationBinDirectory() {
                let shim = shimDirectory.appendingPathComponent("pnpm")
                let script = "#!/bin/sh\nexec '\(corepack)' pnpm \"$@\"\n"
                do {
                    try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
                    try script.write(to: shim, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

                    let extra = tools.knownBinDirectories + [shimDirectory.path]
                    if let updated = await Self.probeOneTool("pnpm", extraDirectories: extra) {
                        tools = Toolchain(
                            dsh: tools.dsh, node: tools.node, npm: tools.npm, pnpm: updated,
                            git: tools.git, brew: tools.brew,
                            knownBinDirectories: extra
                        )
                        spawnEnvironment = Self.baseEnvironment(extraBinDirectories: extra)
                        applySettingsOverrides()
                        logs.append(.success, "pnpm 已通过 Corepack 激活（shim: \(shim.path)）")
                        return true
                    }
                } catch {
                    logs.append(.warning, "创建 pnpm shim 失败：\(error.localizedDescription)")
                }
            }
        }

        let prefix = npmWritableGlobalPrefix(fallback: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true).path)
        createDirectoryIfNeeded(prefix)
        createDirectoryIfNeeded((prefix as NSString).appendingPathComponent("bin"))
        var env = spawnEnvironment
        env["npm_config_prefix"] = prefix

        logs.append(.command, "npm install --global --prefix \(prefix) pnpm")
        let result = await ProcessRunner.streamAndWait(
            executableURL: npmExecutable!,
            arguments: ["install", "--global", "--prefix", prefix, "pnpm"],
            environment: env
        ) { [weak self] line, isStderr in
            self?.logs.append(isStderr ? .stderr : .stdout, line)
        }
        if result.succeeded {
            let binDir = (prefix as NSString).appendingPathComponent("bin")
            spawnEnvironment = Self.baseEnvironment(extraBinDirectories: tools.knownBinDirectories + [binDir])
            applySettingsOverrides()
            if let updated = await Self.probeOneTool("pnpm", extraDirectories: tools.knownBinDirectories + [binDir]) {
                tools = Toolchain(
                    dsh: tools.dsh, node: tools.node, npm: tools.npm, pnpm: updated,
                    git: tools.git, brew: tools.brew,
                    knownBinDirectories: tools.knownBinDirectories + [binDir]
                )
                logs.append(.success, "pnpm 安装完成")
                return true
            }
        }
        logs.append(.error, "pnpm 安装失败：\(result.stderr)")
        return false
    }

    // MARK: - 私有实现

    private func applySettingsOverrides() {
        var env = spawnEnvironment
        let dshHome = settings.dshHome.trimmingCharacters(in: .whitespaces)
        if !dshHome.isEmpty {
            env["DSH_HOME"] = (dshHome as NSString).expandingTildeInPath
        } else {
            env.removeValue(forKey: "DSH_HOME")
        }
        spawnEnvironment = env
    }

    private nonisolated static func applicationBinDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("DeepSeekHarnessShell", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private func createDirectoryIfNeeded(_ path: String) {
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
    }

    private func npmWritableGlobalPrefix(fallback: String) -> String {
        guard let npmInfo = tools.npm else { return fallback }
        do {
            let result = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: npmInfo.path),
                arguments: ["config", "get", "prefix"],
                environment: spawnEnvironment,
                timeout: 10
            )
            let prefix = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty, isWritableDirectory(prefix) {
                return (prefix as NSString).expandingTildeInPath
            }
        } catch {
            logs.append(.warning, "读取 npm 全局前缀失败：\(error.localizedDescription)")
        }
        return fallback
    }

    private func isWritableDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: path)
    }

    // MARK: - 探测实现（后台线程执行，避免卡 UI）

    private static func probe(customDshPath: String) async -> Toolchain {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: probeSync(customDshPath: customDshPath))
            }
        }
    }

    private static func probeOneTool(_ name: String, extraDirectories: [String]) async -> ToolInfo? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let directories = uniqueDirectories(additionalCandidateDirectories() + extraDirectories)
                let probeEnvironment = baseEnvironment(extraBinDirectories: directories)
                let candidates = candidatePaths(for: name, extraDirectories: directories)
                for candidate in candidates.prefix(8) {
                    if let info = versionOfTool(name: name, executablePath: candidate, environment: probeEnvironment) {
                        continuation.resume(returning: info)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private nonisolated static func probeSync(customDshPath: String) -> Toolchain {
        // node 排在 npm/dsh 前面：npm 与 dsh 的 shebang 是 `#!/usr/bin/env node`，
        // 在 Finder 启动 GUI 的最小 PATH 下必须先让 node 目录进入探测环境 PATH。
        let names = ["node", "npm", "dsh", "pnpm", "git", "brew"]
        let extraDirectories = additionalCandidateDirectories()
        let probeEnvironment = baseEnvironment(extraBinDirectories: extraDirectories)
        var infoByName: [String: ToolInfo] = [:]

        // 用户指定的 dsh 路径拥有最高优先级。
        let custom = customDshPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            if let info = versionOfTool(
                name: "dsh",
                executablePath: (custom as NSString).expandingTildeInPath,
                environment: probeEnvironment
            ) {
                infoByName["dsh"] = info
            }
        }

        for name in names where infoByName[name] == nil {
            let candidates = candidatePaths(for: name, extraDirectories: extraDirectories)
            for candidate in candidates.prefix(10) {
                if let info = versionOfTool(
                    name: name,
                    executablePath: candidate,
                    environment: probeEnvironment
                ) {
                    infoByName[name] = info
                    break
                }
            }
        }

        var knownBins = Set<String>()
        for info in infoByName.values {
            knownBins.insert(URL(fileURLWithPath: info.path).deletingLastPathComponent().path)
        }
        for dir in extraDirectories where FileManager.default.fileExists(atPath: dir) {
            knownBins.insert(dir)
        }

        return Toolchain(
            dsh: infoByName["dsh"],
            node: infoByName["node"],
            npm: infoByName["npm"],
            pnpm: infoByName["pnpm"],
            git: infoByName["git"],
            brew: infoByName["brew"],
            knownBinDirectories: knownBins.sorted()
        )
    }

    private nonisolated static func versionOfTool(
        name: String,
        executablePath: String,
        environment: [String: String]? = nil
    ) -> ToolInfo? {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { return nil }
        do {
            let result = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: executablePath),
                arguments: ["--version"],
                environment: environment,
                timeout: 8
            )
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return ToolInfo(name: name, path: executablePath, version: version.isEmpty ? "?" : version)
        } catch {
            return nil
        }
    }

    /// 覆盖常见 Node 安装方式：Homebrew（含 node@18/20/22/24 多版本）、nvm、
    /// volta、asdf、fnm、mise、MacPorts、conda，以及用户级 npm 前缀。
    private nonisolated static func additionalCandidateDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs: [String] = []
        func append(_ path: String) { dirs.append(path) }

        let base = [
            (home.path as NSString).appendingPathComponent(".local/bin"),
            (home.path as NSString).appendingPathComponent(".npm-global/bin"),
            (home.path as NSString).appendingPathComponent("Library/pnpm"),
            "/opt/homebrew/bin",
            "/opt/homebrew/opt/node/bin",
            "/opt/homebrew/opt/corepack/bin",
            "/opt/homebrew/opt/pnpm/bin",
            "/usr/local/bin",
            "/usr/local/opt/node/bin",
            "/usr/local/opt/corepack/bin",
            "/usr/local/opt/pnpm/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin"
        ]
        for path in base { append(path) }

        let userDirectories = [
            ".volta/bin",
            ".asdf/shims",
            ".mise/shims",
            ".local/share/mise/shims",
            "miniconda3/bin",
            "anaconda3/bin",
            "miniforge3/bin",
            "micromamba/bin"
        ]
        for relative in userDirectories {
            append((home.path as NSString).appendingPathComponent(relative))
        }

        // Homebrew 版本化公式：node@18 / node@20 / node@22 / node@24 等。
        for optRoot in ["/opt/homebrew/opt", "/usr/local/opt"] {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: optRoot) else { continue }
            for child in children.sorted() where child.hasPrefix("node") || child == "corepack" || child == "pnpm" {
                let bin = URL(fileURLWithPath: optRoot)
                    .appendingPathComponent(child)
                    .appendingPathComponent("bin")
                append(bin.path)
            }
        }

        // nvm。
        let nvmRoot = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let children = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot.path) {
            for versionDir in children.sorted().reversed() {
                append(nvmRoot.appendingPathComponent(versionDir).appendingPathComponent("bin").path)
            }
        }

        // fnm（两个常见数据目录）。
        let fnmRoots = [
            home.appendingPathComponent("Library/Application Support/fnm/node-versions", isDirectory: true),
            home.appendingPathComponent(".local/share/fnm/node-versions", isDirectory: true)
        ]
        for fnmRoot in fnmRoots {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: fnmRoot.path) else { continue }
            for versionDir in children.sorted().reversed() {
                append(fnmRoot.appendingPathComponent(versionDir).appendingPathComponent("installation/bin").path)
            }
        }

        return uniqueDirectories(dirs)
    }

    private nonisolated static func uniqueDirectories(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.filter { path in
            let expanded = (path as NSString).standardizingPath
            guard !seen.contains(expanded) else { return false }
            seen.insert(expanded)
            return true
        }.map { ($0 as NSString).standardizingPath }
    }

    private nonisolated static func candidatePaths(for name: String, extraDirectories: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func append(_ dir: String) {
            let path = (dir as NSString).appendingPathComponent(name)
            if !seen.contains(path) {
                seen.insert(path)
                result.append(path)
            }
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in pathValue.split(separator: ":").map(String.init) {
            append(dir)
        }
        for dir in extraDirectories {
            append(dir)
        }
        return result
    }

    private nonisolated static func firstExistingExecutable(named name: String, extraDirectories: [String]) -> String? {
        candidatePaths(for: name, extraDirectories: extraDirectories)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func baseEnvironment(extraBinDirectories: [String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var pathEntries = (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        for dir in extraBinDirectories where !pathEntries.contains(dir) {
            pathEntries.insert(dir, at: 0)
        }
        env["PATH"] = pathEntries.joined(separator: ":")
        return env
    }
}
