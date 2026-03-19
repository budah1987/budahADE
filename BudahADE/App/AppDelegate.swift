import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Initialize Ghostty on launch
        GhosttyAppManager.shared.initialize()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhosttyAppManager.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
