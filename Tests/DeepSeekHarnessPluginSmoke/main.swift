import DeepSeekHarnessCore
import Foundation
import Darwin

@main
struct PluginSmokeMain {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-shell-plugin-smoke-\(UUID().uuidString)", isDirectory: true)
        let settingsDir = root.appendingPathComponent("settings", isDirectory: true)
        let dshHome = root.appendingPathComponent("dsh-home", isDirectory: true)
        try? FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dshHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings(settingsFileURL: settingsDir.appendingPathComponent("settings.json"))
        settings.dshHome = dshHome.path
        settings.profileName = "web"

        let environment = EnvironmentManager(settings: settings)
        await environment.detect()
        guard environment.dshExecutable != nil else {
            print("SMOKE FAIL: dsh 不可用")
            exit(1)
        }

        print("== 确保 pnpm 可用 ==")
        environment.logs.append(.info, "smoke: calling ensurePnpm")
        guard await environment.ensurePnpm() else {
            print("SMOKE FAIL: pnpm 安装失败")
            exit(1)
        }
        print("pnpm: \(environment.tools.pnpm?.version ?? "?")")

        let plugins = PluginManager(environment: environment, settings: settings)
        plugins.refreshProfiles()

        // 1) 文件夹安装
        let folderPlugin = root.appendingPathComponent("folder-plugin", isDirectory: true)
        try makeBundlePackage(at: folderPlugin, name: "smoke-folder-plugin", version: "0.0.1")
        print("== 从本地文件夹安装 ==")
        do {
            try await plugins.installFromFolder(folderPlugin)
            let target = plugins.installed.first { $0.name == "smoke-folder-plugin" }
            guard target?.isBundle == true else {
                print("SMOKE FAIL: 文件夹插件未出现在清单 / 未识别为 bundle")
                exit(1)
            }
            print("PASS  文件夹插件已安装: \(target!.name) bundle=\(target!.isBundle)")
        } catch {
            print("SMOKE FAIL: 文件夹安装 \(error.localizedDescription)")
            exit(1)
        }

        // 2) ZIP 安装（package.json 在唯一顶层目录）
        let zipPluginDir = root.appendingPathComponent("zip-plugin", isDirectory: true)
        try makeBundlePackage(at: zipPluginDir, name: "smoke-zip-plugin", version: "0.0.2")
        let zipURL = root.appendingPathComponent("plugin.zip")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--sequesterRsrc", zipPluginDir.path, zipURL.path]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        print("== 从 ZIP 压缩包安装 ==")
        do {
            try await plugins.installFromZip(zipURL)
            let target = plugins.installed.first { $0.name == "smoke-zip-plugin" }
            guard target != nil else {
                print("SMOKE FAIL: ZIP 插件未出现在清单")
                exit(1)
            }
            print("PASS  ZIP 插件已安装: \(target!.name)")
        } catch {
            print("SMOKE FAIL: ZIP 安装 \(error.localizedDescription)")
            for entry in plugins.logs.entries.suffix(20) {
                print("  log: \(entry.text)")
            }
            exit(1)
        }

        // 3) 更新（本地目录源按原 spec 重新解析，应保持安装）
        print("== 更新 ZIP 插件 ==")
        do {
            guard let target = plugins.installed.first(where: { $0.name == "smoke-zip-plugin" }) else {
                print("SMOKE FAIL: 找不到待更新插件")
                exit(1)
            }
            try await plugins.update(target)
            guard plugins.installed.contains(where: { $0.name == "smoke-zip-plugin" }) else {
                print("SMOKE FAIL: 更新后插件丢失")
                exit(1)
            }
            print("PASS  插件更新命令完成: \(target.name)")
        } catch {
            print("SMOKE FAIL: 更新 \(error.localizedDescription)")
            for entry in plugins.logs.entries.suffix(25) {
                print("  log: \(entry.text)")
            }
            exit(1)
        }

        // 4) 移除
        print("== 移除文件夹插件 ==")
        do {
            guard let target = plugins.installed.first(where: { $0.name == "smoke-folder-plugin" }) else {
                print("SMOKE FAIL: 找不到待移除插件")
                exit(1)
            }
            try await plugins.remove(target)
            guard !plugins.installed.contains(where: { $0.name == "smoke-folder-plugin" }) else {
                print("SMOKE FAIL: 插件未被移除")
                exit(1)
            }
            print("PASS  插件已移除")
        } catch {
            print("SMOKE FAIL: 移除 \(error.localizedDescription)")
            for entry in plugins.logs.entries.suffix(25) {
                print("  log: \(entry.text)")
            }
            exit(1)
        }

        let profileManifest = plugins.profileDirectory.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: profileManifest.path) else {
            print("SMOKE FAIL: 临时 profile package.json 不存在")
            exit(1)
        }
        print("profile: \(profileManifest.path)")
        print("PLUGIN SMOKE PASS")
        exit(0)
    }

    static func makeBundlePackage(at url: URL, name: String, version: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": name,
            "version": version,
            "private": true,
            "dsh": ["bundle": ["patch": "patch.yml"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try data.write(to: url.appendingPathComponent("package.json"))
        try "[]\n".write(to: url.appendingPathComponent("patch.yml"), atomically: true, encoding: .utf8)
    }
}
