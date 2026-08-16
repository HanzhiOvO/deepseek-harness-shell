import Foundation
import Combine

public struct InstalledPlugin: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let spec: String
    public let version: String?
    public let isBundle: Bool
    public let isInbox: Bool

    public init(
        name: String,
        spec: String,
        version: String?,
        isBundle: Bool,
        isInbox: Bool = false
    ) {
        self.name = name
        self.spec = spec
        self.version = version
        self.isBundle = isBundle
        self.isInbox = isInbox
    }

    public var sourceKind: SourceKind {
        let lower = spec.lowercased()
        if lower.hasPrefix("file:") || lower.hasPrefix("link:") { return .folder }
        if lower.contains("github:") || lower.contains("git+") || lower.contains("git@") { return .github }
        if lower.hasPrefix("http") && lower.contains(".tgz") { return .zip }
        return .npm
    }

    /// 本地源码路径（本地文件夹 / ZIP 持久化目录）。
    public var localSourceURL: URL? {
        let lower = spec.lowercased()
        guard lower.hasPrefix("file:") || lower.hasPrefix("link:") else { return nil }
        guard let parsed = URL(string: spec) else { return nil }
        return URL(fileURLWithPath: parsed.path, isDirectory: true)
    }

    /// 插件在网上的主页（GitHub 仓库 / npm 包页），供「打开主页」使用。
    public var externalURL: URL? {
        switch sourceKind {
        case .github:
            let cleaned = spec
                .replacingOccurrences(of: "git+https://github.com/", with: "https://github.com/")
                .replacingOccurrences(of: "git+ssh://git@github.com/", with: "https://github.com/")
                .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
                .replacingOccurrences(of: "github:", with: "https://github.com/")
            guard let parsed = URLComponents(string: cleaned) else { return nil }
            let pieces = parsed.path.split(separator: "/").map(String.init)
            guard pieces.count >= 2 else { return nil }
            var repo = pieces[1]
            if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
            var urlString = "https://github.com/\(pieces[0])/\(repo)"
            if let ref = parsed.fragment?.trimmingCharacters(in: .whitespaces), !ref.isEmpty {
                urlString += "/tree/\(ref)"
            }
            return URL(string: urlString)
        case .npm:
            return URL(string: "https://www.npmjs.com/package/\(name)")
        case .folder, .zip:
            return nil
        }
    }

    public enum SourceKind {
        case github, zip, folder, npm

        public var label: String {
            switch self {
            case .github: return "GitHub"
            case .zip: return "归档"
            case .folder: return "本地目录"
            case .npm: return "npm"
            }
        }
    }
}

public enum PluginManagerError: LocalizedError, Equatable {
    case dshMissing
    case pnpmMissing
    case invalidPackage(String)
    case commandFailed(code: Int32, detail: String)

    public var errorDescription: String? {
        switch self {
        case .dshMissing:
            return "缺少 dsh，请先在「环境与设置」中配置运行环境"
        case .pnpmMissing:
            return "无法安装 pnpm（dsh 插件管理依赖 pnpm），请查看运行日志"
        case .invalidPackage(let message):
            return message
        case .commandFailed(let code, let detail):
            let tail = detail.split(separator: "\n").suffix(5).joined(separator: "\n")
            return "安装命令失败（exit \(code)）\(tail.isEmpty ? "" : "：\n\(tail)")"
        }
    }
}

/// 插件中心：包装官方 `dsh plugin --profile <name> add/remove ...`。
/// - GitHub 地址 → `github:owner/repo#ref`
/// - ZIP 压缩包 → 解包到临时目录 → `file:/path`
/// - 本地文件夹 → 直接 `file:/path`（不复制，节省磁盘）
@MainActor
public final class PluginManager: ObservableObject {
    @Published public private(set) var installed: [InstalledPlugin] = []
    @Published public private(set) var profiles: [String] = ["web"]
    @Published public private(set) var isWorking = false
    @Published public var profileName: String {
        didSet {
            let trimmed = profileName.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { profileName = "web" }
            settings.profileName = profileName
            loadInstalled()
        }
    }

    public let logs = LogStore(limit: 700)
    private let environment: EnvironmentManager
    private let settings: AppSettings

    public init(environment: EnvironmentManager, settings: AppSettings) {
        self.environment = environment
        self.settings = settings
        self.profileName = settings.profileName.trimmingCharacters(in: .whitespaces)
        if self.profileName.isEmpty { self.profileName = "web" }
    }

    // MARK: - 路径

