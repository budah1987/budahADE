import SwiftUI

/// Overlay drawer showing the builder agent's terminal output.
/// Slides down from the spec strip, overlays the regular CLI terminals.
struct BuilderDrawerView: View {
    @ObservedObject var panel: TerminalPanel
    @ObservedObject var buildStatus: BuildStatusState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text("Builder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)

                if let task = buildStatus.currentTaskTitle {
                    Text(task)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }

                if let elapsed = buildStatus.elapsed {
                    Text(elapsed)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary.opacity(0.6))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Colors.surface)

            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(height: 0.5)

            // Builder terminal output
            TerminalPanelView(panel: panel)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Theme.Colors.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private var statusColor: Color {
        switch buildStatus.status {
        case .working:   return Theme.Colors.accent
        case .blocked:   return Color(hex: 0xE06C75)
        case .completed: return Theme.Colors.statusDone
        case .idle:      return Theme.Colors.textTertiary
        }
    }
}
