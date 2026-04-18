// Legacy prompt sheets — still used by BuilderChatView. PlanChatView now uses
// the new structured `PromptDispatcher` pipeline in `Plan/Prompts/`.
// Do not add new consumers. When the Builder migrates, delete this file.

import SwiftUI
import AppKit

// MARK: - Option Buttons Sheet

struct OptionButtonsSheet: View {
    let contextText: String
    let options: [AgentSession.DetectedOption]
    var showApproveAndBuild: Bool = false
    let onSelect: (AgentSession.DetectedOption) -> Void
    let onDismiss: () -> Void
    let onCustomResponse: (String) -> Void
    var onApproveAndBuild: (() -> Void)? = nil

    @State private var customText: String = ""
    @State private var focusedIndex: Int? = nil
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFieldFocused: Bool

    /// Auto-detect: if any option has a description, use detailed layout
    private var isDetailed: Bool {
        options.contains { !$0.description.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent top border
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)

            VStack(alignment: .leading, spacing: 6) {
                // Header: question + dismiss
                sheetHeader

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                    .padding(.bottom, 2)

                // Option rows — compact or detailed
                if isDetailed {
                    detailedOptions
                } else {
                    compactOptions
                }

                // Approve & Build button — shown when spec looks complete
                if showApproveAndBuild {
                    Button {
                        onApproveAndBuild?()
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

                // Custom text field
                customTextField
                    .padding(.top, 4)

                // Keyboard hints footer
                keyboardFooter
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
            if let option = options.first(where: { $0.label == String(num) }) {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(option) }
                return .handled
            }
            let idx = num - 1
            if idx < options.count {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(options[idx]) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet.letters, phases: .down) { press in
            guard !customFieldFocused else { return .ignored }
            let char = String(press.characters).uppercased()
            if let option = options.first(where: { $0.label.uppercased() == char }) {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(option) }
                return .handled
            }
            return .ignored
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

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            Text(cleanContext(contextText))
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

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
        }
        .padding(.bottom, 4)
    }

    // MARK: - Compact Options

    private var compactOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                CompactOptionRow(
                    option: option,
                    isFocused: focusedIndex == idx,
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
                DetailedOptionCard(
                    option: option,
                    isFocused: focusedIndex == idx,
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
            Text("\u{270E}")  // pencil icon
                .font(.system(size: 12))
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

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Text("Skip")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.hoverFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
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
            .joined(separator: "\n")
    }
}

private struct CompactOptionRow: View {
    let option: AgentSession.DetectedOption
    let isFocused: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            HStack(spacing: 10) {
                // Badge
                Text(option.label)
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHighlighted
                                  ? Color(hex: 0xc4785c).opacity(0.15)
                                  : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isHighlighted
                                          ? Color(hex: 0xc4785c).opacity(0.3)
                                          : Color.white.opacity(0.1),
                                          lineWidth: 1)
                    )

                // Option text
                Text(option.text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Arrow indicator
                Text("→")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.accent)
                    .opacity(isHighlighted ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(isFocused ? 0.06 : 0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

private struct DetailedOptionCard: View {
    let option: AgentSession.DetectedOption
    let isFocused: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Header: badge + title + arrow
                HStack(spacing: 10) {
                    Text(option.label)
                        .font(Theme.label(11))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isHighlighted
                                      ? Color(hex: 0xc4785c).opacity(0.15)
                                      : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(isHighlighted
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

                    Text("→")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.accent)
                        .opacity(isHighlighted ? 1 : 0)
                }
                .padding(.bottom, 6)

                // Description + Pros/Cons
                if !option.description.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(parsedDescription.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .plain(let text):
                                Text(text)
                                    .font(Theme.body(12))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .lineLimit(3)
                            case .pros(let text):
                                (Text("Pros: ").font(Theme.label(11)).foregroundColor(Theme.Colors.statusDone)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            case .cons(let text):
                                (Text("Cons: ").font(Theme.label(11)).foregroundColor(Theme.Colors.error)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            }
                        }
                    }
                    .padding(.leading, 32) // past badge width
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

    // MARK: - Description Parsing

    private enum DescriptionLine {
        case plain(String)
        case pros(String)
        case cons(String)
    }

    private var parsedDescription: [DescriptionLine] {
        option.description.components(separatedBy: "\n").compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { return nil }
            if l.lowercased().hasPrefix("pros:") {
                return .pros(String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if l.lowercased().hasPrefix("cons:") {
                return .cons(String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else {
                return .plain(l)
            }
        }
    }
}

// MARK: - Inline Bold Text

/// Parses **bold** markers in a string and renders them as bold Text segments
private struct InlineBoldText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        parsedText
    }

    private var parsedText: Text {
        var result = Text("")
        var remaining = source[source.startIndex..<source.endIndex]

        while let boldStart = remaining.range(of: "**") {
            // Text before the bold marker
            let before = remaining[remaining.startIndex..<boldStart.lowerBound]
            if !before.isEmpty {
                result = result + Text(before)
            }

            // Find closing **
            let afterOpen = boldStart.upperBound
            guard afterOpen < remaining.endIndex,
                  let boldEnd = remaining[afterOpen...].range(of: "**") else {
                // No closing marker — render the rest as plain text
                result = result + Text(remaining[boldStart.lowerBound...])
                return result
            }

            let boldContent = remaining[afterOpen..<boldEnd.lowerBound]
            result = result + Text(boldContent).bold()
            remaining = remaining[boldEnd.upperBound...]
        }

        // Remaining text after last bold
        if !remaining.isEmpty {
            result = result + Text(remaining)
        }

        return result
    }
}

// MARK: - Question Stepper Sheet

struct QuestionStepperSheet: View {
    let questions: [AgentSession.DetectedQuestionItem]
    let onComplete: ([String]) -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String]
    @State private var customText = ""
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFocused: Bool

    init(questions: [AgentSession.DetectedQuestionItem], onComplete: @escaping ([String]) -> Void, onDismiss: @escaping () -> Void) {
        self.questions = questions
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self._answers = State(initialValue: Array(repeating: "", count: questions.count))
    }

    private var current: AgentSession.DetectedQuestionItem { questions[currentIndex] }
    private var isLast: Bool { currentIndex == questions.count - 1 }
    private var canAdvance: Bool { !answers[currentIndex].isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: step counter + dismiss
                HStack {
                    Text("Question \(currentIndex + 1) of \(questions.count)")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.Colors.textTertiary)

                    // Step dots
                    HStack(spacing: 4) {
                        ForEach(0..<questions.count, id: \.self) { i in
                            Circle()
                                .fill(i < currentIndex ? Color(hex: 0x34a853) :
                                      i == currentIndex ? Theme.Colors.accent :
                                      Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 4)

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
                }

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

                // Question text
                Text(cleanBold(current.question))
                    .font(Theme.body(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Context (if any)
                if !current.context.isEmpty {
                    Text(current.context)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Suggestion buttons
                if !current.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(current.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            SuggestionRow(
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

                // Custom text field
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

                // Navigation + keyboard hints
                HStack {
                    if !current.suggestions.isEmpty {
                        Text("1–\(current.suggestions.count) select")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                        + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
                        + Text("Enter next")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
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

                    Button {
                        advance()
                    } label: {
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
            guard !customFocused else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= current.suggestions.count else { return .ignored }
            withAnimation(.easeOut(duration: 0.1)) {
                answers[currentIndex] = current.suggestions[num - 1]
                customText = ""
            }
            return .handled
        }
    }

    private func advance() {
        if isLast {
            withAnimation(.easeOut(duration: 0.15)) { onComplete(answers) }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                customText = ""
                currentIndex += 1
                loadCustomText()
            }
        }
    }

    private func loadCustomText() {
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

private struct SuggestionRow: View {
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
