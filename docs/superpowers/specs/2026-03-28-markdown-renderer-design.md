# Plan Chat Markdown Renderer + Code Blocks

**Date:** 2026-03-28
**Branch:** `emdash/planning-conversation-enhanement-4f8`
**Scope:** Rich markdown rendering in Plan mode assistant messages, syntax-highlighted code blocks, and Build/Edit action buttons for spec output.

## Problem

Plan mode's assistant messages render as plain `Text(message.content)` — no headers, no bold/italic, no code blocks, no lists, no tables. This makes Claude's responses hard to scan and impossible to copy code from effectively. The gap between BudahADE's Plan mode and Claude Desktop's rendering quality is the single biggest UX blocker.

## Goals

1. Render Claude's markdown responses with full formatting fidelity
2. Code blocks with syntax highlighting, language labels, and copy functionality
3. Hybrid streaming — show completed markdown blocks as rich content while the response is still streaming
4. Build/Edit buttons appear when a spec or plan is detected in the output, enabling the Plan→Build handoff

## Non-Goals

- Block quotes (deferred — rare in Claude CLI output)
- Images within markdown (deferred)
- Task list checkboxes (deferred — handled by SpecParser separately)
- Footnotes (deferred)
- Auto-detection of code language when no fence tag is present
- Full builder agent implementation (buttons are stubbed for now)

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `BudahADE/Plan/MarkdownRenderer.swift` | Main view — parses markdown string into `[MarkdownBlock]` via swift-markdown AST walker, renders as SwiftUI views |
| `BudahADE/Plan/CodeBlockView.swift` | Interactive code block — language label, copy button, syntax-highlighted code |
| `BudahADE/Plan/SyntaxHighlighter.swift` | Regex-based tokenizer — maps language keywords/patterns to Theme colors |

### Modified Files

| File | Change |
|------|--------|
| `PlanChatView.swift` | Replace `Text(message.content)` with `MarkdownRenderer` in assistant bubble and streaming bubble. Remove `surface2` background from assistant messages (direct flow layout). Add Build/Edit buttons. |
| `project.yml` | Add `swift-markdown` SPM dependency |

### Unchanged

ChatMessage, AgentSession, PlanChatState, Theme — all existing infrastructure is sufficient.

### Data Flow

```
String → Document(parsing:) → MarkupWalker → [MarkdownBlock] → ForEach → SwiftUI views
```

The walker produces an array of `MarkdownBlock` values rather than directly emitting views. This keeps the walker pure and testable.

---

## Intermediate Representation

### MarkdownBlock

```swift
enum MarkdownBlock: Identifiable {
    case heading(level: Int, inlines: [InlineNode])
    case paragraph(inlines: [InlineNode])
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [ListItem])
    case orderedList(start: Int, items: [ListItem])
    case table(headers: [InlineNode], rows: [[InlineNode]], alignments: [TableAlignment?])
    case thematicBreak
}

struct ListItem {
    let content: [InlineNode]
    let children: [MarkdownBlock]  // nested lists
}

enum TableAlignment {
    case left, center, right
}
```

### InlineNode

```swift
enum InlineNode {
    case text(String)
    case code(String)
    case emphasis([InlineNode])
    case strong([InlineNode])
    case link(destination: String, children: [InlineNode])
    case lineBreak
}
```

Inline nodes flatten into a single `Text` view using SwiftUI's `Text` concatenation (`+` operator) for proper line wrapping across mixed bold/italic/code spans.

---

## Rendering Specifications

### Typography & Spacing

| Element | Font | Color | Spacing |
|---------|------|-------|---------|
| H1 | `Theme.headline(22)` | `textPrimary` | 20pt above, 8pt below |
| H2 | `Theme.headline(18)` | `textPrimary` | 16pt above, 6pt below |
| H3 | `Theme.label(15)` | `textPrimary` | 12pt above, 4pt below |
| Paragraph | `Theme.body(14)` | `textPrimary` | 8pt below |
| Inline code | `Theme.mono(13)` | `textPrimary` | `rgba(255,255,255,0.08)` bg, 4px radius |
| Bold | `.bold` weight | `white` (full) | — |
| Italic | `.italic` | `textSecondary` | — |
| Link | `Theme.body(14)` | `accent` | underline on hover |
| Bullet list | `Theme.body(14)` | `textPrimary` | `•` prefix, 20pt left indent, 4pt between items |
| Numbered list | `Theme.body(14)` | `textPrimary` | `1.` prefix, 20pt left indent, 4pt between items |
| HR | — | `borderSubtle` | 1px line, 12pt vertical margin |

### Message Layout

