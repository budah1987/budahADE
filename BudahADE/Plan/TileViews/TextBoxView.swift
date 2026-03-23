import SwiftUI

/// Single-line headline/label tile. Auto-width to text content. Enter exits edit mode.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @State private var isEditing: Bool = true  // Start in edit mode
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
                    .fixedSize()
                    .frame(minWidth: 80)
            } else {
                Text(content.isEmpty ? "Label" : content)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(content.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 80)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEditing() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            // Auto-focus when first created
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onChange(of: isSelected) { _, selected in
            if !selected { exitEditing() }
        }
        .onChange(of: content) { _, newValue in
            updateElementSize(for: newValue)
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                updateElementSize(for: content)
            }
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
        if content.isEmpty { content = "Label" }
        updateElementSize(for: content)
    }

    /// Measure text and resize the canvas element to fit
    private func updateElementSize(for text: String) {
        let displayText = text.isEmpty ? "Type label..." : text
        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        let width = max(ceil(textSize.width) + 32, 80)  // +padding
        let height = ceil(textSize.height) + 24           // +padding
        canvas.resizeElement(elementId, to: CGSize(width: width, height: height))
    }
}
