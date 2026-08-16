import SwiftUI
import DeepSeekHarnessCore

/// ⌘K 快速跳转面板：搜索工作区页面、最近会话与服务控制。
/// 纯 SwiftUI 浮层，关闭后即释放；没有定时器，不产生空闲能耗。
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    enum PaletteEntry: Identifiable {
        case toggleService
        case syncSessions
        case page(SidebarItem)
        case session(SessionSummary)

        var id: String {
            switch self {
            case .toggleService: return "service"
            case .syncSessions: return "sync"
            case .page(let item): return "page-\(item.rawValue)"
            case .session(let session): return "session-\(session.id)"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                searchBar
                Divider()
                resultList
                Divider()
                footer
            }
            .frame(width: 580)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.22))
            )
            .shadow(color: .black.opacity(0.28), radius: 26, y: 12)
            .padding(.top, 56)
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            query = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
        .onExitCommand { close() }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(Theme.accent)

            TextField("搜索历史会话，或跳转到任意功能…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .onSubmit { execute(entries.first) }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 结果

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("没有匹配结果")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(entries) { entry in
                        PaletteRow(entry: entry, webRunning: model.web.isRunning) {
                            execute(entry)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(minHeight: 120, maxHeight: 380)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("回车执行", systemImage: "return")
            Label("Esc 关闭", systemImage: "escape")
            Spacer()
            Text("\(entries.count) 项结果")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - 数据与动作

    private var entries: [PaletteEntry] {
        var result: [PaletteEntry] = []
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func matches(_ values: String...) -> Bool {
            keyword.isEmpty || values.contains { $0.lowercased().contains(keyword) }
        }

        if matches(model.web.isRunning ? "停止服务" : "启动服务", "harness", "web") {
            result.append(.toggleService)
        }
        if matches("同步", "刷新会话", "历史会话") {
            result.append(.syncSessions)
        }
        for item in SidebarItem.allCases where matches(item.title) {
            result.append(.page(item))
        }
        for session in model.sessionStore.sessions.prefix(60)
        where matches(session.displayTitle, session.workspaceDisplayName, session.projectName, session.id) {
            result.append(.session(session))
        }
        return result
    }

    private func execute(_ entry: PaletteEntry?) {
        guard let entry else { return }
        switch entry {
        case .toggleService:
            if model.web.isRunning {
                model.stopWeb()
            } else {
                model.startWeb()
            }
        case .syncSessions:
            model.syncSessions()
        case .page(let item):
            model.selection = item
        case .session(let session):
            model.openSessionInWeb(session)
        }
        close()
    }

    private func close() {
        model.showCommandPalette = false
    }
}

private struct PaletteRow: View {
    let entry: CommandPaletteView.PaletteEntry
    let webRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconTint.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let badge = trailingBadge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        switch entry {
        case .toggleService: return webRunning ? "停止 DeepSeek Harness 服务" : "启动 DeepSeek Harness"
        case .syncSessions: return "同步本地历史会话"
        case .page(let item): return item.title
        case .session(let session): return session.displayTitle
        }
    }

    private var subtitle: String {
        switch entry {
        case .toggleService: return webRunning ? "关闭本机 Web UI 进程并释放内存" : "启动 dsh web 并自动嵌入官方界面"
        case .syncSessions: return "扫描 ~/.dsh/sessions 并刷新侧边栏"
        case .page(let item):
            switch item {
            case .chat: return "对话工作区"
            case .history: return "浏览本地会话记录"
            case .plugins: return "管理 profile 插件"
            case .logs: return "查看环境 / 服务 / 插件日志"
            case .settings: return "环境检测、API Key 与偏好设置"
            }
        case .session(let session):
            return "\(session.projectName) · \(session.workspaceDisplayName) · \(session.updatedAt?.formatted(.relative(presentation: .named)) ?? "时间未知")"
        }
    }

    private var icon: String {
        switch entry {
        case .toggleService: return webRunning ? "stop.fill" : "play.fill"
        case .syncSessions: return "arrow.triangle.2.circlepath"
        case .page(let item): return item.systemImage
        case .session: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var iconTint: Color {
        switch entry {
        case .toggleService: return webRunning ? Theme.danger : Theme.success
        case .syncSessions: return Theme.accent
        case .page: return Theme.accent
        case .session: return .purple
        }
    }

    private var trailingBadge: String? {
        switch entry {
        case .toggleService: return "⌘R / ⌘."
        case .syncSessions: return "同步"
        case .page: return "页面"
        case .session: return "会话"
        }
    }

}
