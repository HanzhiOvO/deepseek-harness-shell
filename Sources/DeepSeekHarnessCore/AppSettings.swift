import Foundation
import Combine

/// 壳自身的偏好设置，保存于
/// `~/Library/Application Support/DeepSeekHarnessShell/settings.json`。
/// 保存 API Key 时目录权限收紧为 0600。
@MainActor
public final class AppSettings: ObservableObject {
    private struct DiskModel: Codable {
        var autoStartWeb: Bool = true
        var autoInstallDsh: Bool = true
        var stopWhenClosed: Bool = true
        var telemetryDisabled: Bool = true
        var webPort: Int = 0
        var profileName: String = "web"
        var apiKey: String = ""
        var customDshPath: String = ""
        var dshHome: String = ""
    }

    @Published public var autoStartWeb: Bool { didSet { save() } }
    @Published public var autoInstallDsh: Bool { didSet { save() } }
    @Published public var stopWhenClosed: Bool { didSet { save() } }
    @Published public var telemetryDisabled: Bool { didSet { save() } }
    @Published public var webPort: Int { didSet { save() } }
    @Published public var profileName: String { didSet { save() } }
    @Published public var apiKey: String { didSet { save() } }
    @Published public var customDshPath: String { didSet { save() } }
    @Published public var dshHome: String { didSet { save() } }

    public let settingsURL: URL
    private let encoder: JSONEncoder
    private var isLoading = true

    public init(fileManager: FileManager = .default, settingsFileURL: URL? = nil) {
        if let settingsFileURL {
            self.settingsURL = settingsFileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.settingsURL = base
                .appendingPathComponent("DeepSeekHarnessShell", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
        }

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var disk = DiskModel()
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(DiskModel.self, from: data) {
            disk = decoded
        }

        self.autoStartWeb = disk.autoStartWeb
        self.autoInstallDsh = disk.autoInstallDsh
        self.stopWhenClosed = disk.stopWhenClosed
        self.telemetryDisabled = disk.telemetryDisabled
        self.webPort = min(max(disk.webPort, 0), 65535)
        self.profileName = disk.profileName.isEmpty ? "web" : disk.profileName
        self.apiKey = disk.apiKey
        self.customDshPath = disk.customDshPath
        self.dshHome = disk.dshHome
        self.isLoading = false
    }

    public func sanitizedWebPort() -> Int {
        min(max(webPort, 0), 65535)
    }

    private func save() {
        guard !isLoading else { return }
        let disk = DiskModel(
            autoStartWeb: autoStartWeb,
            autoInstallDsh: autoInstallDsh,
            stopWhenClosed: stopWhenClosed,
            telemetryDisabled: telemetryDisabled,
            webPort: sanitizedWebPort(),
            profileName: profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "web" : profileName,
            apiKey: apiKey,
            customDshPath: customDshPath.trimmingCharacters(in: .whitespaces),
            dshHome: dshHome.trimmingCharacters(in: .whitespaces)
        )
        do {
            let dir = settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(disk)
            try data.write(to: settingsURL, options: [.atomic])
            // 设置里可能包含 API Key，收紧权限。
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
        } catch {
            // 设置保存失败不影响运行，UI 会在控制台日志中体现。
            NSLog("DeepSeekHarnessShell: settings save failed: \(error.localizedDescription)")
        }
    }
}
