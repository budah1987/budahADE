import Foundation
import AppKit
import Combine

/// High-level terminal API wrapping TerminalSurface.
@MainActor
final class TerminalPanel: ObservableObject, Identifiable {
    let id: UUID
    let surface: TerminalSurface
    /// Persistent NSView — reused across SwiftUI view identity changes (e.g. reparenting into frames)
    lazy var surfaceView: TerminalSurfaceView = {
        let view = TerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.terminalSurface = surface
        return view
    }()
    @Published var title: String = "Terminal"
    @Published var isActive: Bool = false
    /// Scrollback text from previous session (displayed as read-only snapshot above terminal)
    @Published var restoredScrollback: String?
    private var cancellables = Set<AnyCancellable>()

    init(workingDirectory: String? = nil) {
        let surface = TerminalSurface(workingDirectory: workingDirectory)
        self.surface = surface
        self.id = surface.id

        // Listen for title changes
        NotificationCenter.default.publisher(for: .terminalTitleChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let info = notification.userInfo,
                      let surfaceId = info["surfaceId"] as? UUID,
                      surfaceId == self.id,
                      let title = info["title"] as? String else { return }
                self.title = title
            }
            .store(in: &cancellables)
    }

    /// Whether the Ghostty surface is ready to receive input.
    var isSurfaceReady: Bool { surface.surface != nil }

    func sendText(_ text: String) { surface.sendText(text) }
    func sendCommand(_ text: String) { surface.sendCommand(text) }
    func sendEnter() { surface.sendEnter() }
    func sendKeyEvent(_ event: NSEvent) { surface.sendKeyEvent(event) }
    func focus() { surface.setFocus(true) }
    func unfocus() { surface.setFocus(false) }
    func close() { surface.requestClose() }

    /// Send a command, retrying until the surface is ready (up to ~5 seconds).
    func sendCommandWhenReady(_ text: String, retryCount: Int = 0) {
        if isSurfaceReady {
            sendCommand(text)
            return
        }
        if retryCount >= 20 { // 20 × 0.25s = 5s max
            print("[TerminalPanel] Surface never became ready, dropping command: \(text.prefix(60))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.sendCommandWhenReady(text, retryCount: retryCount + 1)
        }
    }

    /// Capture current terminal scrollback text. Returns nil if unavailable.
    func readScrollback() -> String? {
        guard let ghosttySurface = surface.surface else { return nil }
        return ScrollbackCapture.readAll(from: ghosttySurface)
    }
}
