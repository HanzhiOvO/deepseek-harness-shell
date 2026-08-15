import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if case .running(let url) = model.web.state, let host = model.webHost {
                WebToolbar(host: host, url: url)
                Divider()
                WebContainerView(host: host)
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

    var body: some View {
        HStack(spacing: 8) {
            Button {
                host.webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!host.webView.canGoBack)

            Button {
                host.webView.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!host.webView.canGoForward)

            Button {
                host.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            if host.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                openURL(url)
            } label: {
                Image(systemName: "safari")
            }
            .help("在浏览器中打开")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