    public var dshHomeDirectory: URL {
        let configured = settings.dshHome.trimmingCharacters(in: .whitespaces)
        if !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        }
        let envHome = ProcessInfo.processInfo.environment["DSH_HOME"]?.trimmingCharacters(in: .whitespaces)
        if let envHome, !envHome.isEmpty {
            return URL(fileURLWithPath: (envHome as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
    }

    public var profileDirectory: URL {
        dshHomeDirectory.appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(profileName, isDirectory: true)
    }

    // MARK: - 清单

    public func refreshProfiles() {
        let profilesRoot = dshHomeDirectory.appendingPathComponent("profiles", isDirectory: true)
        var names: [String] = []
        if let children = try? FileManager.default.contentsOfDirectory(atPath: profilesRoot.path) {
            for child in children.sorted() {
                let manifest = profilesRoot.appendingPathComponent(child).appendingPathComponent("package.json")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    names.append(child)
                }
            }
        }
        if !names.contains("web") { names.insert("web", at: 0) }
        profiles = names
        if !names.contains(profileName) { profileName = names.first ?? "web" }
        loadInstalled()
    }

    public func loadInstalled() {
        let manifestURL = profileDirectory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // profile 尚未初始化：仍然显示 dsh 随附的默认 bundle。
            let defaults = ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"]
            installed = defaults.map { name in
                InstalledPlugin(
                    name: name,
                    spec: "dsh 随附 bundle",
                    version: self.installedVersion(of: name),
                    isBundle: true,
                    isInbox: true
                )
            }
            return
        }

        let dependencies = manifest["dependencies"] as? [String: String] ?? [:]
        let dshSection = manifest["dsh"] as? [String: Any]
        let profileSection = dshSection?["profile"] as? [String: Any]
        let bundles = profileSection?["bundles"] as? [String] ?? []

        var result: [InstalledPlugin] = []
        var namesInDependencies = Set<String>()

        // 1) 用户通过 dsh plugin add 安装的依赖。
        for (name, spec) in dependencies.sorted(by: { $0.key < $1.key }) {
            namesInDependencies.insert(name)
            result.append(InstalledPlugin(
                name: name,
                spec: spec,
                version: self.installedVersion(of: name),
                isBundle: bundles.contains(name)
            ))
        }

        // 2) dsh 随附的内置 bundle（例如 dsh-base / dsh-web-app）。
        // 它们不在 dependencies 里，但确实是 profile 已安装并激活的插件。
        for name in bundles where !namesInDependencies.contains(name) {
            result.append(InstalledPlugin(
                name: name,
                spec: "dsh 随附 bundle",
                version: self.installedVersion(of: name),
                isBundle: true,
                isInbox: true
            ))
        }

        installed = result.sorted {
            if $0.isInbox != $1.isInbox { return !$0.isInbox }
            return $0.name < $1.name
        }
    }

    private func installedVersion(of packageName: String) -> String? {
        let candidates = versionManifestCandidates(for: packageName)
        for manifest in candidates {
            guard let data = try? Data(contentsOf: manifest),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let version = object["version"] as? String { return version }
        }
        return nil
    }

