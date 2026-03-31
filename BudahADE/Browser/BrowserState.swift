import Foundation
import WebKit

// MARK: - Browser State

@MainActor
@Observable
final class BrowserState {
    var url: URL?
    var title: String?
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// Last URL for session persistence — saved on every navigation
    var lastURL: URL?

    private(set) var webView: WKWebView?

    func navigate(to url: URL) {
        ensureWebView()
        webView?.load(URLRequest(url: url))
    }

    func navigateToString(_ text: String) {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }
        if let url = URL(string: normalized) {
            navigate(to: url)
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func ensureWebView() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv
    }
}
