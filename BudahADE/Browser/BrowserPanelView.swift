import SwiftUI
import WebKit

// MARK: - Browser Panel View

struct BrowserPanelView: View {
    @Bindable var state: BrowserState
    @State private var urlText: String = ""
    @FocusState private var urlBarFocused: Bool
    var assignedPort: Int?
    var detectedURLs: [URL] = []
    var onPopOut: (() -> Void)?
    var onActivatePicker: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            browserChrome
            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)
            webContent
        }
        .background(Theme.Colors.appBackground)
        .onChange(of: state.url) { _, newURL in
            if let url = newURL {
                urlText = url.absoluteString
            }
        }
    }

    // MARK: - Chrome (URL bar + nav)

    private var browserChrome: some View {
        HStack(spacing: 8) {
            navButtons
            urlBar

            if detectedURLs.count > 1 {
                detectedURLsPicker
            }

            if let port = assignedPort {
                portBadge(port)
            }

            inspectButton

            if let onPopOut {
                Button(action: onPopOut) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pop out to window")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface)
    }

    private var detectedURLsPicker: some View {
        Menu {
            ForEach(detectedURLs, id: \.absoluteString) { url in
                Button(url.absoluteString) {
                    state.navigate(to: url)
                    urlText = url.absoluteString
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                Text("\(detectedURLs.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(Theme.Colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Colors.accent.opacity(0.15))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Detected localhost URLs")
    }

    private var navButtons: some View {
        HStack(spacing: 2) {
            Button(action: { state.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.canGoBack ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.canGoBack)

            Button(action: { state.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.canGoForward ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.canGoForward)

            Button(action: { state.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var urlBar: some View {
        ZStack {
            // Hidden button so Cmd+L focuses the URL bar from anywhere in the browser pane
            Button("") { urlBarFocused = true }
                .keyboardShortcut("l", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)

            TextField("URL", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(6)
                .focused($urlBarFocused)
                .onSubmit {
                    state.navigateToString(urlText)
                    urlBarFocused = false
                }
        }
    }

    private func portBadge(_ port: Int) -> some View {
        Text(":" + String(port))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.Colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Colors.accent.opacity(0.15))
            .cornerRadius(4)
    }

    private var inspectButton: some View {
        let isActive = state.elementPicker.isActive
        return Button(action: {
            if isActive {
                state.elementPicker.deactivate()
            } else {
                onActivatePicker?()
            }
        }) {
            Image(systemName: "cursorarrow.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Exit inspect mode (Esc)" : "Inspect element (⌘⇧I)")
        .keyboardShortcut("i", modifiers: [.command, .shift])
    }

    // MARK: - Web Content

    private var webContent: some View {
        Group {
            if state.webView != nil {
                BrowserWebViewRepresentable(state: state)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Enter a URL or open a localhost preview")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - WebView NSViewRepresentable (for BrowserState)

struct BrowserWebViewRepresentable: NSViewRepresentable {
    let state: BrowserState

    func makeNSView(context: Context) -> WKWebView {
        state.ensureWebView()
        let wv = state.webView!
        context.coordinator.observe(wv, state: state)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private var titleObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?

        func observe(_ webView: WKWebView, state: BrowserState) {
            titleObservation = webView.observe(\.title) { wv, _ in
                Task { @MainActor in state.title = wv.title }
            }
            canGoBackObservation = webView.observe(\.canGoBack) { wv, _ in
                Task { @MainActor in state.canGoBack = wv.canGoBack }
            }
            canGoForwardObservation = webView.observe(\.canGoForward) { wv, _ in
                Task { @MainActor in state.canGoForward = wv.canGoForward }
            }
            urlObservation = webView.observe(\.url) { wv, _ in
                Task { @MainActor in
                    state.url = wv.url
                    state.lastURL = wv.url
                }
            }
            loadingObservation = webView.observe(\.isLoading) { wv, _ in
                Task { @MainActor in state.isLoading = wv.isLoading }
            }
        }
    }
}
