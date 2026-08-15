import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 290)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ServerStatusControl()
            }
        }
        .sheet(item: $model.installSheet) { kind in
            InstallPluginSheet(initialKind: kind)
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
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                if model.web.isRunning {
                    model.stopWeb()
                } else {
                    model.startWeb()
                }
            } label: {
                Image(systemName: model.web.isRunning ? "stop.fill" : "play.fill")
            }
            .help(model.web.isRunning ? "停止服务 (⌘.)" : "启动服务 (⌘R)")
            .disabled(startDisabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
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
        case .running(let url): return url.host ?? "运行中"
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
