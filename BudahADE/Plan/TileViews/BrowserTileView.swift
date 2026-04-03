import SwiftUI
import WebKit

// MARK: - Browser Tile View

struct BrowserTileView: View {
    let initialURL: URL?
    let onClose: () -> Void
    var isVisible: Bool = true  // when false, replaces WKWebView with a lightweight placeholder

    @State private var urlText: String
    @State private var webViewStore = WebViewStore()

    init(url: URL?, onClose: @escaping () -> Void, isVisible: Bool = true) {
        self.initialURL = url
        self.onClose = onClose
        self.isVisible = isVisible
        _urlText = State(initialValue: url?.absoluteString ?? "")
    }

    var body: some View {
        TileChrome(
            title: webViewStore.title ?? "Browser",
            icon: "globe",
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                // URL bar
                HStack(spacing: 6) {
                    Button(action: { webViewStore.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!webViewStore.canGoBack)

                    Button(action: { webViewStore.goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!webViewStore.canGoForward)

                    Button(action: { webViewStore.reload() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)

                    TextField("URL", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(Theme.body(11))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.surfaceElevated)
                        .cornerRadius(4)
                        .onSubmit { navigateToURL() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Colors.surface)

                Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)

                // WebView or lightweight placeholder when offscreen
                if isVisible {
                    WebViewRepresentable(store: webViewStore)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.Colors.textTertiary)
                        if let url = initialURL {
                            Text(url.host ?? url.absoluteString)
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if let url = initialURL {
                webViewStore.navigate(to: url)
            }
        }
    }

    private func navigateToURL() {
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "https://\(text)"
        }
        if let url = URL(string: text) {
            webViewStore.navigate(to: url)
        }
    }
}

// MARK: - WebView Store

@MainActor
@Observable
final class WebViewStore {
    var title: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    private(set) var webView: WKWebView?

    func navigate(to url: URL) {
        ensureWebView()
        webView?.load(URLRequest(url: url))
    }

    func loadHTML(_ html: String, baseURL: URL? = nil) {
        ensureWebView()
        webView?.loadHTMLString(html, baseURL: baseURL)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    private func ensureWebView() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv
    }
}

// MARK: - WebView NSViewRepresentable

struct WebViewRepresentable: NSViewRepresentable {
    let store: WebViewStore

    func makeNSView(context: Context) -> WKWebView {
        store.navigate(to: URL(string: "about:blank")!) // ensure webView exists
        let wv = store.webView!
        context.coordinator.observe(wv, store: store)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private var titleObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?

        func observe(_ webView: WKWebView, store: WebViewStore) {
            titleObservation = webView.observe(\.title) { wv, _ in
                Task { @MainActor in store.title = wv.title }
            }
            canGoBackObservation = webView.observe(\.canGoBack) { wv, _ in
                Task { @MainActor in store.canGoBack = wv.canGoBack }
            }
            canGoForwardObservation = webView.observe(\.canGoForward) { wv, _ in
                Task { @MainActor in store.canGoForward = wv.canGoForward }
            }
        }
    }
}
