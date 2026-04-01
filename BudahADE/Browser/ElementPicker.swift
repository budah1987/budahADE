import Foundation
import WebKit
import AppKit

// MARK: - Element Context

struct ElementContext {
    let selector: String
    let html: String
    let rect: CGRect
    let styles: [String: String]
    let tagName: String
    var screenshot: NSImage?
    var screenshotPath: String?

    /// Formatted text block ready to paste into the CLI terminal input.
    func terminalBlock() -> String {
        let stylesStr = styles
            .filter { !$0.value.isEmpty && $0.value != "none" && $0.value != "normal" && $0.value != "auto" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "; ")

        let htmlPreview = String(html.prefix(400))
        var lines = [
            "[Element: \(selector)]",
            "HTML: \(htmlPreview)",
        ]
        if !stylesStr.isEmpty { lines.append("Styles: \(stylesStr)") }
        if let path = screenshotPath { lines.append("Screenshot: .budahade/\(path)") }
        lines.append("")   // trailing newline so cursor sits at start of next line
        return lines.joined(separator: "\n")
    }
}

// MARK: - Element Picker

/// Manages inspect/element-pick mode for a WKWebView.
/// Injects the picker JS on activation and receives the picked element via WKScriptMessageHandler.
@MainActor
final class ElementPicker {
    var onElementPicked: ((ElementContext) -> Void)?
    private(set) var isActive = false
    private weak var webView: WKWebView?

    /// Called by BrowserState's script message handler when the "elementPicker" message arrives.
    func handleMessage(_ body: [String: Any]) {
        guard isActive else { return }
        isActive = false
        webView = nil
        Task {
            let context = await buildContext(from: body)
            onElementPicked?(context)
        }
    }

    /// Injects the picker JS into webView and activates hover+click mode.
    func activate(in webView: WKWebView) {
        guard !isActive else { return }
        self.webView = webView
        isActive = true
        webView.evaluateJavaScript(BrowserScripts.elementPicker) { _, error in
            if let error { print("[ElementPicker] JS inject error: \(error)") }
        }
    }

    /// Removes the picker overlay programmatically (e.g., on Cmd+Shift+I toggle).
    func deactivate() {
        guard isActive else { return }
        isActive = false
        webView?.evaluateJavaScript("window.__budahPickerDeactivate && window.__budahPickerDeactivate()")
        webView = nil
    }

    // MARK: - Context assembly

    private func buildContext(from body: [String: Any]) async -> ElementContext {
        let selector = body["selector"] as? String ?? "unknown"
        let html = body["html"] as? String ?? ""
        let tagName = body["tagName"] as? String ?? ""
        let stylesRaw = body["styles"] as? [String: Any] ?? [:]
        let styles = stylesRaw.compactMapValues { $0 as? String }

        let rectDict = body["rect"] as? [String: Double] ?? [:]
        let rect = CGRect(
            x: rectDict["x"] ?? 0,
            y: rectDict["y"] ?? 0,
            width: rectDict["width"] ?? 0,
            height: rectDict["height"] ?? 0
        )

        var context = ElementContext(selector: selector, html: html, rect: rect,
                                     styles: styles, tagName: tagName)

        // Crop screenshot to element bounds
        if let wv = webView, !rect.isEmpty {
            let config = WKSnapshotConfiguration()
            config.rect = rect
            let image: NSImage? = await withCheckedContinuation { cont in
                wv.takeSnapshot(with: config) { img, _ in cont.resume(returning: img) }
            }
            context.screenshot = image
            let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: " ", with: "")
            context.screenshotPath = "element-\(ts).png"
        }

        return context
    }
}
