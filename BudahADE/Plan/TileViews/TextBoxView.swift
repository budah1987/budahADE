import SwiftUI

/// Single-line headline/label tile. Auto-width to text content. Enter exits edit mode.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @State private var isEditing: Bool = true  // Start in edit mode
    @FocusState private var isFocused: Bool

    private static let labelFont = NSFont.systemFont(ofSize: 16, weight: .semibold)
    private static let labelHeight: CGFloat = 40  // Fixed height — single line
    private static let hPad: CGFloat = 16
    private static let minWidth: CGFloat = 80

    private var isSelected: Bool { canvas.selectedId == elementId }

    var body: some View {
        Group {
            if isEditing {
                TextField("Label", text: $content)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isFocused)
                    .onSubmit { exitEditing() }
                    .onExitCommand { exitEditing() }
            } else {
                Text(content.isEmpty ? "Label" : content)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(content.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { enterEditing() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Self.hPad)
        .onAppear {
            // Auto-focus after SwiftUI settles the view hierarchy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
        .onChange(of: isSelected) { _, selected in
            if !selected { exitEditing() }
        }
        .onChange(of: content) { _, _ in
            updateWidth()
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
        updateWidth()
    }

    /// Measure text and resize the canvas element width to fit. Height is fixed.
    private func updateWidth() {
        let displayText = content.isEmpty ? "Label" : content
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.labelFont]
        let textWidth = ceil((displayText as NSString).size(withAttributes: attrs).width)
        let width = max(textWidth + Self.hPad * 2, Self.minWidth)
        canvas.resizeElement(elementId, to: CGSize(width: width, height: Self.labelHeight))
    }
}
