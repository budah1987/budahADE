import SwiftUI

/// Multi-line plain text, user-sized. For longer notes that need explicit dimensions.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TileChrome(
            title: "Text Box",
            icon: "text.alignleft",
            onClose: onClose
        ) {
            TextEditor(text: $content)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)
        }
    }
}
