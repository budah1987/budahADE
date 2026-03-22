import SwiftUI

struct TerminalTileView: View {
    let panel: TerminalPanel
    let agent: AgentMode
    let onClose: () -> Void

    var body: some View {
        TileChrome(
            title: agent.displayName,
            icon: agent.iconName,
            dotColor: agent.dotColor,
            onClose: onClose
        ) {
            TerminalPanelView(panel: panel)
        }
    }
}
