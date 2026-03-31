# Option Sheet Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the option sheet with two auto-switching variants (compact / detailed), full keyboard navigation, and BudahADE dark/terra cotta aesthetic.

**Architecture:** Add `description` field to `DetectedOption` and update `detectOptions()` to collect sub-lines between option headings. Rewrite `OptionButtonsSheet` and `OptionSheetRow` in PlanChatView.swift with new badge/focus/arrow UI, add `DetailedOptionCard` for the rich variant, and wire up ↑↓ keyboard nav with focus tracking.

**Tech Stack:** SwiftUI, NSRegularExpression, existing Theme tokens

---

### Task 1: Add `description` to DetectedOption and update detectOptions()

**Files:**
- Modify: `BudahADE/Agent/AgentSession.swift:342-346` (DetectedOption struct)
- Modify: `BudahADE/Agent/AgentSession.swift:348-460` (detectOptions method)

- [ ] **Step 1: Add `description` field to DetectedOption**

In `AgentSession.swift`, replace the struct at lines 342-346:

```swift
    struct DetectedOption: Identifiable {
        let id: Int
        let label: String
        let text: String
        let description: String  // Sub-lines between headings (pros/cons/description). Empty = compact variant.
    }
```

- [ ] **Step 2: Update all DetectedOption construction sites to include `description: ""`**

In the `detectOptions()` method, every `options.append(DetectedOption(...))` call needs `description: ""` added. There are 5 append sites (lines ~407, ~419, ~429, ~438, ~446). Update each one. For example the first one at ~407:

```swift
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
```

Do the same for all 5 append calls.

- [ ] **Step 3: Collect sub-lines between option headings as descriptions**

Replace the second `for line in lines` loop (lines 396-450) with a two-pass approach that collects description lines when `foundOptionHeadings` is true. The full replacement for the loop:

```swift
        // Indices where option headings appear (for collecting sub-lines)
        var headingIndices: [Int] = []

        for (idx, line) in lines.enumerated() {
            if line.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let match = optionHeadingPattern.firstMatch(in: line, range: range),
               let labelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: "" // filled in next pass
                ))
                headingIndices.append(idx)
            } else if foundOptionHeadings {
                // Skip other patterns when Option headings are the structure
                continue
            } else if let match = numberedPattern.firstMatch(in: line, range: range),
               let labelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if let match = bulletLetteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if let match = letteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if let match = bulletPattern.firstMatch(in: line, range: range),
                      let textRange = Range(match.range(at: 1), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: "\(options.count + 1)",
                    text: rawText,
                    description: ""
                ))
            }
        }

        // Second pass: collect description lines between option headings
        if foundOptionHeadings && !headingIndices.isEmpty {
            for (i, headingIdx) in headingIndices.enumerated() {
                let nextBound = (i + 1 < headingIndices.count) ? headingIndices[i + 1] : lines.count
                var descLines: [String] = []
                for lineIdx in (headingIdx + 1)..<nextBound {
                    let l = lines[lineIdx]
                    guard !l.isEmpty else { continue }
                    // Skip the question line (last non-empty line) — it's not part of a description
                    if l.hasSuffix("?") && lineIdx >= lines.count - 3 { continue }
                    // Clean markdown markers
                    let cleaned = l.replacingOccurrences(of: "**", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty {
                        // Strip leading bullet markers for cleaner display
                        var c = cleaned
                        for prefix in ["- ", "• ", "· ", "‣ ", "› "] {
                            if c.hasPrefix(prefix) { c = String(c.dropFirst(prefix.count)); break }
                        }
                        descLines.append(c)
                    }
                }
                if !descLines.isEmpty && i < options.count {
                    let desc = descLines.joined(separator: "\n")
                    options[i] = DetectedOption(
                        id: options[i].id,
                        label: options[i].label,
                        text: options[i].text,
                        description: desc
                    )
                }
            }
        }
```

- [ ] **Step 4: Remove debug NSLog statements**

Remove or comment out the debug NSLog calls at lines 351, 364, 387, 390-391, 454, 456. These were for debugging the regex issue which is now fixed.

- [ ] **Step 5: Build and verify**

Run:
```bash
cd /Users/amir/Documents/Cursor\ Projects/budahADE && xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```
Expected: Clean build with no errors (warnings about nonisolated are OK).

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Agent/AgentSession.swift
git commit -m "feat: add description field to DetectedOption, collect sub-lines between headings"
```

---

### Task 2: Rewrite OptionButtonsSheet — compact variant with new aesthetic

**Files:**
- Modify: `BudahADE/Plan/PlanChatView.swift:871-992` (OptionButtonsSheet + OptionSheetRow)

- [ ] **Step 1: Replace OptionButtonsSheet with redesigned version**

Replace the entire `OptionButtonsSheet` struct (lines 871-992) with the new implementation. This includes the sheet container, header, option rows, custom text field, keyboard hints footer, and all keyboard navigation:

```swift
private struct OptionButtonsSheet: View {
    let contextText: String
    let options: [AgentSession.DetectedOption]
    let onSelect: (AgentSession.DetectedOption) -> Void
    let onDismiss: () -> Void
    let onCustomResponse: (String) -> Void

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
                .fill(Theme.accent.opacity(0.4))
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

