import Foundation
import AppKit
import Combine

/// High-level terminal API wrapping TerminalSurface.
@MainActor
final class TerminalPanel: ObservableObject, Identifiable {
    let id: UUID
    let surface: TerminalSurface
    @Published var title: String = "Terminal"
    @Published var isActive: Bool = false
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

    func sendText(_ text: String) { surface.sendText(text) }
    func sendCommand(_ text: String) { surface.sendCommand(text) }
    func sendEnter() { surface.sendEnter() }
    func sendKeyEvent(_ event: NSEvent) { surface.sendKeyEvent(event) }
    func focus() { surface.setFocus(true) }
    func unfocus() { surface.setFocus(false) }
    func close() { surface.requestClose() }
}
