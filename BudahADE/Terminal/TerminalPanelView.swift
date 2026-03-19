import SwiftUI

/// SwiftUI wrapper for the Ghostty terminal surface.
struct TerminalPanelView: NSViewRepresentable {
    let panel: TerminalPanel

    func makeNSView(context: Context) -> TerminalSurfaceView {
        let view = TerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.terminalSurface = panel.surface
        return view
    }

    func updateNSView(_ nsView: TerminalSurfaceView, context: Context) {
        if nsView.terminalSurface !== panel.surface {
            nsView.terminalSurface = panel.surface
        }
    }
}
