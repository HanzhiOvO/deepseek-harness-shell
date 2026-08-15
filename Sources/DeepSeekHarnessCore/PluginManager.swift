import Foundation
import Combine

public struct InstalledPlugin: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let spec: String
    public let version: String?
    public let isBundle: Bool

    public init(name: String, spec: String, version: String?, isBundle: Bool) {
        self.name = name
        self.spec = spec
        self.version = version
        self.isBundle = isBundle
    }

    public var sourceKind: SourceKind {
        let lower = spec.lowercased()
        if lower.hasPrefix("file:") || lower.hasPrefix("link:") { return .folder }
        if lower.contains("github:") || lower.contains("git+") || lower.contains("git@") { return .github }
        if lower.hasPrefix("http") && lower.contains(".tgz") { return .zip }
        return .npm
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
            installed = []
            return
        }

        let dependencies = manifest["dependencies"] as? [String: String] ?? [:]
        let dshSection = manifest["dsh"] as? [String: Any]
        let profileSection = dshSection?["profile"] as? [String: Any]
        let bundles = profileSection?["bundles"] as? [String] ?? []

        var result: [InstalledPlugin] = []
        for (name, spec) in dependencies.sorted(by: { $0.key < $1.key }) {
            let version = self.installedVersion(of: name)
            result.append(InstalledPlugin(
                name: name,
                spec: spec,
                version: version,
                isBundle: bundles.contains(name)
            ))
        }
        installed = result
    }

    private func installedVersion(of packageName: String) -> String? {
        let manifest = profileDirectory
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(packageName, isDirectory: true)
            .appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["version"] as? String
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
        try await runPlugin(arguments: ["remove", plugin.name], logPrefix: "移除 \(plugin.name)")
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