**Assistant messages** use direct flow — no wrapping bubble. Markdown content renders directly on `contentBg` (#141416). Code blocks stand out via their own darker background. This matches Claude Desktop / ChatGPT's approach.

**User messages** keep their existing bubble style (dark warm background, right-aligned).

**Streaming bubble** also uses `MarkdownRenderer` with `isStreaming: true` — no bubble wrapper.

---

## Code Block Component

### Visual Design (Option A — Minimal Header)

- **Container**: `sidebar` (#1a1a1e) background, 8px corner radius, no outer border. Full bleed within message flow.
- **Header bar**: `rgba(255,255,255,0.04)` background, 1px bottom border (`rgba(255,255,255,0.06)`).
  - Left: language label in `Theme.mono(11)` / `textMuted`
  - Right: "Copy" button in `Theme.mono(11)` / `textMuted`. On click → "Copied" for 2 seconds, then reverts.
- **Code area**: `Theme.mono(13)`, `textPrimary`, 12px vertical + 14px horizontal padding. Text selection enabled via `textSelection(.enabled)`.

### Syntax Highlighting

Regex-based tokenizer. Returns `AttributedString` with color attributes.

**Token types and Theme colors:**

| Token | Color | Pattern |
|-------|-------|---------|
| Keyword | `accent` (#c4785c) | Language-specific word list |
| Type/Function | `info` (#6b8fb5) | Word after keyword, PascalCase identifiers |
| String | `success` (#5a9a6b) | `"..."`, `'...'`, template literals |
| Number | `warning` (#c4a85c) | Integer/float literals |
| Comment | `textMuted` (#555) | `//`, `/* */`, `#` (language-dependent) |
| Plain | `textPrimary` (#e5e5e5) | Everything else |

**Supported languages** (keyword lists): Swift, Python, JavaScript/TypeScript, Rust, Go, Bash, JSON, YAML, SQL, HTML/CSS.

**Unknown languages**: Comment + string + number highlighting only (no keywords). No auto-detection — uses the language tag from the code fence.

---

## Hybrid Streaming

`MarkdownRenderer` accepts an `isStreaming: Bool` parameter.

### When `isStreaming == true`:

1. **Find the stable boundary** — the last double newline (`\n\n`) that is NOT inside an open code fence.
2. **Detect open code fences** — scan for `` ``` `` lines; odd count means the last fence is unclosed.
3. **Stable prefix** (everything before the boundary) → parse with swift-markdown → render as rich markdown blocks.
4. **Unstable tail** (everything after) → render as plain `Text` with `Theme.body(14)`.

### When `isStreaming == false`:

Parse and render everything as rich markdown.

### Edge Cases

- **Unclosed code fence** → entire unclosed fence block stays in the plain text tail. No partial code block rendering.
- **Empty stable prefix** → entire content renders as plain text until the first block completes.
- **Single newline mid-paragraph** → stays in tail until double newline closes it.

---

## Tables

Rendered with SwiftUI `Grid`:

- **Header row**: `Theme.label(13)`, `textSecondary`, bottom border using `borderSubtle`
- **Data rows**: `Theme.body(13)`, `textPrimary`, alternating background (clear / `rgba(255,255,255,0.02)`)
- **Cell padding**: 8px horizontal, 6px vertical
- **Column alignment**: respected from markdown pipe table syntax (`:--`, `:-:`, `--:`)
- **Overflow**: horizontal `ScrollView` if table exceeds message width
- **Cell content**: supports inline markdown (bold, code, links) since cells contain `[InlineNode]`

---

## Build/Edit Action Buttons

### Detection

After an assistant message is finalized (streaming complete, message appended to `messages[]`), scan the content for spec/plan indicators:

- Contains a markdown heading with keywords: "spec", "plan", "implementation plan", "design", "architecture"
- AND contains at least one list (ordered or unordered) suggesting actionable items

This is a heuristic, not a parser — false negatives are acceptable, false positives are not. If uncertain, don't show buttons.

### UI

When detected, show a button row below the assistant message:

- **Build** button: Filled style, accent color background, white text. Label: "Build" with a hammer icon (`hammer.fill`).
- **Edit** button: Ghost style, `borderSubtle` border, `textSecondary` text. Label: "Edit" with a pencil icon (`pencil`).
- Layout: right-aligned `HStack`, 8px gap between buttons, 8pt top margin from message content.

### Behavior

- **Build**: For now, stores the message content on `PlanChatState` as `pendingSpec: String?` and prints a log message. This will be wired to the builder agent / Build mode in a future spec.
- **Edit**: Opens the spec content in a modal text editor (a `TextEditor` sheet) where the user can revise before building. On save, updates the stored spec content. On cancel, dismisses.

---

## Dependency

### swift-markdown (Apple)

- **Package**: `https://github.com/swiftlang/swift-markdown.git`
- **Version**: from `0.5.0`
- **Target**: `Markdown`
- **Added to**: `project.yml` under SPM dependencies, linked to the BudahADE target
