import Foundation

// MARK: - Browser Panel

/// Wraps BrowserState for a single browser tab, analogous to TerminalPanel for terminals.
@MainActor
final class BrowserPanel: ObservableObject, Identifiable {
    let id: UUID
    let state: BrowserState

    init(id: UUID = UUID(), url: URL? = nil) {
        self.id = id
        self.state = BrowserState()
        if let url {
            state.navigate(to: url)
        }
    }
}
