import SwiftUI

/// Multi-line plain text, user-sized. For longer notes that need explicit dimensions.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { canvas.selectedId == elementId }

    var body: some View {
        TileChrome(
            title: "Text Box",
            icon: "text.alignleft",
            onClose: onClose
        ) {
            Group {
                if isEditing {
                    TextEditor(text: $content)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .onExitCommand { exitEditing() }
                } else {
                    Text(content.isEmpty ? "Click to type..." : content)
                        .font(.system(size: 13))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
    }

    private func exitEditing() {
        isEditing = false
        isFocused = false
    }
}
