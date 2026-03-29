import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            codeContent
        }
        .background(Theme.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var header: some View {
        HStack {
            if let lang = language {
                Text(lang)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            Button {
                copyToClipboard()
            } label: {
                Text(copied ? "Copied" : "Copy")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var codeContent: some View {
        let highlighted = SyntaxHighlighter.highlight(code, language: language)
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(highlighted)
                .font(Theme.mono(13))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
