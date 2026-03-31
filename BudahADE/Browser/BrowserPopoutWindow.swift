import AppKit
import SwiftUI

// MARK: - Browser Popout Window

/// Manages an NSPanel that hosts a BrowserPanelView in a separate window.
/// The same BrowserState is shared — no WKWebView recreation.
@MainActor
final class BrowserPopoutWindow {
    private var panel: NSPanel?
    private let state: BrowserState

    init(state: BrowserState) {
        self.state = state
    }

    var isOpen: Bool { panel != nil }

    func open() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = BrowserPanelView(state: state, onPopOut: nil)
            .frame(minWidth: 480, minHeight: 320)

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = state.title ?? "Browser"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.center()
        window.isReleasedWhenClosed = false

        // Watch for window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.panel = nil
        }

        window.makeKeyAndOrderFront(nil)
        self.panel = window
    }

    func close() {
        panel?.close()
        panel = nil
    }
}
