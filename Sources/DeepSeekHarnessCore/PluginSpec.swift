import Foundation

public struct GitHubPluginSpec: Equatable, Sendable {
    public let owner: String
    public let repository: String
    public let ref: String?
    /// 传给 `dsh plugin --profile <name> add` 的 pnpm 参数。
    public let pnpmArgument: String

    public init(owner: String, repository: String, ref: String?, pnpmArgument: String) {
        self.owner = owner
        self.repository = repository
        self.ref = ref
        self.pnpmArgument = pnpmArgument
    }

    public var displayName: String {
        ref.map { "\(owner)/\(repository)@\($0)" } ?? "\(owner)/\(repository)"
    }
}

public enum PluginSpecError: LocalizedError, Equatable {
    case empty
    case unsupported(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入 GitHub 仓库地址"
        case .unsupported(let input):
            return "不支持的地址：\(input)\n支持 owner/repo、https://github.com/owner/repo 或 git@github.com:owner/repo.git 形式"
        case .malformed(let input):
            return "无法解析 GitHub 仓库：\(input)"
        }
    }
}

/// 把用户输入（owner/repo、https、git+https、git@ 等）规范化为 pnpm 可安装的 spec。
public enum GitHubSpecParser {
    public static func parse(_ rawInput: String) throws -> GitHubPluginSpec {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw PluginSpecError.empty }

        // 1. 带协议的 URL / scp 风格地址
        if input.contains("github.com") {
            let normalized = input
                .replacingOccurrences(of: "git+ssh://git@github.com/", with: "https://github.com/")
                .replacingOccurrences(of: "ssh://git@github.com/", with: "https://github.com/")
                .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
                .replacingOccurrences(of: "git+https://github.com/", with: "https://github.com/")
                .replacingOccurrences(of: "git+ssh://github.com/", with: "https://github.com/")

            guard let components = URLComponents(string: normalized),
                  let path = parseGitHubPath(normalized) else {
                throw PluginSpecError.malformed(input)
            }
            let pieces = path.split(separator: "/").map(String.init)
            guard pieces.count >= 2 else { throw PluginSpecError.malformed(input) }

            var ref = components.fragment?.trimmingCharacters(in: .whitespaces)
            let repo = stripDotGit(pieces[1])
            if pieces.count >= 4, pieces[2].lowercased() == "tree" {
                ref = pieces.dropFirst(3).joined(separator: "/")
            } else if pieces.count > 2 {
                // 其他非标准路径按无法解析处理
                throw PluginSpecError.unsupported(input)
            }
            guard isValidName(pieces[0]), isValidName(repo) else {
                throw PluginSpecError.malformed(input)
            }
            let pnpm = "github:\(pieces[0])/\(repo)" + (ref.map { "#\($0)" } ?? "")
            return GitHubPluginSpec(owner: pieces[0], repository: repo, ref: ref, pnpmArgument: pnpm)
        }

        // 2. owner/repo、owner/repo#ref
        if input.contains("/") {
            let withoutFragment = input.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let pathPart = String(withoutFragment[0]).replacingOccurrences(of: "github:", with: "")
            let pieces = pathPart.split(separator: "/").map(String.init)
            guard pieces.count == 2 else { throw PluginSpecError.unsupported(input) }
            let owner = pieces[0]
            let repo = stripDotGit(pieces[1])
            guard isValidName(owner), isValidName(repo) else { throw PluginSpecError.malformed(input) }
            let ref: String?
            if withoutFragment.count == 2 {
                let value = withoutFragment[1].trimmingCharacters(in: .whitespaces)
                ref = value.isEmpty ? nil : value
            } else {
                ref = nil
            }
            let pnpm = "github:\(owner)/\(repo)" + (ref.map { "#\($0)" } ?? "")
            return GitHubPluginSpec(owner: owner, repository: repo, ref: ref, pnpmArgument: pnpm)
        }

        throw PluginSpecError.unsupported(input)
    }

    private static func parseGitHubPath(_ urlString: String) -> String? {
        let withoutProtocol = urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "git+", with: "")
            .replacingOccurrences(of: "ssh://", with: "")
            .replacingOccurrences(of: "git@", with: "")
        guard let slash = withoutProtocol.firstIndex(of: "/") else { return nil }
        var path = String(withoutProtocol[slash...])
        if let hash = path.firstIndex(of: "#") {
            path = String(path[..<hash])
        }
        if let query = path.firstIndex(of: "?") {
            path = String(path[..<query])
        }
        return path
    }

    private static func stripDotGit(_ name: String) -> String {
        name.lowercased().hasSuffix(".git") ? String(name.dropLast(4)) : name
    }

    private static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }
}

/// ZIP 解包后的目录定位：允许 package.json 位于根目录或唯一的一级子目录。
public enum ArchivePackageLocator {
    public static func relativeEntries(in root: URL) -> [String] {
        let rootURL = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var entries: [String] = []
        for case let url as URL in enumerator {
            let resolved = url.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(prefix) else { continue }
            let relative = String(resolved.path.dropFirst(prefix.count))
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            if !isDirectory.boolValue {
                entries.append(relative)
            }
        }
        return entries
    }

    public static func packageRootRelativePath(entries: [String]) -> String? {
        let normalized = entries
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("__MACOSX") }

        if normalized.contains("package.json") {
            return ""
        }

        var topLevelDirectories = Set<String>()
        for entry in normalized {
            let components = entry.split(separator: "/").map(String.init)
            if components.count > 1 {
                topLevelDirectories.insert(components[0])
            }
        }
        if topLevelDirectories.count == 1,
           let only = topLevelDirectories.first,
           normalized.contains("\(only)/package.json") {
            return only
        }
        return nil
    }
}
