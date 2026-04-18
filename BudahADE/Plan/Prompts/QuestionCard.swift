import SwiftUI

/// A single free-form question. No counter, no dots — just the question,
/// optional context, suggestion chips (if any), and a text field.
/// Cmd+Enter submits the focused/typed answer.
struct QuestionCard: View {
    let prompt: AgentSession.QueuedPrompt
    let suggestions: [String]
    let namespace: Namespace.ID
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var customText: String = ""
    @State private var selectedSuggestion: String?
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFocused: Bool

    private var currentAnswer: String {
        if !customText.isEmpty { return customText }
        return selectedSuggestion ?? ""
    }
    private var canSubmit: Bool { !currentAnswer.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)
                .matchedGeometryEffect(id: "accent", in: namespace)

            VStack(alignment: .leading, spacing: 8) {
                header

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

                // Question text
                Text(cleanBold(prompt.question))
                    .font(Theme.body(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .matchedGeometryEffect(id: "question-\(prompt.id)", in: namespace)

                // Inline context paragraph (if non-empty)
                if !prompt.context.isEmpty {
                    Text(prompt.context)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Suggestion chips
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            SuggestionChipRow(
                                number: idx + 1,
                                text: suggestion,
                                isSelected: selectedSuggestion == suggestion,
                                onSelect: {
                                    selectedSuggestion = suggestion
                                    customText = ""
                                }
                            )
                            if idx < suggestions.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                }

                // Custom text field
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 20)

                    TextField(suggestions.isEmpty ? "Type your answer..." : "Something else...", text: $customText)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($customFocused)
                        .onChange(of: customText) { _, newValue in
                            if !newValue.isEmpty { selectedSuggestion = nil }
                        }
                        .onSubmit {
                            if canSubmit { submit() }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Action row
                HStack {
                    if !suggestions.isEmpty {
                        Text("1–\(suggestions.count) select")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                        + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
                        + Text("Enter submit")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }

                    Spacer()

                    Button(action: submit) {
                        HStack(spacing: 4) {
                            Text("Submit")
                                .font(Theme.label(12))
                                .foregroundColor(canSubmit ? .black : .black.opacity(0.4))
                            Text("\u{2318}\u{21A9}")
                                .font(Theme.caption(10))
                                .foregroundColor(canSubmit ? .black.opacity(0.45) : .black.opacity(0.25))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canSubmit ? Color(white: 0.92) : Color(white: 0.92).opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Theme.Colors.sidebarBackground)
        .focusable()
        .focused($sheetFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sheetFocused = true
            }
        }
        .onKeyPress(.return) {
            guard !customFocused, canSubmit else { return .ignored }
            submit()
            return .handled
        }
        .onKeyPress(.escape) {
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard !customFocused else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= suggestions.count else { return .ignored }
            withAnimation(.easeOut(duration: 0.1)) {
                selectedSuggestion = suggestions[num - 1]
                customText = ""
            }
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Colors.hoverFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: "dismiss", in: namespace)
        }
    }

    private func submit() {
        let answer = currentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { onSubmit(answer) }
    }

    private func cleanBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
}

// MARK: - Suggestion Chip Row

private struct SuggestionChipRow: View {
    let number: Int
    let text: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false
    private var isHighlighted: Bool { isSelected || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.1)) { onSelect() }
        } label: {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(Theme.label(11))
                    .foregroundColor(isSelected ? .white : Theme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected
                                  ? Theme.Colors.accent
                                  : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.15) : Color.white.opacity(0.06)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isSelected
                                          ? Theme.Colors.accent
                                          : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.3) : Color.white.opacity(0.1)),
                                          lineWidth: 1)
                    )

                Text(text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
