import SwiftUI
import DeepSeekHarnessCore

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    private var workspaceItems: [SidebarItem] {
        [.chat, .plugins, .logs, .settings]
    }

    var body: some View {
        List(selection: $model.selection) {
            Section("工作区") {
                ForEach(workspaceItems) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            Section {
                if model.sessionStore.sessions.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .foregroundStyle(.tertiary)
                        Text("暂无本地会话")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                    .padding(.vertical, 2)
                } else {
                    ForEach(model.sessionStore.sessions.prefix(40)) { session in
                        Button {
                            model.showSession(session)
                        } label: {
                            SessionSidebarRow(session: session)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("历史会话")
                    Spacer()
                    Button {
                        model.syncSessions()
                    } label: {
                        if model.sessionStore.isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("同步本地历史会话")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }
}

private struct SessionSidebarRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.displayTitle)
                .font(.callout)
                .lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text(session.workspaceDisplayName)
                    .lineLimit(1)
                Text("·")
                Text(relativeDate)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var relativeDate: String {
        guard let date = session.updatedAt else { return "未知时间" }
        return date.formatted(.relative(presentation: .named))
    }
}

private struct SidebarFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(environmentColor)
                    .frame(width: 7, height: 7)
                Text(environmentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(webColor)
                    .frame(width: 7, height: 7)
                Text(webLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text("本地会话 \(model.sessionStore.sessions.count) 个")
                if let syncedAt = model.sessionStore.lastSyncAt {
                    Text("· 已同步 \(syncedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)

            if let version = model.environment.tools.dsh?.version {
                Text("dsh \(version) · 原生 SwiftUI · 低能耗壳")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var environmentLabel: String {
        model.environment.state.label
    }

    private var environmentColor: Color {
        switch model.environment.state {
        case .ready: return .green
        case .checking, .installing: return .orange
        case .missingDsh, .missingNode, .missingNpm, .failed: return .red
        case .idle: return .secondary
        }
    }

    private var webLabel: String {
        switch model.web.state {
        case .running: return "Web UI 运行中"
        case .starting: return "Web UI 启动中"
        case .failed: return "Web UI 异常"
        case .stopped: return "Web UI 未启动"
        }
    }

    private var webColor: Color {
        switch model.web.state {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }
}
