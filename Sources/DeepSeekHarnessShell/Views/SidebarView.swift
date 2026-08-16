import SwiftUI
import DeepSeekHarnessCore

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    private var workspaceItems: [SidebarItem] {
        [.chat, .history, .plugins, .logs, .settings]
    }

    private var pinnedSessions: [SessionSummary] {
        model.sessionStore.sessions.filter { model.isPinned($0) }
    }

    var body: some View {
        List(selection: $model.selection) {
            Section("工作区") {
                ForEach(workspaceItems) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            if !pinnedSessions.isEmpty {
                Section("收藏") {
                    ForEach(pinnedSessions.prefix(12)) { session in
                        sessionButton(session, pinned: true)
                    }
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
                        sessionButton(session, pinned: model.isPinned(session))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarBrandHeader()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }

    private func sessionButton(_ session: SessionSummary, pinned: Bool) -> some View {
        Button {
            model.openSessionInWeb(session)
        } label: {
            SessionSidebarRow(session: session, isPinned: pinned)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(pinned ? "取消收藏" : "收藏会话") {
                model.togglePin(session)
            }
            Button("在历史会话中查看") {
                model.showSession(session)
            }
            Button("在 Finder 中显示") {
                model.sessionStore.revealInFinder(session)
            }
        }
    }
}

private struct SidebarBrandHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: 32, systemImage: "terminal.fill")

            VStack(alignment: .leading, spacing: 1) {
                Text("DeepSeek Harness")
                    .font(.headline)
                    .lineLimit(1)
                Text("Shell \(model.appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct SessionSidebarRow: View {
    let session: SessionSummary
    let isPinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(session.displayTitle)
                    .font(.callout)
                    .lineLimit(2)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.accent)
                }
            }
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
        VStack(alignment: .leading, spacing: 7) {
            Button {
                model.showCommandPalette = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "command")
                        .font(.system(size: 10, weight: .bold))
                    Text("快速跳转")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("⌘K")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
