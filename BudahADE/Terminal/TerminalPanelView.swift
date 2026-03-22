import SwiftUI

/// SwiftUI wrapper for the Ghostty terminal surface.
/// Reuses the persistent NSView from TerminalPanel so reparenting
/// (e.g. dragging into a frame) doesn't destroy the Ghostty Metal surface.
struct TerminalPanelView: NSViewRepresentable {
    let panel: TerminalPanel

    func makeNSView(context: Context) -> TerminalSurfaceView {
        panel.surfaceView
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        if nsView.terminalSurface !== panel.surface {
            nsView.terminalSurface = panel.surface
        }
    }
}
