import Foundation
import WebKit

// MARK: - Log Entry Types

struct ConsoleEntry {
    let level: String     // "log" | "warn" | "error" | "info" | "debug"
    let text: String
    let timestamp: Double // JS Date.now() / 1000 (seconds since epoch)
}

struct NetworkEntry {
    let url: String
    let method: String
    let status: Int
    let duration: Int     // ms
    let timestamp: Double // seconds since epoch
    var error: String?
}

// MARK: - Script Message Handler Bridge

/// NSObject bridge so BrowserState can receive WKScriptMessageHandler callbacks
/// without inheriting from NSObject itself.
private final class ScriptMessageBridge: NSObject, WKScriptMessageHandler {
    let callback: ([String: Any]) -> Void
    init(_ callback: @escaping ([String: Any]) -> Void) { self.callback = callback }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor in self.callback(body) }
    }
}

// MARK: - Browser State

@MainActor
@Observable
final class BrowserState {
    var url: URL?
    var title: String?
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// Last URL for session persistence
    var lastURL: URL?

    /// Console log ring buffer — capped at 200 entries
    private(set) var consoleLogs: [ConsoleEntry] = []
    /// Network request ring buffer — capped at 100 entries
    private(set) var networkLogs: [NetworkEntry] = []

    private(set) var webView: WKWebView?

    /// Element picker — activate to enter hover+click inspect mode
    lazy var elementPicker = ElementPicker()

    // MARK: - Navigation

    func navigate(to url: URL) {
        ensureWebView()
        webView?.load(URLRequest(url: url))
    }

    func navigateToString(_ text: String) {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") { normalized = "https://\(normalized)" }
        if let url = URL(string: normalized) { navigate(to: url) }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    // MARK: - WebView setup

    func ensureWebView() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        let ucc = config.userContentController

        // Console capture
        let consoleHandler = ScriptMessageBridge { [weak self] body in
            self?.handleConsoleMessage(body)
        }
        ucc.add(consoleHandler, name: "consoleCapture")
        ucc.addUserScript(WKUserScript(source: BrowserScripts.consoleCapture,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))

        // Network capture
        let networkHandler = ScriptMessageBridge { [weak self] body in
            self?.handleNetworkMessage(body)
        }
        ucc.add(networkHandler, name: "networkCapture")
        ucc.addUserScript(WKUserScript(source: BrowserScripts.networkCapture,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))

        // Element picker — handler routes to the lazy ElementPicker instance
        let pickerHandler = ScriptMessageBridge { [weak self] body in
            self?.elementPicker.handleMessage(body)
        }
        ucc.add(pickerHandler, name: "elementPicker")

        let wv = WKWebView(frame: .zero, configuration: config)
        self.webView = wv
    }

    // MARK: - Log handlers

    func handleConsoleMessage(_ body: [String: Any]) {
        let entry = ConsoleEntry(
            level: body["level"] as? String ?? "log",
            text: body["text"] as? String ?? "",
            timestamp: (body["timestamp"] as? Double ?? 0) / 1000
        )
        consoleLogs.append(entry)
        if consoleLogs.count > 200 { consoleLogs.removeFirst() }
    }

    func handleNetworkMessage(_ body: [String: Any]) {
        let entry = NetworkEntry(
            url: body["url"] as? String ?? "",
            method: body["method"] as? String ?? "GET",
            status: body["status"] as? Int ?? 0,
            duration: body["duration"] as? Int ?? 0,
            timestamp: (body["timestamp"] as? Double ?? 0) / 1000,
            error: body["error"] as? String
        )
        networkLogs.append(entry)
        if networkLogs.count > 100 { networkLogs.removeFirst() }
    }
}
