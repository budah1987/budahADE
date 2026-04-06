import SwiftUI

struct EditableMarkdownRenderer: View {
    @Binding var content: String
    let onDone: () -> Void

    @State private var editingBlockId: Int?
    @State private var editText: String = ""
    @State private var hoveredBlockId: Int?
    @State private var cachedBlocks: [MarkdownBlockItem] = []
    @State private var cachedContentHash: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(cachedBlocks) { block in
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
        .onAppear { reparse() }
        .onChange(of: content) { _, _ in reparse() }
    }

    private func reparse() {
        let hash = content.hashValue
        guard hash != cachedContentHash else { return }
        cachedContentHash = hash
        cachedBlocks = MarkdownParser.parse(content)
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
        guard let block = cachedBlocks.first(where: { $0.id == blockId }) else { return }

        if let range = content.range(of: block.sourceText) {
            content.replaceSubrange(range, with: editText)
        }

        editingBlockId = nil
        editText = ""
    }
}
