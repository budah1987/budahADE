import Foundation

// MARK: - Browser Panel

/// Wraps BrowserState for a single browser tab, analogous to TerminalPanel for terminals.
@MainActor
final class BrowserPanel: ObservableObject, Identifiable {
    let id: UUID
    let state: BrowserState
    lazy var popoutWindow = BrowserPopoutWindow(state: state)

    init(id: UUID = UUID(), url: URL? = nil) {
        self.id = id
        self.state = BrowserState()
        if let url {
            state.navigate(to: url)
        }
    }

    func focus() {
        guard let wv = state.webView else { return }
        DispatchQueue.main.async {
            wv.window?.makeFirstResponder(wv)
        }
    }

    func popOut() {
        popoutWindow.open()
    }

    func dockBack() {
        popoutWindow.close()
    }
}
