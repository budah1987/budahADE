import SwiftUI

/// Plain text, auto-sizes to content. Lightweight sticky note.
struct StickyNoteView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { canvas.selectedId == elementId }

    var body: some View {
        TileChrome(
            title: "Sticky Note",
            icon: "note.text",
            onClose: onClose
        ) {
            Group {
                if isEditing {
                    TextEditor(text: $content)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .onExitCommand { exitEditing() }
                } else {
                    Text(content.isEmpty ? "Click to type..." : content)
                        .font(.system(size: 14))
                        .foregroundColor(content.isEmpty ? Theme.textMuted : Theme.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture { enterEditing() }
                }
            }
            .padding(8)
        }
        .onChange(of: isSelected) { _, selected in
            if !selected { exitEditing() }
        }
    }

    private func enterEditing() {
        isEditing = true
        // Delay focus to let SwiftUI add the TextEditor to the hierarchy first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }

    private func exitEditing() {
        isEditing = false
        isFocused = false
    }
}
