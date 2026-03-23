import SwiftUI

/// Single-line headline/label tile. Auto-width to text content. Enter exits edit mode.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = "Label"
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { canvas.selectedId == elementId }

    var body: some View {
        Group {
            if isEditing {
                TextField("Type label...", text: $content)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isFocused)
                    .onSubmit { exitEditing() }
                    .onExitCommand { exitEditing() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Text(content.isEmpty ? "Label" : content)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(content.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEditing() }
            }
        }
        .background(Theme.contentBg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
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
