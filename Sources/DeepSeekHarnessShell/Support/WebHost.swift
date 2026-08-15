import SwiftUI
import WebKit
import Combine

/// 系统 WKWebView 宿主：只承载 dsh 官方 Web UI。
/// 相比 Electron 不再捆绑 Chromium；服务停止后该对象被释放，
/// WebKit 内容进程随之退出，空闲内存与能耗回到接近零。
final class WebHost: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView

    @Published var isLoading = false
    @Published var pageTitle = "DeepSeek Harness"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        self.webView = view
        super.init()
        view.navigationDelegate = self
    }

    func load(_ url: URL) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    func reload() {
        if webView.url != nil {
            webView.reload()
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        pageTitle = webView.title ?? "DeepSeek Harness"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

struct WebContainerView: NSViewRepresentable {
    @ObservedObject var host: WebHost

    func makeNSView(context: Context) -> WKWebView {
        host.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
