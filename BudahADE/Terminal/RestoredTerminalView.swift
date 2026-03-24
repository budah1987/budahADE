import SwiftUI

/// Wraps TerminalPanelView with an optional scrollback snapshot from a previous session.
/// When `panel.restoredScrollback` is non-nil, renders a read-only faded view of the
/// previous session output above the live terminal, separated by a "Session resumed" divider.
struct RestoredTerminalView: View {
    @ObservedObject var panel: TerminalPanel

    var body: some View {
        VStack(spacing: 0) {
            if panel.restoredScrollback != nil {
                // Previous session scrollback (read-only, faded)
                ScrollView {
                    Text(panel.restoredScrollback ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .background(Color(hex: 0x141416))

                // "Session resumed" divider with dismiss button
                HStack(spacing: 8) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 0.5)
                    Text("Session resumed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                        .fixedSize()
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 0.5)

                    Button {
                        panel.restoredScrollback = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(hex: 0x141416))
            }

            TerminalPanelView(panel: panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
