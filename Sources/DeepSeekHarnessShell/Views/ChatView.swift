import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if case .running(let url) = model.web.state, let host = model.webHost {
                WebToolbar(host: host, url: url)
                Divider()
                ZStack(alignment: .top) {
                    WebContainerView(host: host)
                    if host.isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .tint(Theme.accent)
                    }
                }
            } else {
                PlaceholderView()
            }
        }
    }
}

private struct WebToolbar: View {
    @ObservedObject var host: WebHost
    let url: URL
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            toolbarButton("chevron.left", help: "后退") {
                host.webView.goBack()
            }
            .disabled(!host.webView.canGoBack)

            toolbarButton("chevron.right", help: "前进") {
                host.webView.goForward()
            }
            .disabled(!host.webView.canGoForward)

            toolbarButton("arrow.clockwise", help: "刷新") {
                host.reload()
            }

            Divider()
                .frame(height: 16)

            toolbarButton("minus.magnifyingglass", help: "缩小 (⌘−)") {
                host.zoomOut()
            }

            Button {
                host.zoomReset()
            } label: {
                Text("\(host.zoomPercent)%")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .frame(width: 44)
            }
            .buttonStyle(.borderless)
            .help("实际大小 (⌘0)")

            toolbarButton("plus.magnifyingglass", help: "放大 (⌘+)") {
                host.zoomIn()
            }

            Divider()
                .frame(height: 16)

            HStack(spacing: 6) {
                if host.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.success)
                Text(host.pageTitle.isEmpty ? "DeepSeek Harness" : host.pageTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            toolbarButton(copied ? "checkmark" : "doc.on.doc", help: "复制服务地址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    copied = false
                }
            }

            toolbarButton("safari", help: "在浏览器中打开") {
                openURL(url)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func toolbarButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
