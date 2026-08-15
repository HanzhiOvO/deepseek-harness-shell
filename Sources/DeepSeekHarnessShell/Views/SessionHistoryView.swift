import SwiftUI
import AppKit
import DeepSeekHarnessCore

struct SessionHistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.sessionStore.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.sessionStore.sessions) { session in
                            SessionHistoryCard(session: session) {
                                model.sessionStore.revealInFinder(session)
                            } onCopy: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(session.id, forType: .string)
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

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("历史会话")
                    .font(.title2.weight(.semibold))
                Text("从本地 \(model.sessionStore.sessionsRoot.path) 读取，与 Harness Web UI 使用同一份数据，只读同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let syncedAt = model.sessionStore.lastSyncAt {
                Text("上次同步 \(syncedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                model.syncSessions()
            } label: {
                Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(model.sessionStore.isSyncing)
        }
        .padding(16)
    }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct SessionHistoryCard: View {
    let session: SessionSummary
    let onReveal: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Text(session.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("复制会话 ID")

                    Button {
                        onReveal()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("在 Finder 中显示会话文件")
                }
                .buttonStyle(.borderless)
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
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}
