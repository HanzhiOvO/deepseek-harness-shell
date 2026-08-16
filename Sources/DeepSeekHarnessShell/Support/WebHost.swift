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

    // MARK: - 缩放（页面级，不影响窗口尺寸）

    var zoomPercent: Int {
        Int((webView.pageZoom * 100).rounded())
    }

    func zoomIn() {
        webView.pageZoom = min(webView.pageZoom + 0.1, 2.0)
    }

    func zoomOut() {
        webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
    }

    func zoomReset() {
        webView.pageZoom = 1.0
    }

    /// 在官方 Web UI 中打开/恢复一个历史会话。
    /// 通过 React fiber 找到 SessionNodeItem.node.id 对应的会话行并点击；
    /// 找不到时按标题前缀回退；页面尚未就绪时自动重试。
    func openSession(id: String, title: String?, completion: ((Bool) -> Void)? = nil) {
        attemptOpenSession(id: id, title: title, attemptsRemaining: 24, completion: completion)
    }

    private func attemptOpenSession(
        id: String,
        title: String?,
        attemptsRemaining: Int,
        completion: ((Bool) -> Void)?
    ) {
        guard attemptsRemaining > 0 else {
            completion?(false)
            return
        }
        let idJSON = (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let titleJSON: String
        if let title {
            titleJSON = (try? JSONEncoder().encode(title)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        } else {
            titleJSON = "null"
        }

        let script = """
        (function () {
          function fiberOf(el) {
            var key = Object.keys(el).find(function (k) { return k.indexOf('__reactFiber') === 0; });
            return key ? el[key] : null;
          }
          function nameOf(f) {
            if (!f) return '';
            if (f.elementType && f.elementType.name) return String(f.elementType.name);
            return typeof f.type === 'string' ? f.type : '';
          }
          var target = \(idJSON);
          var title = \(titleJSON);
          var rows = Array.from(document.querySelectorAll('[role="treeitem"]'));
          for (var i = 0; i < rows.length; i++) {
            var f = fiberOf(rows[i]);
            while (f) {
              if (nameOf(f) === 'SessionNodeItem') {
                var node = f.memoizedProps && f.memoizedProps.node;
                if (node && node.id === target) {
                  rows[i].click();
                  return JSON.stringify({ ok: true, via: 'id' });
                }
              }
              f = f.return;
            }
          }
          if (title) {
            var norm = function (s) { return (s || '').trim().replace(/\\s+/g, ' '); };
            var prefix = norm(title).slice(0, 18);
            for (var j = 0; j < rows.length; j++) {
              var span = rows[j].querySelector('.YDXeBa_title');
              if (span && norm(span.textContent).slice(0, prefix.length) === prefix && prefix.length > 0) {
                rows[j].click();
                return JSON.stringify({ ok: true, via: 'title' });
              }
            }
          }
          return JSON.stringify({ ok: false });
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            var opened = false
            if error == nil,
               let text = result as? String,
               let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (object["ok"] as? Bool) == true {
                opened = true
            }
            if opened {
                completion?(true)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.attemptOpenSession(
                        id: id,
                        title: title,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                }
            }
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
