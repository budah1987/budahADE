import SwiftUI

/// A single-choice prompt. Options are listed with optional descriptions,
/// the recommended option carries a subtle accent ring and is the target of
/// Cmd+Enter. Numbered shortcuts (1–9) select instantly. Spec-ready choices
/// surface an additional "Approve & Build" action.
struct ChoiceCard: View {
    let prompt: AgentSession.QueuedPrompt
    let options: [AgentSession.QueuedPrompt.ChoiceOption]
    let recommendedIndex: Int?
    let showApproveAndBuild: Bool
    let namespace: Namespace.ID
    let onSelect: (AgentSession.QueuedPrompt.ChoiceOption) -> Void
    let onCustomResponse: (String) -> Void
    let onApproveAndBuild: () -> Void
    let onDismiss: () -> Void

    @State private var customText: String = ""
    @State private var focusedIndex: Int? = nil
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFieldFocused: Bool

    /// Auto-detect: if any option has a description, use detailed layout.
    private var isDetailed: Bool {
        options.contains { !$0.description.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)
                .matchedGeometryEffect(id: "accent", in: namespace)

            VStack(alignment: .leading, spacing: 6) {
                header

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                    .padding(.bottom, 2)

                if isDetailed {
                    detailedOptions
                } else {
                    compactOptions
                }

                if showApproveAndBuild {
                    Button {
                        onApproveAndBuild()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Approve & Build")
                                .font(Theme.label(13))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.statusWorking)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }

                customTextField
                    .padding(.top, 4)

                keyboardFooter
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Theme.Colors.sidebarBackground)
        .focusable()
        .focused($sheetFocused)
        .onAppear {
            focusedIndex = recommendedIndex
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sheetFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            guard !customFieldFocused else { return .ignored }
            moveFocus(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !customFieldFocused else { return .ignored }
            moveFocus(delta: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !customFieldFocused else { return .ignored }
            if let idx = focusedIndex, idx < options.count {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(options[idx]) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard !customFieldFocused else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= options.count else { return .ignored }
            let idx = num - 1
            withAnimation(.easeOut(duration: 0.15)) { onSelect(options[idx]) }
            return .handled
        }
        .onKeyPress(.tab) {
            if !customFieldFocused {
                customFieldFocused = true
                focusedIndex = nil
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if customFieldFocused {
                customFieldFocused = false
                sheetFocused = true
                return .handled
            }
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                if !prompt.context.isEmpty {
                    Text(cleanContext(prompt.context))
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(2)
                }
                Text(cleanBold(prompt.question))
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .matchedGeometryEffect(id: "question-\(prompt.id)", in: namespace)
            }

            Spacer(minLength: 8)

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
        .padding(.bottom, 4)
    }

    // MARK: - Compact Options

    private var compactOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                ChoiceCompactRow(
                    index: idx,
                    option: option,
                    isFocused: focusedIndex == idx,
                    isRecommended: recommendedIndex == idx,
                    onSelect: { onSelect(option) },
                    onHover: { hovering in
                        if hovering { focusedIndex = idx }
                    }
                )
                if idx < options.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        .padding(.horizontal, 10)
                }
            }
        }
    }

    // MARK: - Detailed Options

    private var detailedOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                ChoiceDetailedCard(
                    index: idx,
                    option: option,
                    isFocused: focusedIndex == idx,
                    isRecommended: recommendedIndex == idx,
                    onSelect: { onSelect(option) },
                    onHover: { hovering in
                        if hovering { focusedIndex = idx }
                    }
                )
                if idx < options.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Custom Text Field

    private var customTextField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 22, height: 22)

            TextField(options.isEmpty ? "Type your answer..." : "Something else...", text: $customText)
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .focused($customFieldFocused)
                .onSubmit {
                    let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCustomResponse(trimmed)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Keyboard Footer

    private var keyboardFooter: some View {
        HStack {
            Text("↑↓ navigate")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Enter select")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Esc skip")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer()
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Focus Navigation

    private func moveFocus(delta: Int) {
        guard !options.isEmpty else { return }
        if let current = focusedIndex {
            focusedIndex = (current + delta + options.count) % options.count
        } else {
            focusedIndex = delta > 0 ? 0 : options.count - 1
        }
    }

    // MARK: - Helpers

    private func cleanBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }

    private func cleanContext(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .components(separatedBy: "\n")
            .map { line in
                var l = line
                if l.hasPrefix("• ") { l = String(l.dropFirst(2)) }
                if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
                return l
            }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Compact Row

private struct ChoiceCompactRow: View {
    let index: Int
    let option: AgentSession.QueuedPrompt.ChoiceOption
    let isFocused: Bool
    var isRecommended: Bool = false
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHighlighted || isRecommended
                                  ? Color(hex: 0xc4785c).opacity(0.15)
                                  : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isHighlighted || isRecommended
                                          ? Color(hex: 0xc4785c).opacity(0.3)
                                          : Color.white.opacity(0.1),
                                          lineWidth: 1)
                    )

                Text(option.text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isRecommended {
                    Text("\u{2318}\u{21A9}")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.trailing, 2)
                }

                Text("→")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.accent)
                    .opacity(isHighlighted || isRecommended ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(isFocused ? 0.06 : 0.04) :
                          isRecommended ? Color.white.opacity(0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

// MARK: - Detailed Card

private struct ChoiceDetailedCard: View {
    let index: Int
    let option: AgentSession.QueuedPrompt.ChoiceOption
    let isFocused: Bool
    var isRecommended: Bool = false
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(Theme.label(11))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isHighlighted || isRecommended
                                      ? Color(hex: 0xc4785c).opacity(0.15)
                                      : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(isHighlighted || isRecommended
                                              ? Color(hex: 0xc4785c).opacity(0.3)
                                              : Color.white.opacity(0.1),
                                              lineWidth: 1)
                        )

                    Text(option.text)
                        .font(Theme.label(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if isRecommended {
                        Text("\u{2318}\u{21A9}")
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.trailing, 2)
                    }

                    Text("→")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.accent)
                        .opacity(isHighlighted || isRecommended ? 1 : 0)
                }
                .padding(.bottom, 6)

                if !option.description.isEmpty {
                    Text(option.description)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(3)
                        .padding(.leading, 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(isFocused ? 0.04 : 0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}
