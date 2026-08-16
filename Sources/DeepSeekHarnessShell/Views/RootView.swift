import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 216, ideal: 246, max: 300)
            } detail: {
                detail
            }
            .tint(Theme.accent)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ServerStatusControl()
                }
            }

            if model.showCommandPalette {
                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.showCommandPalette)
        .sheet(item: $model.installSheet) { kind in
            InstallPluginSheet(initialKind: kind)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
                .environmentObject(model)
        }
        .onAppear {
            model.bootstrap()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .chat:
            ChatView()
        case .history:
            SessionHistoryView()
        case .plugins:
            PluginCenterView()
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }
}

private struct ServerStatusControl: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if case .running(let url) = model.web.state {
                    Text("\(url.host ?? ""):\(url.port ?? 0)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button {
                if model.web.isRunning {
                    model.stopWeb()
                } else {
                    model.startWeb()
                }
            } label: {
                Image(systemName: model.web.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Theme.accent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help(model.web.isRunning ? "停止服务 (⌘.)" : "启动服务 (⌘R)")
            .disabled(startDisabled)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private var color: Color {
        switch model.web.state {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var label: String {
        switch model.web.state {
        case .running: return "Harness 运行中"
        case .starting: return "正在启动…"
        case .failed: return "服务异常"
        case .stopped: return "服务未启动"
        }
    }

    private var startDisabled: Bool {
        if case .starting = model.web.state { return true }
        switch model.environment.state {
        case .ready: return false
        default: return model.environment.npmExecutable == nil
        }
    }
}
