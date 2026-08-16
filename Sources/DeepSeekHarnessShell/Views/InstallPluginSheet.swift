import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DeepSeekHarnessCore

struct InstallPluginSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let initialKind: InstallKind
    @State private var kind: InstallKind
    @State private var githubText = ""
    @State private var npmText = ""
    @State private var zipURL: URL?
    @State private var folderURL: URL?
    @State private var showZipPicker = false
    @State private var showFolderPicker = false
    @State private var running = false
    @State private var errorMessage: String?

    init(initialKind: InstallKind) {
        self.initialKind = initialKind
        _kind = State(initialValue: initialKind)
    }

    private static let zipType = UTType(filenameExtension: "zip") ?? .archive

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandMark(size: 44, systemImage: "plus.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("安装插件")
                        .font(.title2.weight(.semibold))
                    Text("选择来源并安装到 profile「\(model.plugins.profileName)」")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TintBadge(text: model.plugins.profileName, systemImage: "shippingbox.fill", color: Theme.accent)
            }

            Picker("安装方式", selection: $kind) {
                ForEach(InstallKind.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Theme.accent)

            Group {
                switch kind {
                case .github:
                    githubSection
                case .zip:
                    zipSection
                case .folder:
                    folderSection
                case .npm:
                    npmSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            logTail

            Divider()

            HStack {
                Label("插件是本地代码，会以当前用户权限运行，只安装你信任的来源。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await install() }
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("安装")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(running || model.plugins.isWorking)
            }
        }
        .padding(22)
        .frame(width: 580)
        .interactiveDismissDisabled(running)
        .fileImporter(
            isPresented: $showZipPicker,
            allowedContentTypes: [Self.zipType],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                zipURL = urls.first
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                folderURL = urls.first
            }
        }
        .onAppear {
            applyPreloadedURL()
            autofillFromClipboard()
        }
    }

    /// 拖入 ZIP / 文件夹时，安装面板自动预填路径。
    private func applyPreloadedURL() {
        guard let preloaded = model.installPreloadedURL else { return }
        switch kind {
        case .zip where preloaded.pathExtension.lowercased() == "zip":
            zipURL = preloaded
        case .folder:
            folderURL = preloaded
        default:
            break
        }
    }

    /// 如果剪贴板里是 GitHub 地址，自动填入，少一次粘贴。
    private func autofillFromClipboard() {
        guard githubText.isEmpty,
              let text = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              text.contains("github.com") || (text.contains("/") && !text.contains("\n")) else { return }
        if (try? GitHubSpecParser.parse(text)) != nil {
            githubText = text
        }
    }

    // MARK: - 各安装方式

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub 仓库地址")
                .font(.headline)
            TextField("owner/repo  或  https://github.com/owner/repo", text: $githubText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await install() } }

            if let parsed = try? GitHubSpecParser.parse(githubText) {
                Label("将安装 github:\(parsed.owner)/\(parsed.repository)\(parsed.ref.map { "#\($0)" } ?? "")",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("无需本机安装 git：应用会交给 pnpm 的 github: 协议拉取仓库 tarball。默认取默认分支，可追加 #分支名。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var zipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("上传 ZIP 压缩包")
                .font(.headline)
            HStack {
                Text(zipURL?.lastPathComponent ?? "未选择文件")
                    .font(.callout)
                    .foregroundStyle(zipURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Button("选择 .zip…") {
                    showZipPicker = true
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Text("解压后自动定位 package.json（根目录或唯一顶层文件夹），源码保存在应用数据目录 PluginSources，保证后续 pnpm 更新/移除其它插件时仍可解析。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择本地插件文件夹")
                .font(.headline)
            HStack {
                Text(folderURL?.path ?? "未选择文件夹")
                    .font(.callout)
                    .foregroundStyle(folderURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("选择文件夹…") {
                    showFolderPicker = true
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            Text("必须包含 package.json。应用直接以 file: 路径安装（不复制源码、省磁盘）；请勿在插件使用期间移动或删除该文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var npmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("npm 包名")
                .font(.headline)
            TextField("@scope/plugin-name", text: $npmText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await install() } }
            Text("等价于 dsh plugin --profile \(model.plugins.profileName) add <package>。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var logTail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.plugins.logs.entries.suffix(10)) { entry in
                    Text(entry.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(LogLevelTint.color(for: entry.level))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 110)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Text("实时日志")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(6)
        }
    }

    // MARK: - 安装动作

    private func install() async {
        guard !running else { return }
        running = true
        errorMessage = nil
        defer { running = false }

        do {
            switch kind {
            case .github:
                try await model.plugins.installFromGitHub(githubText)
            case .zip:
                guard let url = zipURL else {
                    throw PluginManagerError.invalidPackage("请先选择 .zip 压缩包")
                }
                try await installFromScoped(url) {
                    try await model.plugins.installFromZip(url)
                }
            case .folder:
                guard let url = folderURL else {
                    throw PluginManagerError.invalidPackage("请先选择插件文件夹")
                }
                try await installFromScoped(url) {
                    try await model.plugins.installFromFolder(url)
                }
            case .npm:
                try await model.plugins.installFromNpm(npmText)
            }
            model.plugins.loadInstalled()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installFromScoped(_ url: URL, operation: () async throws -> Void) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        try await operation()
    }
}
