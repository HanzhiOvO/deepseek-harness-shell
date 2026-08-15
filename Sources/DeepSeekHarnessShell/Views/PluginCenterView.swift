import SwiftUI
import DeepSeekHarnessCore

struct PluginCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pluginToRemove: InstalledPlugin?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.plugins.installed.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.plugins.installed) { plugin in
                            PluginCard(plugin: plugin) {
                                pluginToRemove = plugin
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            model.plugins.refreshProfiles()
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
                Task { try? await model.plugins.remove(plugin) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会执行 dsh plugin --profile \(model.plugins.profileName) remove，不会删除本地源文件。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("插件中心")
                    .font(.title2.weight(.semibold))
                Text("插件由 dsh 官方 pnpm 转发器安装进所选 profile，并自动 reconcile bundle 层。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Profile", selection: Binding(
                get: { model.plugins.profileName },
                set: { model.plugins.profileName = $0 }
            )) {
                ForEach(model.plugins.profiles, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(width: 150)

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
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct PluginCard: View {
    let plugin: InstalledPlugin
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: plugin.isBundle ? "puzzlepiece.extension.fill" : "shippingbox")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.body.weight(.medium))
                    if plugin.isBundle {
                        Text("BUNDLE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Text(plugin.sourceKind.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(plugin.spec)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let version = plugin.version {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .help("移除插件")
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}
