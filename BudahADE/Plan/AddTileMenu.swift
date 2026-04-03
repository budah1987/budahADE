import SwiftUI

struct AddTileMenu: View {
    let onAddAgent: (AgentMode) -> Void
    let onAddChatAgent: (AgentMode) -> Void
    let onAddStickyNote: () -> Void
    let onAddTextBox: () -> Void   // Creates ElementKind.text (label with style tools)
    let onAddMarkdown: () -> Void
    let onAddBrowser: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var hoveredAgent: AgentMode?
    @State private var hoveredChatAgent: AgentMode?
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
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(agent.description)
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredAgent == agent ? Theme.Colors.hoverFill : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredAgent = hovering ? agent : nil
                }
            }

            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, 4)

            Text("Chat Agents")
                .font(Theme.caption(10))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

            ForEach(AgentMode.allCases) { agent in
                Button {
                    onAddChatAgent(agent)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 10))
                            .foregroundColor(agent.dotColor)
                            .frame(width: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(agent.displayName) Chat")
                                .font(Theme.label(13))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text("Lightweight, no skills")
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredChatAgent == agent ? Theme.Colors.hoverFill : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredChatAgent = hovering ? agent : nil
                }
            }

            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, 4)

            utilityRow(
                icon: "note.text",
                name: "Sticky Note",
                description: "Quick note, auto-sizes",
                key: "sticky"
            ) {
                onAddStickyNote()
                dismiss()
            }

            utilityRow(
                icon: "text.alignleft",
                name: "Text Box",
                description: "Multi-line text, user-sized",
                key: "textbox"
            ) {
                onAddTextBox()
                dismiss()
            }

            utilityRow(
                icon: "doc.text",
                name: "Markdown",
                description: "Section-based document",
                key: "markdown"
            ) {
                onAddMarkdown()
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
        .background(Theme.Colors.surface)
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
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(Theme.label(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(description)
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredUtility == key ? Theme.Colors.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredUtility = hovering ? key : nil
        }
    }
}
