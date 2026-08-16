import SwiftUI
import AppKit
import DeepSeekHarnessCore

struct PluginCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var pluginToRemove: InstalledPlugin?
    @State private var pluginToUpdate: InstalledPlugin?
    @State private var actionError: String?
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let actionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(actionError)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        self.actionError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
            }

            if filteredPlugins.isEmpty {
                if model.plugins.installed.isEmpty {
                    emptyState
                } else {
                    noMatchState
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPlugins) { plugin in
                            PluginCard(
                                plugin: plugin,
                                isWorking: model.plugins.isWorking,
                                onUpdate: { pluginToUpdate = plugin },
                                onRemove: { pluginToRemove = plugin }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("松开以安装插件")
                            .font(.title3.weight(.semibold))
                        Text("支持 .zip 压缩包或包含 package.json 的文件夹")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            acceptDrop(urls)
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .onAppear {
            model.plugins.refreshProfiles()
        }
        .confirmationDialog(
            "更新插件 \(pluginToUpdate?.name ?? "")",
            isPresented: Binding(
                get: { pluginToUpdate != nil },
                set: { if !$0 { pluginToUpdate = nil } }
            )
        ) {
            Button("更新到最新版本") {
                guard let plugin = pluginToUpdate else { return }
                Task { await performUpdate(plugin) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("等价于 dsh plugin --profile \(model.plugins.profileName) update \(pluginToUpdate?.name ?? "")。本地目录/GitHub 源按原 spec 重新解析，npm 源升级到 latest。")
        }
        .confirmationDialog(
            "移除插件 \(pluginToRemove?.name ?? "")",
            isPresented: Binding(
                get: { pluginToRemove != nil },
                set: { if !$0 { pluginToRemove = nil } }
            )
        ) {
            Button("移除 \(pluginToRemove?.name ?? "")", role: .destructive) {
                guard let plugin = pluginToRemove else { return }
                Task { await performRemove(plugin) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会执行 dsh plugin --profile \(model.plugins.profileName) remove，不会删除本地源文件。")
        }
    }

    private var filteredPlugins: [InstalledPlugin] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return model.plugins.installed }
        return model.plugins.installed.filter {
            $0.name.lowercased().contains(keyword) || $0.spec.lowercased().contains(keyword)
        }
    }

    private func acceptDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        if url.pathExtension.lowercased() == "zip" {
            model.openInstallSheet(.zip, preloadedURL: url)
            return true
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue,
           FileManager.default.fileExists(atPath: url.appendingPathComponent("package.json").path) {
            model.openInstallSheet(.folder, preloadedURL: url)
            return true
        }

        actionError = "拖入的内容不是 .zip 压缩包，也不包含 package.json。"
        return false
    }

    private func performUpdate(_ plugin: InstalledPlugin) async {
        actionError = nil
        do {
            try await model.plugins.update(plugin)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performRemove(_ plugin: InstalledPlugin) async {
        actionError = nil
        do {
            try await model.plugins.remove(plugin)
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                BrandMark(size: 46, systemImage: "puzzlepiece.extension.fill")

                VStack(alignment: .leading, spacing: 3) {
                    Text("插件中心")
                        .font(.title2.weight(.semibold))
                    Text("插件由 dsh 官方 pnpm 转发器安装进所选 profile，并自动 reconcile bundle 层。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    if model.plugins.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    TintBadge(
                        text: "\(model.plugins.installed.count) 个插件",
                        systemImage: "shippingbox.fill",
                        color: Theme.accent
                    )

                    Picker("Profile", selection: Binding(
                        get: { model.plugins.profileName },
                        set: { model.plugins.profileName = $0 }
                    )) {
                        ForEach(model.plugins.profiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 140)

                    Button {
                        model.plugins.refreshProfiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新插件清单")
                    .disabled(model.plugins.isWorking)

                    Menu {
                        ForEach(InstallKind.allCases) { kind in
                            Button {
                                model.installSheet = kind
                            } label: {
                                Label(kind.title, systemImage: kind.systemImage)
                            }
                        }
                    } label: {
                        Label("安装插件", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索插件名称或安装 spec", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .background(Theme.bannerGradient.opacity(0.55))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient.opacity(0.16))
                    .frame(width: 96, height: 96)
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.accent)
            }

            Text("这个 profile 还没有插件")
                .font(.title3.weight(.medium))
            Text("支持四种方式：GitHub 仓库地址、上传 ZIP 压缩包、选择本地文件夹，或直接输入 npm 包名。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Menu {
                ForEach(InstallKind.allCases) { kind in
                    Button {
                        model.installSheet = kind
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            } label: {
                Label("安装第一个插件", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var noMatchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有匹配的插件")
                .font(.title3.weight(.medium))
            Button("清除搜索") {
                searchText = ""
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct PluginCard: View {
    let plugin: InstalledPlugin
    let isWorking: Bool
    let onUpdate: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)

                    if plugin.isInbox {
                        TintBadge(text: "内置", systemImage: "shippingbox.fill", color: .indigo)
                    } else if plugin.isBundle {
                        TintBadge(text: "BUNDLE", systemImage: "puzzlepiece.fill", color: .blue)
                    }
                    TintBadge(
                        text: plugin.sourceKind.label,
                        systemImage: plugin.sourceKind.systemImage,
                        color: plugin.isInbox ? .secondary : badgeColor
                    )
                }
                Text(plugin.spec)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let version = plugin.version {
                    Text("v\(version)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !plugin.isInbox {
                HStack(spacing: 8) {
                    Button {
                        onUpdate()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("更新插件")
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("移除插件")
                    .disabled(isWorking)
                }
                .buttonStyle(.borderless)
                .opacity(hovering ? 1 : 0.45)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("内置 bundle，不可移除")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovering ? Theme.accent.opacity(0.07) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? Theme.cardStrokeStrong : Theme.cardStroke)
        )
        .shadow(color: .black.opacity(hovering ? 0.08 : 0.03), radius: hovering ? 6 : 3, y: 2)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            if !plugin.isInbox {
                Button("更新插件") { onUpdate() }
            }
            if let externalURL = plugin.externalURL {
                Button("打开插件主页") {
                    NSWorkspace.shared.open(externalURL)
                }
            }
            if let localSource = plugin.localSourceURL,
               FileManager.default.fileExists(atPath: localSource.path) {
                Button("在 Finder 中显示源码") {
                    NSWorkspace.shared.activateFileViewerSelecting([localSource])
                }
            }
            Button("复制包名") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plugin.name, forType: .string)
            }
            Button("复制安装 spec") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plugin.spec, forType: .string)
            }
            if !plugin.isInbox {
                Divider()
                Button("移除插件", role: .destructive) { onRemove() }
            }
        }
    }

    private var iconName: String {
        switch plugin.sourceKind {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .zip: return "doc.zipper.fill"
        case .folder: return "folder.fill"
        case .npm: return "shippingbox.fill"
        }
    }

    private var badgeColor: Color {
        switch plugin.sourceKind {
        case .github: return .purple
        case .zip: return .orange
        case .folder: return .green
        case .npm: return .pink
        }
    }

    private var iconGradient: LinearGradient {
        if plugin.isInbox {
            return LinearGradient(colors: [Color.indigo, Color.indigo.opacity(0.65)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private extension InstalledPlugin.SourceKind {
    var systemImage: String {
        switch self {
        case .github: return "link"
        case .zip: return "doc.zipper"
        case .folder: return "folder"
        case .npm: return "shippingbox"
        }
    }
}
