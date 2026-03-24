import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?
    /// Set by BudahADEApp so we can save state before Ghostty shuts down
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Initialize Ghostty on launch
        GhosttyAppManager.shared.initialize()

        // Make window transparent for glass effects
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                window.isOpaque = false
                window.backgroundColor = .clear
            }
        }

        // Restore previous session AFTER Ghostty is initialized.
        // Delay slightly to ensure SwiftUI has wired appState via onAppear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let appState = self?.appState, appState.hasNoWorkspaces {
                print("[AppDelegate] Restoring previous session...")
                _ = appState.restoreFromSavedState()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save all state BEFORE Ghostty shutdown destroys surfaces
        appState?.saveAllState()
        GhosttyAppManager.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
