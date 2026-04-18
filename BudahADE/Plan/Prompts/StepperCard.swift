import SwiftUI

/// A multi-step prompt. Used when the queue has 2+ prompts OR a single prompt
/// of kind `.questionSeries`. Counter and dots only render when there's more
/// than one step — a single step reads as a card, not a quiz.
struct StepperCard: View {
    /// Flattened list of steps — either one per queue item (when queue.count >= 2),
    /// or one per sub-question (for a single `.questionSeries` prompt).
    let steps: [StepperStep]
    let namespace: Namespace.ID
    /// Called when the user finishes all steps.
    let onComplete: ([String]) -> Void
    /// Called when a single-prompt answer is ready (non-series case). Caller can
    /// prefer this path to keep queue drains granular.
    let onAnswerPrompt: ((AgentSession.QueuedPrompt, String) -> Void)?
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String]
    @State private var customText = ""
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFocused: Bool

    init(
        steps: [StepperStep],
        namespace: Namespace.ID,
        onComplete: @escaping ([String]) -> Void,
        onAnswerPrompt: ((AgentSession.QueuedPrompt, String) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.steps = steps
        self.namespace = namespace
        self.onComplete = onComplete
        self.onAnswerPrompt = onAnswerPrompt
        self.onDismiss = onDismiss
        self._answers = State(initialValue: Array(repeating: "", count: steps.count))
    }

    private var showsStepperChrome: Bool { steps.count >= 2 }

    private var current: StepperStep {
        guard !steps.isEmpty else {
            return StepperStep(id: "", question: "", context: "", suggestions: [], sourcePrompt: nil)
        }
        return steps[min(currentIndex, steps.count - 1)]
    }
    private var isLast: Bool { steps.isEmpty || currentIndex == steps.count - 1 }
    private var canAdvance: Bool {
        guard currentIndex < answers.count, !answers[currentIndex].isEmpty else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)
                .matchedGeometryEffect(id: "accent", in: namespace)

            VStack(alignment: .leading, spacing: 8) {
                header

                if showsStepperChrome {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                }

                // Question text
                Text(cleanBold(current.question))
                    .font(Theme.body(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .matchedGeometryEffect(id: "question-\(current.id)", in: namespace)

                if !current.context.isEmpty {
                    Text(current.context)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !current.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(current.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            StepperSuggestionRow(
                                number: idx + 1,
                                text: suggestion,
                                isSelected: answers[currentIndex] == suggestion,
                                onSelect: {
                                    answers[currentIndex] = suggestion
                                    customText = ""
                                }
                            )
                            if idx < current.suggestions.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 20)

                    TextField("Something else...", text: $customText)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($customFocused)
                        .onChange(of: customText) { _, newValue in
                            if !newValue.isEmpty {
                                answers[currentIndex] = newValue
                            }
                        }
                        .onSubmit {
                            if canAdvance { advance() }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

                if !current.suggestions.isEmpty {
                    Text("1–\(current.suggestions.count) select")
                        .font(Theme.label(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                    + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
                    + Text("Enter next")
                        .font(Theme.label(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                HStack {
                    if currentIndex > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                customText = ""
                                currentIndex -= 1
                                loadCustomText()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9))
                                Text("Back")
                                    .font(Theme.body(12))
                            }
                            .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button(action: advance) {
                        HStack(spacing: 4) {
                            Text(isLast ? "Submit" : "Next")
                                .font(Theme.label(12))
                                .foregroundColor(canAdvance ? .black : .black.opacity(0.4))
                            if !isLast {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(canAdvance ? .black : .black.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canAdvance ? Color(white: 0.92) : Color(white: 0.92).opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdvance)
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
            guard !customFocused, canAdvance else { return .ignored }
            advance()
            return .handled
        }
        .onKeyPress(.escape) {
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard !customFocused, currentIndex < answers.count else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= current.suggestions.count else { return .ignored }
            withAnimation(.easeOut(duration: 0.1)) {
                answers[currentIndex] = current.suggestions[num - 1]
                customText = ""
            }
            return .handled
        }
        .onChange(of: steps.count) { _, newCount in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                if newCount > answers.count {
                    answers.append(contentsOf: Array(repeating: "", count: newCount - answers.count))
                } else if newCount < answers.count {
                    answers = Array(answers.prefix(newCount))
                    if currentIndex >= newCount { currentIndex = max(newCount - 1, 0) }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if showsStepperChrome {
                Text("Question \(currentIndex + 1) of \(steps.count)")
                    .font(Theme.label(12))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .contentTransition(.numericText())

                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i < currentIndex ? Color(hex: 0x34a853) :
                                  i == currentIndex ? Theme.Colors.accent :
                                  Color.white.opacity(0.15))
                            .frame(width: 6, height: 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 4)
            }

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

    // MARK: - Advance

    /// Accept the currently focused answer, if one exists. Called by external
    /// Cmd+Enter handlers when the stepper is showing.
    func acceptCurrent() {
        if canAdvance { advance() }
    }

    private func advance() {
        if isLast {
            withAnimation(.easeOut(duration: 0.15)) { onComplete(answers) }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                customText = ""
                currentIndex += 1
                loadCustomText()
            }
        }
    }

    private func loadCustomText() {
        guard currentIndex < answers.count else { return }
        let answer = answers[currentIndex]
        if !answer.isEmpty && !current.suggestions.contains(answer) {
            customText = answer
        } else {
            customText = ""
        }
    }

    private func cleanBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
}

// MARK: - Stepper Step

/// A flattened step shown by `StepperCard`. Wraps either a top-level prompt
/// (queue.count >= 2 case) or a sub-question (questionSeries case).
struct StepperStep: Identifiable, Equatable {
    let id: String
    let question: String
    let context: String
    let suggestions: [String]
    /// The source prompt if this step is a whole queue item (nil for series sub-steps).
    let sourcePrompt: AgentSession.QueuedPrompt?
}

// MARK: - Suggestion Row

private struct StepperSuggestionRow: View {
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
