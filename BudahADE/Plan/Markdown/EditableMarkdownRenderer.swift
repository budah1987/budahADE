import SwiftUI

struct EditableMarkdownRenderer: View {
    @Binding var content: String
    let onDone: () -> Void

    @State private var editingBlockId: UUID?
    @State private var editText: String = ""
    @State private var hoveredBlockId: UUID?

    var body: some View {
        let blocks = MarkdownParser.parse(content)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                if block.id == editingBlockId {
                    editableBlock(block: block)
                } else {
                    renderableBlock(block: block)
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    commitEdit()
                    onDone()
                }
                .font(Theme.label(12))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func renderableBlock(block: MarkdownBlockItem) -> some View {
        MarkdownRenderer(block.sourceText)
            .padding(4)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        hoveredBlockId == block.id ? Theme.Colors.borderSubtle : Color.clear,
                        lineWidth: 1
                    )
            )
            .background(
                hoveredBlockId == block.id ? Theme.Colors.hoverFill : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                hoveredBlockId = hovering ? block.id : nil
                if hovering {
                    NSCursor.iBeam.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                commitEdit()
                editingBlockId = block.id
                editText = block.sourceText
            }
    }

    @ViewBuilder
    private func editableBlock(block: MarkdownBlockItem) -> some View {
        TextEditor(text: $editText)
            .font(Theme.code(13))
            .foregroundColor(Theme.Colors.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60)
            .padding(8)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Colors.borderActive, lineWidth: 1)
            )
    }

    private func commitEdit() {
        guard let blockId = editingBlockId else { return }
        let blocks = MarkdownParser.parse(content)
        guard let block = blocks.first(where: { $0.id == blockId }) else { return }

        if let range = content.range(of: block.sourceText) {
            content.replaceSubrange(range, with: editText)
        }

        editingBlockId = nil
        editText = ""
    }
}
