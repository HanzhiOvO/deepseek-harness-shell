import SwiftUI
import AppKit
import DeepSeekHarnessCore

struct SessionHistoryView: View {
    @EnvironmentObject private var model: AppModel

    @State private var searchText = ""
    @State private var pinnedOnly = false
    @State private var sortMode: SortMode = .updated

    private enum SortMode: String, CaseIterable, Identifiable {
        case updated = "最近更新"
        case created = "创建时间"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.sessionStore.sessions.isEmpty {
                emptyState
            } else if filteredSessions.isEmpty {
                noMatchState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSessions) { session in
                            SessionHistoryCard(
                                session: session,
                                isPinned: model.isPinned(session)
                            ) {
                                model.openSessionInWeb(session)
                            } onTogglePin: {
                                model.togglePin(session)
                            } onReveal: {
                                model.sessionStore.revealInFinder(session)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear {
            model.syncSessions()
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("历史会话")
                            .font(.title2.weight(.semibold))
                        TintBadge(
                            text: "\(filteredSessions.count) 个会话",
                            systemImage: "bubble.left.and.text.bubble.right.fill",
                            color: Theme.accent
                        )
                    }
                    Text("从本地 \(model.sessionStore.sessionsRoot.path) 读取，与 Harness Web UI 使用同一份数据，只读同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let syncedAt = model.sessionStore.lastSyncAt {
                    Label("上次同步 \(syncedAt.formatted(date: .omitted, time: .shortened))",
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    model.syncSessions()
                } label: {
                    if model.sessionStore.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.sessionStore.isSyncing)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、工作区、project 或会话 ID", text: $searchText)
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

                Button {
                    pinnedOnly.toggle()
                } label: {
                    Label(pinnedOnly ? "仅收藏" : "收藏", systemImage: pinnedOnly ? "pin.fill" : "pin")
                }
                .buttonStyle(.bordered)
                .tint(pinnedOnly ? Theme.accent : .secondary)

                Picker("排序", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()
            }
        }
        .padding(16)
    }

    // MARK: - 过滤与排序

    private var filteredSessions: [SessionSummary] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = model.sessionStore.sessions.filter { session in
            if pinnedOnly && !model.isPinned(session) { return false }
            guard !keyword.isEmpty else { return true }
            return session.displayTitle.lowercased().contains(keyword)
                || session.workspaceDisplayName.lowercased().contains(keyword)
                || session.projectName.lowercased().contains(keyword)
                || session.id.lowercased().contains(keyword)
                || (session.workspacePath?.lowercased().contains(keyword) ?? false)
        }
        switch sortMode {
        case .updated:
            result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .created:
            result.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
        return result
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有找到本地历史会话")
                .font(.title3.weight(.medium))
            Text("在 Harness Web UI 中开始新会话后，这里会自动同步；应用回到前台时也会自动刷新。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("立即同步") {
                model.syncSessions()
            }
            .buttonStyle(.borderedProminent)
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
            Text("没有符合筛选条件的会话")
                .font(.title3.weight(.medium))
            Button("清除筛选") {
                searchText = ""
                pinnedOnly = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct SessionHistoryCard: View {
    let session: SessionSummary
    let isPinned: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onReveal: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.softAccentGradient)
                    .frame(width: 42, height: 42)
                Image(systemName: isPinned ? "pin.fill" : "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.displayTitle)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                    if isPinned {
                        TintBadge(text: "收藏", systemImage: "pin.fill", color: Theme.accent)
                    }
                }

                HStack(spacing: 6) {
                    TintBadge(text: session.projectName, systemImage: "shippingbox", color: .indigo)
                    Text(session.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 16) {
                    Label(session.workspacePath ?? "未知工作区", systemImage: "externaldrive")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let createdAt = session.createdAt {
                        Label("创建于 \(createdAt.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "calendar")
                    }
                    if let updatedAt = session.updatedAt {
                        Label("更新于 \(updatedAt.formatted(.relative(presentation: .named)))",
                              systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    onTogglePin()
                } label: {
                    Image(systemName: isPinned ? "pin.slash" : "pin")
                }
                .help(isPinned ? "取消收藏" : "收藏会话")

                Button {
                    onOpen()
                } label: {
                    Label("在 Harness 中打开", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.accent)

                Menu {
                    Button("复制会话 ID") {
                        copy(session.id)
                    }
                    Button("复制会话文件路径") {
                        copy(session.fileURL.path)
                    }
                    if let workspace = session.workspacePath, !workspace.isEmpty {
                        Button("复制工作区路径") {
                            copy(workspace)
                        }
                    }
                    Divider()
                    Button("在 Finder 中显示") {
                        onReveal()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多操作")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.75)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovering ? Theme.accent.opacity(0.055) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? Theme.cardStrokeStrong : Theme.cardStroke)
        )
        .shadow(color: .black.opacity(hovering ? 0.07 : 0.025), radius: hovering ? 7 : 3, y: 2)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
        .contextMenu {
            Button("在 Harness 中打开") { onOpen() }
            Button(isPinned ? "取消收藏" : "收藏会话") { onTogglePin() }
            Divider()
            Button("复制会话 ID") { copy(session.id) }
            Button("复制会话文件路径") { copy(session.fileURL.path) }
            Divider()
            Button("在 Finder 中显示") { onReveal() }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
