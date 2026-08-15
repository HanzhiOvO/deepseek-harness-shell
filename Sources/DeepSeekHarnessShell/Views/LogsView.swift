import SwiftUI
import DeepSeekHarnessCore

struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            logSection(title: "环境", entries: model.environment.logs.entries)
            logSection(title: "Web 服务", entries: model.web.logs.entries)
            logSection(title: "插件中心", entries: model.plugins.logs.entries)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("运行日志")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("清空全部日志") {
                    model.environment.logs.clear()
                    model.web.logs.clear()
                    model.plugins.logs.clear()
                }
            }
            .padding(16)
            .background(.bar)
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
    static func color(for level: LogLevel) -> Color {
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