    private func versionManifestCandidates(for packageName: String) -> [URL] {
        var candidates: [URL] = []
        let nodeModules = profileDirectory.appendingPathComponent("node_modules", isDirectory: true)

        // pnpm 顶层符号链接。
        candidates.append(nodeModules.appendingPathComponent(packageName).appendingPathComponent("package.json"))

        // pnpm 虚拟仓库：node_modules/.pnpm/<name>@<version>/node_modules/<name>/package.json
        let pnpmStore = nodeModules.appendingPathComponent(".pnpm", isDirectory: true)
        if let children = try? FileManager.default.contentsOfDirectory(atPath: pnpmStore.path) {
            let prefix = packageName + "@"
            for child in children.sorted().reversed() where child.hasPrefix(prefix) {
                let candidate = pnpmStore
                    .appendingPathComponent(child)
                    .appendingPathComponent("node_modules")
                    .appendingPathComponent(packageName)
                    .appendingPathComponent("package.json")
                candidates.append(candidate)
                if candidates.count >= 6 { break }
            }
        }

        // dsh 安装位置（内置 bundle 从安装锚点解析）。
        if let dsh = environment.dshExecutable {
            var dir = dsh.resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<8 {
                let candidate = dir
                    .appendingPathComponent("node_modules", isDirectory: true)
                    .appendingPathComponent(packageName, isDirectory: true)
                    .appendingPathComponent("package.json")
                candidates.append(candidate)
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return candidates
    }

    // MARK: - 安装

    public func installFromGitHub(_ input: String) async throws {
        let spec = try GitHubSpecParser.parse(input)
        logs.append(.info, "解析 GitHub 插件：\(spec.displayName)")
        try await install(pnpmArgument: spec.pnpmArgument, sourceLabel: spec.displayName)
    }

    public func installFromZip(_ archiveURL: URL) async throws {
        let extensionName = archiveURL.pathExtension.lowercased()
        guard extensionName == "zip" else {
            throw PluginManagerError.invalidPackage("仅支持 .zip 压缩包")
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekHarnessShell-PluginInstall", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: staging)
        }

        let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
        let extract = try ProcessRunner.run(
            executableURL: ditto,
            arguments: ["-x", "-k", archiveURL.path, staging.path],
            timeout: 120
        )
        guard extract.succeeded else {
            throw PluginManagerError.invalidPackage("解压失败：\(extract.stderr)")
        }

        let entries = ArchivePackageLocator.relativeEntries(in: staging)
        logs.append(.info, "ZIP 内文件：\(entries.joined(separator: ", "))")
        guard let root = ArchivePackageLocator.packageRootRelativePath(entries: entries) else {
            throw PluginManagerError.invalidPackage(
                "压缩包内没有找到 package.json。请确保 package.json 位于根目录，或位于唯一的顶层文件夹内。"
            )
        }
        let packageRoot = staging.appendingPathComponent(root, isDirectory: true)
        let manifestURL = packageRoot.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginManagerError.invalidPackage("package.json 无法读取")
        }

        // ZIP 内容必须持久保存：pnpm 的 file: 依赖在后续 install/remove 时
        // 仍会解析源路径，立即删除解压目录会导致 ENOENT。
        let sourcesRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DeepSeekHarnessShell", isDirectory: true)
            .appendingPathComponent("PluginSources", isDirectory: true)
        let sources = sourcesRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekHarnessShell-PluginSources", isDirectory: true)

        let packageName: String
        if let data = try? Data(contentsOf: manifestURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["name"] as? String,
           !name.isEmpty {
            packageName = name.replacingOccurrences(of: "/", with: "_")
        } else {
            packageName = "plugin-\(UUID().uuidString)"
        }

        let destination = sources.appendingPathComponent(packageName, isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: packageRoot, to: destination)
        logs.append(.info, "ZIP 源文件已保存到 \(destination.path)")
        try await install(pnpmArgument: "file:\(destination.path)", sourceLabel: archiveURL.lastPathComponent)
    }

    public func installFromFolder(_ folderURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("package.json").path) else {
            throw PluginManagerError.invalidPackage("所选文件夹中必须包含 package.json")
        }
        try await install(pnpmArgument: "file:\(folderURL.path)", sourceLabel: folderURL.lastPathComponent)
    }

    public func installFromNpm(_ package: String) async throws {
        let spec = package.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { throw PluginManagerError.invalidPackage("请输入 npm 包名") }
        try await install(pnpmArgument: spec, sourceLabel: spec)
    }

    public func remove(_ plugin: InstalledPlugin) async throws {
        guard !plugin.isInbox else {
            throw PluginManagerError.invalidPackage("内置 bundle 由 dsh 随附，不能从 profile 中移除")
        }
        try await runPlugin(arguments: ["remove", plugin.name], logPrefix: "移除 \(plugin.name)")
    }

    /// 更新已安装插件：npm 源直接升级到 latest；
    /// GitHub/本地目录源按 package.json 中的既有 spec 重新解析（不改变来源）。
    public func update(_ plugin: InstalledPlugin) async throws {
        guard !plugin.isInbox else {
            throw PluginManagerError.invalidPackage("内置 bundle 随 dsh 一起升级，不需要单独更新")
        }
        let arguments: [String]
        switch plugin.sourceKind {
        case .npm:
            arguments = ["update", "--latest", plugin.name]
        case .github, .folder, .zip:
            arguments = ["update", plugin.name]
        }
        try await runPlugin(arguments: arguments, logPrefix: "更新 \(plugin.name)")
    }

    // MARK: - 内部实现

    private func install(pnpmArgument: String, sourceLabel: String) async throws {
        try await runPlugin(
            arguments: ["add", pnpmArgument],
            logPrefix: "安装 \(sourceLabel)"
        )
    }

    private func runPlugin(arguments: [String], logPrefix: String) async throws {
        guard let dsh = environment.dshExecutable else {
            throw PluginManagerError.dshMissing
        }
        guard await environment.ensurePnpm() else {
            throw PluginManagerError.pnpmMissing
        }

        isWorking = true
        defer { isWorking = false }
        logs.append(.command, "dsh plugin --profile \(profileName) \(arguments.joined(separator: " "))")
        logs.append(.info, "\(logPrefix)（通过 pnpm 安装到 profile「\(profileName)」，可能需要下载依赖）")

        var processEnvironment = environment.spawnEnvironment
        let dshHome = settings.dshHome.trimmingCharacters(in: .whitespaces)
        if !dshHome.isEmpty {
            processEnvironment["DSH_HOME"] = (dshHome as NSString).expandingTildeInPath
        }

        let result = await ProcessRunner.streamAndWait(
            executableURL: dsh,
            arguments: ["plugin", "--profile", profileName] + arguments,
            environment: processEnvironment
        ) { [weak self] line, isStderr in
            self?.logs.append(isStderr ? .stderr : .stdout, line)
        }

        guard result.succeeded else {
            var detail = result.stderr
            if detail.contains("allowBuilds") || detail.contains("build") {
                detail += "\n提示：git 插件依赖构建脚本时，pnpm 需要 allowBuilds 白名单；请按上面 pnpm 打印的 key 编辑 \(profileDirectory.path)/pnpm-workspace.yaml 后重试。"
            }
            throw PluginManagerError.commandFailed(code: result.exitCode, detail: detail)
        }
        logs.append(.success, "\(logPrefix) 完成")
        loadInstalled()
    }
}
