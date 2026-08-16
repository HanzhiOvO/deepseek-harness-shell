import SwiftUI
import AppKit
import DeepSeekHarnessCore

struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var source: LogSource = .all
    @State private var levelFilter: LogLevel?
    @State private var searchText = ""

    private enum LogSource: String, CaseIterable, Identifiable {
        case all = "全部"
        case environment = "环境"
        case web = "Web 服务"
        case plugins = "插件"
        case sessions = "会话"

        var id: String { rawValue }
    }

    var body: some View {
        List {
            if totalVisibleCount == 0 {
                Text("当前筛选条件下没有日志")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                if source == .all || source == .environment {
                    logSection(title: "环境", entries: filtered(model.environment.logs.entries))
                }
                if source == .all || source == .web {
                    logSection(title: "Web 服务", entries: filtered(model.web.logs.entries))
                }
                if source == .all || source == .plugins {
                    logSection(title: "插件中心", entries: filtered(model.plugins.logs.entries))
                }
                if source == .all || source == .sessions {
                    logSection(title: "会话同步", entries: filtered(model.sessionStore.logs.entries))
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("运行日志", systemImage: "terminal.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)

                Spacer()

                Text("\(totalVisibleCount) 条")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button("导出") {
                    exportLogs()
                }
                Button("清空全部") {
                    model.environment.logs.clear()
                    model.web.logs.clear()
                    model.plugins.logs.clear()
                    model.sessionStore.logs.clear()
                }
            }

            HStack(spacing: 8) {
                Picker("来源", selection: $source) {
                    ForEach(LogSource.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索日志内容", text: $searchText)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Menu {
                    Button("全部级别") { levelFilter = nil }
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Button {
                            levelFilter = level
                        } label: {
                            Label(level.displayName, systemImage: levelFilter == level ? "checkmark" : "circle.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(LogLevelTint.color(for: levelFilter))
                            .frame(width: 7, height: 7)
                        Text(levelFilter?.displayName ?? "全部级别")
                            .font(.caption)
                    }
                }
                .fixedSize()

                Spacer()
            }
        }
        .padding(16)
        .background(.bar)
    }

    // MARK: - 过滤

    private var totalVisibleCount: Int {
        [filtered(model.environment.logs.entries).count,
         filtered(model.web.logs.entries).count,
         filtered(model.plugins.logs.entries).count,
         filtered(model.sessionStore.logs.entries).count].reduce(0, +)
    }

    private func filtered(_ entries: [LogEntry]) -> [LogEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let levelFilter, entry.level != levelFilter { return false }
            guard !keyword.isEmpty else { return true }
            return entry.text.lowercased().contains(keyword)
        }
    }

    private func logSection(title: String, entries: [LogEntry]) -> some View {
        Section(title) {
            if entries.isEmpty {
                Text("暂无日志")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(entries.reversed()) { entry in
                    LogRow(entry: entry)
                }
            }
        }
    }

    // MARK: - 导出

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.title = "导出运行日志"
        panel.nameFieldStringValue = "DeepSeekHarnessShell-\(Date().formatted(date: .numeric, time: .omitted))-logs.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let lines = allEntries().map { entry in
                "[\(formatter.string(from: entry.date))] [\(entry.level.rawValue.uppercased())] \(entry.text)"
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func allEntries() -> [LogEntry] {
        let all = model.environment.logs.entries
            + model.web.logs.entries
            + model.plugins.logs.entries
            + model.sessionStore.logs.entries
        return all.sorted { $0.date < $1.date }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Circle()
                .fill(LogLevelTint.color(for: entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(entry.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(LogLevelTint.color(for: entry.level))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

enum LogLevelTint {
    static func color(for level: LogLevel?) -> Color {
        guard let level else { return .secondary }
        switch level {
        case .info, .stdout: return .primary
        case .command: return .blue
        case .stderr: return .orange
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

extension LogLevel: CaseIterable {
    public static var allCases: [LogLevel] {
        [.info, .command, .stdout, .stderr, .warning, .error, .success]
    }

    var displayName: String {
        switch self {
        case .info: return "信息"
        case .command: return "命令"
        case .stdout: return "标准输出"
        case .stderr: return "标准错误"
        case .warning: return "警告"
        case .error: return "错误"
        case .success: return "成功"
        }
    }
}
