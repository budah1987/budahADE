import SwiftUI

/// Plain text, auto-sizes to content. Lightweight sticky note.
struct StickyNoteView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TileChrome(
            title: "Sticky Note",
            icon: "note.text",
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
