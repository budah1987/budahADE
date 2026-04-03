import SwiftUI

struct SendToMenu: View {
    let onSendToSpec: () -> Void
    let onSendToAgent: (AgentMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Send to Spec
            Button(action: onSendToSpec) {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .medium))
                    Text("Spec")
                        .font(Theme.caption(12))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.Colors.surface)
                .foregroundColor(Theme.Colors.textSecondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Send to each agent
            ForEach(AgentMode.allCases) { mode in
                Button {
                    onSendToAgent(mode)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(mode.dotColor)
                            .frame(width: 6, height: 6)
                        Text(mode.displayName)
                            .font(Theme.caption(12))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.surface)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Colors.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5)
        )
    }
}
