import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhosttyAppManager.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
