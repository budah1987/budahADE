import SwiftUI

struct DocumentTileView: View {
    let path: String
    let onClose: () -> Void

    @State private var content: String = ""
    @State private var editorCoordinator: RichTextEditor.Coordinator?

    private var filename: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        TileChrome(
            title: filename,
            icon: "doc.text",
            onClose: onClose
        ) {
            if path.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Formatting toolbar
                    formatToolbar

                    Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                    // Rich text editor
                    RichTextEditor(text: $content, onSave: { save() }) { coordinator in
                        editorCoordinator = coordinator
                    }
                }
            }
        }
        .onAppear { loadContent() }
    }

    // MARK: - Toolbar

    private var formatToolbar: some View {
        HStack(spacing: 2) {
            formatButton("B", weight: .bold) {
                editorCoordinator?.toggleBold()
            }
            formatButton("I", italic: true) {
                editorCoordinator?.toggleItalic()
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surface2)
    }

    private func formatButton(
        _ label: String,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: weight))
                .italic(italic)
                .foregroundColor(Theme.textMuted)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.hoverFill)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Load / Save

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted)
            Text("No document")
                .font(Theme.body(13))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadContent() {
        guard !path.isEmpty else { return }
        content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func save() {
        guard !path.isEmpty else { return }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