                // Custom text field
                customTextField
                    .padding(.top, 4)

                // Keyboard hints footer
                keyboardFooter
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.sidebar)
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
                .foregroundColor(Theme.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Theme.hoverFill)
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
            Text("\u{270E}")  // pencil icon ✎
                .font(.system(size: 12))
                .foregroundColor(Theme.textMuted)
                .frame(width: 22, height: 22)

            TextField(options.isEmpty ? "Type your answer..." : "Something else...", text: $customText)
                .font(Theme.body(13))
                .foregroundColor(Theme.textPrimary)
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
                .font(Theme.mono(11))
                .foregroundColor(Theme.textMuted)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Enter select")
                .font(Theme.mono(11))
                .foregroundColor(Theme.textMuted)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Esc skip")
                .font(Theme.mono(11))
                .foregroundColor(Theme.textMuted)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Text("Skip")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.hoverFill)
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
```

- [ ] **Step 2: Replace OptionSheetRow with CompactOptionRow**

Replace the `OptionSheetRow` struct (lines 994-1028) with the new `CompactOptionRow` that has badge, arrow indicator, and focus state:

```swift
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
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundColor(Theme.accent)
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
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Arrow indicator
                Text("→")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
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
```

- [ ] **Step 3: Build and verify**

Run:
```bash
cd /Users/amir/Documents/Cursor\ Projects/budahADE && xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```
Expected: Clean build. The `InlineBoldText` struct (lines 1030-1076) should remain untouched.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/PlanChatView.swift
git commit -m "feat: redesign OptionButtonsSheet — badges, focus tracking, keyboard hints, skip button"
```

---

### Task 3: Add DetailedOptionCard for the rich variant

**Files:**
- Modify: `BudahADE/Plan/PlanChatView.swift` (insert new struct after CompactOptionRow)

- [ ] **Step 1: Add DetailedOptionCard struct**

Insert this struct right after the `CompactOptionRow` closing brace, before the `InlineBoldText` struct:

```swift
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
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundColor(Theme.accent)
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
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Text("→")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
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
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(3)
                            case .pros(let text):
                                (Text("Pros: ").font(Theme.label(11)).foregroundColor(Theme.success)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            case .cons(let text):
                                (Text("Cons: ").font(Theme.label(11)).foregroundColor(Theme.error)
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
            .overlay(alignment: .leading) {
                // Left accent border
                RoundedRectangle(cornerRadius: 1)
                    .fill(isFocused ? Theme.accent : (isHovered ? Theme.accent.opacity(0.3) : Color.clear))
                    .frame(width: 2)
            }
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
```

- [ ] **Step 2: Build and verify**

Run:
```bash
cd /Users/amir/Documents/Cursor\ Projects/budahADE && xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```
Expected: Clean build.

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Plan/PlanChatView.swift
git commit -m "feat: add DetailedOptionCard for rich options with descriptions and pros/cons"
```

---

### Task 4: Smoke test — launch app and verify both variants

**Files:**
- No file changes — manual verification

- [ ] **Step 1: Build and launch**

```bash
cd /Users/amir/Documents/Cursor\ Projects/budahADE && xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
open ~/Library/Developer/Xcode/DerivedData/BudahADE-*/Build/Products/Debug/BudahADE.app
```

- [ ] **Step 2: Start log stream in another terminal**

```bash
log stream --process BudahADE --predicate 'eventMessage contains "detectOptions" or eventMessage contains "OptionSheet"'
```

- [ ] **Step 3: Test compact variant**

Ask the plan agent a question that produces simple numbered/lettered options without descriptions (e.g., "Give me 3 names for a CLI tool"). Verify:
- Sheet slides up with accent top border
- Badges are rounded rects with terra cotta labels
- ↑↓ keys move focus with visible highlight
- Arrow (→) appears on focused/hovered row
- Enter selects, Esc dismisses
- Number/letter keys direct-select
- Skip button works
- Keyboard hints show at bottom
- "Something else..." text field works

- [ ] **Step 4: Test detailed variant**

Ask a question that produces "Option N:" headings with Pros/Cons (e.g., "What's the best approach for a login system? Give me 3 options with pros and cons"). Verify:
- Sheet auto-switches to detailed layout
- Each card shows title, description, Pros (green), Cons (red)
- Left accent border appears on focus
- Same keyboard navigation works
- Cards are scrollable if they overflow

- [ ] **Step 5: Commit final cleanup if needed**

If any visual tweaks are needed from testing, fix and commit:
```bash
git add BudahADE/Plan/PlanChatView.swift BudahADE/Agent/AgentSession.swift
git commit -m "fix: option sheet visual tweaks from smoke testing"
```
