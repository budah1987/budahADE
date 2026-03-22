import SwiftUI

struct AddTileMenu: View {
    let onAddAgent: (AgentMode) -> Void
    let onAddDocument: () -> Void
    let onAddBrowser: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var hoveredAgent: AgentMode?
    @State private var hoveredUtility: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AgentMode.allCases) { agent in
                Button {
                    onAddAgent(agent)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(agent.dotColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.displayName)
                                .font(Theme.label(13))
                                .foregroundColor(Theme.textPrimary)
                            Text(agent.description)
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredAgent == agent ? Theme.hoverFill : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredAgent = hovering ? agent : nil
                }
            }

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, 4)

            utilityRow(
                icon: "doc.text",
                name: "Document",
                description: "Markdown notes",
                key: "doc"
            ) {
                onAddDocument()
                dismiss()
            }

            utilityRow(
                icon: "globe",
                name: "Browser",
                description: "Web reference",
                key: "browser"
            ) {
                onAddBrowser()
                dismiss()
            }
        }
        .padding(8)
        .frame(width: 260)
        .background(Theme.surface2)
    }

    private func utilityRow(
        icon: String,
        name: String,
        description: String,
        key: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.label(13))
                        .foregroundColor(Theme.textPrimary)
                    Text(description)
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredUtility == key ? Theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredUtility = hovering ? key : nil
        }
    }
}
