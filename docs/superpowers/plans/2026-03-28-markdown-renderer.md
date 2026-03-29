# Markdown Renderer + Code Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace plain `Text()` in Plan mode assistant messages with a rich markdown renderer featuring syntax-highlighted code blocks, tables, and Build/Edit action buttons.

**Architecture:** `swift-markdown` parses content into an AST. A `MarkupWalker` converts the AST into `[MarkdownBlock]` intermediate representation. SwiftUI views render each block type. A regex-based `SyntaxHighlighter` colorizes code blocks using existing Theme tokens. Hybrid streaming splits content at stable block boundaries — completed blocks render rich, the trailing incomplete text renders plain.

**Tech Stack:** swift-markdown (Apple SPM), SwiftUI, XCTest

**Spec:** `docs/superpowers/specs/2026-03-28-markdown-renderer-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| **Create:** `BudahADE/Plan/Markdown/MarkdownRenderer.swift` | Main SwiftUI view — accepts markdown string + isStreaming flag, parses via swift-markdown, renders `[MarkdownBlock]` as SwiftUI views. Contains `MarkdownBlock`, `InlineNode`, `ListItem` types and the `MarkupWalker` subclass. |
| **Create:** `BudahADE/Plan/Markdown/CodeBlockView.swift` | Interactive code block component — language label, copy button, syntax-highlighted code display. |
| **Create:** `BudahADE/Plan/Markdown/SyntaxHighlighter.swift` | Regex-based tokenizer — takes code string + language, returns `AttributedString` with color attributes mapped to Theme tokens. |
| **Create:** `BudahADE/Plan/Markdown/MarkdownTableView.swift` | Table rendering — SwiftUI `Grid` with headers, alignment, alternating rows, horizontal scroll overflow. |
| **Modify:** `BudahADE/Plan/PlanChatView.swift` | Replace `Text(message.content)` with `MarkdownRenderer` in assistant bubbles and streaming bubble. Remove surface2 background for assistant messages. Add Build/Edit buttons. Add inline block editing support. |
| **Modify:** `BudahADE/Plan/PlanChatState.swift` | Add `pendingSpec`, `editingMessageId`, `editingBlockIndex` published properties for Build/Edit state. |
| **Modify:** `project.yml` | Add swift-markdown SPM dependency. |
| **Create:** `BudahADETests/MarkdownRendererTests.swift` | Tests for markdown parsing, block extraction, streaming boundary detection. |
| **Create:** `BudahADETests/SyntaxHighlighterTests.swift` | Tests for syntax highlighting token extraction. |

---

### Task 1: Add swift-markdown SPM Dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add swift-markdown package to project.yml**

Add the SPM package and link it to the BudahADE target. In XcodeGen, packages go at the project root level and dependencies reference them by package name.

```yaml
# Add at the top level of project.yml (same level as 'name', 'options', 'targets'):
packages:
  swift-markdown:
    url: https://github.com/swiftlang/swift-markdown.git
    from: "0.5.0"
```

Then update the target's `dependencies` array:

```yaml
# In targets.BudahADE, change:
    dependencies: []
# To:
    dependencies:
      - package: swift-markdown
        product: Markdown
```

- [ ] **Step 2: Also add Markdown to the test target**

In the `BudahADETests` target section of `project.yml`, add the same dependency so tests can import Markdown:

```yaml
# In targets.BudahADETests.dependencies, add:
      - package: swift-markdown
        product: Markdown
```

- [ ] **Step 3: Regenerate Xcode project and verify**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
```

Expected: "Generated project BudahADE.xcodeproj" with no errors.

Then verify swift-markdown resolves:

```bash
xcodebuild -resolvePackageDependencies -project BudahADE.xcodeproj -scheme BudahADE
```

Expected: Package resolution succeeds, swift-markdown downloaded.

- [ ] **Step 4: Verify build still succeeds**

Run:
```bash
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "chore: add swift-markdown SPM dependency"
```

---

### Task 2: Markdown Data Model + Parser

**Files:**
- Create: `BudahADE/Plan/Markdown/MarkdownRenderer.swift`
- Create: `BudahADETests/MarkdownRendererTests.swift`

- [ ] **Step 1: Write failing tests for MarkdownBlock parsing**

Create `BudahADETests/MarkdownRendererTests.swift`:

```swift
import XCTest
@testable import BudahADE

final class MarkdownRendererTests: XCTestCase {

    // MARK: - Block Parsing

    func testParseHeading() {
        let blocks = MarkdownParser.parse("# Hello World")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let inlines) = blocks[0].kind else {
            return XCTFail("Expected heading block")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(inlines.plainText, "Hello World")
    }

    func testParseMultipleHeadingLevels() {
        let md = """
        # H1
        ## H2
        ### H3
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        guard case .heading(let l1, _) = blocks[0].kind else { return XCTFail("Expected h1") }
        guard case .heading(let l2, _) = blocks[1].kind else { return XCTFail("Expected h2") }
        guard case .heading(let l3, _) = blocks[2].kind else { return XCTFail("Expected h3") }
        XCTAssertEqual(l1, 1)
        XCTAssertEqual(l2, 2)
        XCTAssertEqual(l3, 3)
    }

    func testParseParagraph() {
        let blocks = MarkdownParser.parse("Hello world, this is a paragraph.")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let inlines) = blocks[0].kind else {
            return XCTFail("Expected paragraph block")
        }
        XCTAssertEqual(inlines.plainText, "Hello world, this is a paragraph.")
    }

    func testParseCodeBlock() {
        let md = """
        ```swift
        func hello() {
            print("hi")
        }
        ```
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let lang, let code) = blocks[0].kind else {
            return XCTFail("Expected code block")
        }
        XCTAssertEqual(lang, "swift")
        XCTAssertTrue(code.contains("func hello()"))
    }

    func testParseCodeBlockNoLanguage() {
        let md = """
        ```
        some code
        ```
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let lang, _) = blocks[0].kind else {
            return XCTFail("Expected code block")
        }
        XCTAssertNil(lang)
    }

    func testParseUnorderedList() {
        let md = """
        - Item one
        - Item two
        - Item three
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .unorderedList(let items) = blocks[0].kind else {
            return XCTFail("Expected unordered list")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].content.plainText, "Item one")
    }

    func testParseOrderedList() {
        let md = """
        1. First
        2. Second
        3. Third
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .orderedList(let start, let items) = blocks[0].kind else {
            return XCTFail("Expected ordered list")
        }
        XCTAssertEqual(start, 1)
        XCTAssertEqual(items.count, 3)
    }

    func testParseThematicBreak() {
        let md = """
        Some text

        ---

        More text
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 3)
        guard case .thematicBreak = blocks[1].kind else {
            return XCTFail("Expected thematic break")
        }
    }

    func testParseTable() {
        let md = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let headers, let rows, _) = blocks[0].kind else {
            return XCTFail("Expected table")
        }
        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(headers[0].plainText, "Name")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0][0].plainText, "Alice")
    }

    // MARK: - Inline Parsing

    func testParseBoldInline() {
        let blocks = MarkdownParser.parse("This is **bold** text.")
        guard case .paragraph(let inlines) = blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .strong = $0 { return true }
            return false
        }))
    }

    func testParseItalicInline() {
        let blocks = MarkdownParser.parse("This is *italic* text.")
        guard case .paragraph(let inlines) = blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .emphasis = $0 { return true }
            return false
        }))
    }

    func testParseInlineCode() {
        let blocks = MarkdownParser.parse("Use `someFunction()` here.")
        guard case .paragraph(let inlines) = blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .code(let text) = $0 { return text == "someFunction()" }
            return false
        }))
    }

    func testParseLink() {
        let blocks = MarkdownParser.parse("Visit [Apple](https://apple.com) for more.")
        guard case .paragraph(let inlines) = blocks[0].kind else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .link(let dest, _) = $0 { return dest == "https://apple.com" }
            return false
        }))
    }

    // MARK: - Mixed Content

    func testParseMixedContent() {
        let md = """
        # Title

        A paragraph with **bold** and `code`.

        ```python
        print("hello")
        ```

        - Item 1
        - Item 2
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 4) // heading, paragraph, codeBlock, list
        guard case .heading = blocks[0].kind else { return XCTFail("Expected heading") }
        guard case .paragraph = blocks[1].kind else { return XCTFail("Expected paragraph") }
        guard case .codeBlock = blocks[2].kind else { return XCTFail("Expected code block") }
        guard case .unorderedList = blocks[3].kind else { return XCTFail("Expected list") }
    }

    // MARK: - Source Ranges

    func testBlocksHaveSourceRanges() {
        let md = "# Title\n\nParagraph text"
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 2)
        // Each block should have a valid source range
        for block in blocks {
            XCTAssertFalse(block.sourceText.isEmpty)
        }
    }

    // MARK: - Streaming Boundary

    func testStableBoundarySplitsAtDoubleNewline() {
        let md = "# Title\n\nParagraph\n\nIncomplete"
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(md)
        XCTAssertTrue(stable.contains("# Title"))
        XCTAssertTrue(stable.contains("Paragraph"))
        XCTAssertEqual(tail, "Incomplete")
    }

    func testStableBoundaryRespectsOpenCodeFence() {
        let md = "# Title\n\n```swift\nfunc hello() {\n"
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(md)
        XCTAssertEqual(stable, "# Title")
        XCTAssertTrue(tail.contains("```swift"))
    }

    func testStableBoundaryClosedCodeFence() {
        let md = "# Title\n\n```swift\nlet x = 1\n```\n\nMore text"
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(md)
        XCTAssertTrue(stable.contains("```swift"))
        XCTAssertTrue(stable.contains("```"))
        XCTAssertEqual(tail.trimmingCharacters(in: .whitespacesAndNewlines), "More text")
    }

    func testStableBoundaryAllUnstable() {
        let md = "Some text without a block break"
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(md)
        XCTAssertEqual(stable, "")
        XCTAssertEqual(tail, md)
    }

    func testStableBoundaryEmptyInput() {
        let (stable, tail) = MarkdownParser.splitAtStableBoundary("")
        XCTAssertEqual(stable, "")
        XCTAssertEqual(tail, "")
    }
}

// MARK: - InlineNode Helpers

extension [InlineNode] {
    var plainText: String {
        map { node in
            switch node {
            case .text(let t): return t
            case .code(let t): return t
            case .emphasis(let children): return children.plainText
            case .strong(let children): return children.plainText
            case .link(_, let children): return children.plainText
            case .lineBreak: return "\n"
            }
        }.joined()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" -only-testing:BudahADETests/MarkdownRendererTests 2>&1 | tail -20
```

Expected: Compilation failure — `MarkdownParser` not defined.

- [ ] **Step 3: Implement MarkdownParser and data model**

Create `BudahADE/Plan/Markdown/MarkdownRenderer.swift`:

```swift
import SwiftUI
import Markdown

// MARK: - Data Model

struct MarkdownBlockItem: Identifiable {
    let id = UUID()
    let kind: MarkdownBlock
    let sourceText: String  // raw markdown for this block (for inline editing)
}

enum MarkdownBlock {
    case heading(level: Int, inlines: [InlineNode])
    case paragraph(inlines: [InlineNode])
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [ListItem])
    case orderedList(start: Int, items: [ListItem])
    case table(headers: [[InlineNode]], rows: [[[InlineNode]]], alignments: [MarkdownTableAlignment?])
    case thematicBreak
}

enum InlineNode {
    case text(String)
    case code(String)
    case emphasis([InlineNode])
    case strong([InlineNode])
    case link(destination: String, children: [InlineNode])
    case lineBreak
}

struct ListItem {
    let content: [InlineNode]
    let children: [MarkdownBlockItem]  // nested lists
}

enum MarkdownTableAlignment {
    case left, center, right
}

// MARK: - Parser

struct MarkdownParser {

    /// Parse a markdown string into an array of MarkdownBlockItems.
    static func parse(_ markdown: String) -> [MarkdownBlockItem] {
        let document = Document(parsing: markdown)
        var walker = BlockWalker(source: markdown)
        walker.visit(document)
        return walker.blocks
    }

    /// Split markdown at the last stable boundary for hybrid streaming.
    /// Returns (stablePrefix, unstableTail).
    static func splitAtStableBoundary(_ markdown: String) -> (String, String) {
        guard !markdown.isEmpty else { return ("", "") }

        // Find all double-newline positions
        let doubleNewlines = findDoubleNewlines(in: markdown)
        guard !doubleNewlines.isEmpty else { return ("", markdown) }

        // Walk backwards to find the last double-newline that isn't inside an open code fence
        for splitPos in doubleNewlines.reversed() {
            let prefix = String(markdown[markdown.startIndex..<splitPos])
            let suffix = String(markdown[splitPos...]).trimmingCharacters(in: .newlines)

            // Check if code fences are balanced in the prefix
            if isCodeFenceBalanced(prefix) {
                return (prefix.trimmingCharacters(in: .whitespacesAndNewlines),
                        suffix)
            }
        }

        // No balanced split point found — everything is unstable
        return ("", markdown)
    }

    // MARK: - Private Helpers

    private static func findDoubleNewlines(in text: String) -> [String.Index] {
        var positions: [String.Index] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\n" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\n" {
                    positions.append(next)
                }
            }
            i = text.index(after: i)
        }
        return positions
    }

    private static func isCodeFenceBalanced(_ text: String) -> Bool {
        var count = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                count += 1
            }
        }
        return count % 2 == 0
    }
}

// MARK: - AST Walker

private struct BlockWalker: MarkupWalker {
    let source: String
    var blocks: [MarkdownBlockItem] = []

    mutating func visitHeading(_ heading: Heading) {
        let inlines = parseInlines(heading.children)
        let sourceText = extractSource(heading)
        blocks.append(MarkdownBlockItem(
            kind: .heading(level: heading.level, inlines: inlines),
            sourceText: sourceText
        ))
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let inlines = parseInlines(paragraph.children)
        let sourceText = extractSource(paragraph)
        blocks.append(MarkdownBlockItem(
            kind: .paragraph(inlines: inlines),
            sourceText: sourceText
        ))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.isEmpty == false ? codeBlock.language : nil
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code
        let sourceText = extractSource(codeBlock)
        blocks.append(MarkdownBlockItem(
            kind: .codeBlock(language: language, code: code),
            sourceText: sourceText
        ))
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let items = parseListItems(unorderedList.children)
        let sourceText = extractSource(unorderedList)
        blocks.append(MarkdownBlockItem(
            kind: .unorderedList(items: items),
            sourceText: sourceText
        ))
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let items = parseListItems(orderedList.children)
        let start = orderedList.startIndex
        let sourceText = extractSource(orderedList)
        blocks.append(MarkdownBlockItem(
            kind: .orderedList(start: start, items: items),
            sourceText: sourceText
        ))
    }

    mutating func visitTable(_ table: Table) {
        let head = table.head
        let headers: [[InlineNode]] = head.cells.map { cell in
            parseInlines(cell.children)
        }

        let alignments: [MarkdownTableAlignment?] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            default: return nil
            }
        }

        let rows: [[[InlineNode]]] = table.body.rows.map { row in
            row.cells.map { cell in
                parseInlines(cell.children)
            }
        }

        let sourceText = extractSource(table)
        blocks.append(MarkdownBlockItem(
            kind: .table(headers: headers, rows: rows, alignments: alignments),
            sourceText: sourceText
        ))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let sourceText = extractSource(thematicBreak)
        blocks.append(MarkdownBlockItem(
            kind: .thematicBreak,
            sourceText: sourceText
        ))
    }

    // MARK: - Inline Parsing

    private func parseInlines(_ children: some Sequence<Markup>) -> [InlineNode] {
        var nodes: [InlineNode] = []
        for child in children {
            switch child {
            case let text as Markdown.Text:
                nodes.append(.text(text.string))
            case let code as InlineCode:
                nodes.append(.code(code.code))
            case let emphasis as Emphasis:
                nodes.append(.emphasis(parseInlines(emphasis.children)))
            case let strong as Strong:
                nodes.append(.strong(parseInlines(strong.children)))
            case let link as Markdown.Link:
                nodes.append(.link(
                    destination: link.destination ?? "",
                    children: parseInlines(link.children)
                ))
            case _ as SoftBreak:
                nodes.append(.text(" "))
            case _ as LineBreak:
                nodes.append(.lineBreak)
            default:
                // For any unhandled inline, try to extract text
                if let plainText = child as? any BasicInlineContainer {
                    nodes.append(contentsOf: parseInlines(plainText.children))
                }
            }
        }
        return nodes
    }

    private func parseListItems(_ children: some Sequence<Markup>) -> [ListItem] {
        children.compactMap { child -> ListItem? in
            guard let listItem = child as? Markdown.ListItem else { return nil }

            var inlines: [InlineNode] = []
            var nestedBlocks: [MarkdownBlockItem] = []

            for itemChild in listItem.children {
                if let paragraph = itemChild as? Paragraph {
                    inlines.append(contentsOf: parseInlines(paragraph.children))
                } else if itemChild is UnorderedList || itemChild is OrderedList {
                    var nestedWalker = BlockWalker(source: source)
                    nestedWalker.visit(itemChild)
                    nestedBlocks.append(contentsOf: nestedWalker.blocks)
                }
            }

            return ListItem(content: inlines, children: nestedBlocks)
        }
    }

    private func extractSource(_ markup: Markup) -> String {
        guard let range = markup.range else { return "" }
        let lines = source.components(separatedBy: "\n")
        let startLine = range.lowerBound.line - 1  // 1-indexed
        let endLine = range.upperBound.line - 1
        guard startLine >= 0, endLine < lines.count else { return "" }
        return lines[startLine...endLine].joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Regenerate Xcode project**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" -only-testing:BudahADETests/MarkdownRendererTests 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/Markdown/MarkdownRenderer.swift BudahADETests/MarkdownRendererTests.swift
git commit -m "feat: add MarkdownParser with block/inline model and streaming boundary detection"
```

---

### Task 3: Syntax Highlighter

**Files:**
- Create: `BudahADE/Plan/Markdown/SyntaxHighlighter.swift`
- Create: `BudahADETests/SyntaxHighlighterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `BudahADETests/SyntaxHighlighterTests.swift`:

```swift
import XCTest
@testable import BudahADE

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - Token Extraction

    func testSwiftKeywordsHighlighted() {
        let tokens = SyntaxHighlighter.tokenize("func hello() { let x = 1 }", language: "swift")
        let keywords = tokens.filter { $0.type == .keyword }
        let keywordTexts = keywords.map { $0.text }
        XCTAssertTrue(keywordTexts.contains("func"))
        XCTAssertTrue(keywordTexts.contains("let"))
    }

    func testStringLiteralsHighlighted() {
        let tokens = SyntaxHighlighter.tokenize("let msg = \"hello world\"", language: "swift")
        let strings = tokens.filter { $0.type == .string }
        XCTAssertFalse(strings.isEmpty)
        XCTAssertTrue(strings.first?.text.contains("hello world") == true)
    }

    func testNumberLiteralsHighlighted() {
        let tokens = SyntaxHighlighter.tokenize("let x = 42", language: "swift")
        let numbers = tokens.filter { $0.type == .number }
        XCTAssertEqual(numbers.first?.text, "42")
    }

    func testCommentsHighlighted() {
        let tokens = SyntaxHighlighter.tokenize("// this is a comment\nlet x = 1", language: "swift")
        let comments = tokens.filter { $0.type == .comment }
        XCTAssertFalse(comments.isEmpty)
        XCTAssertTrue(comments.first?.text.contains("this is a comment") == true)
    }

    func testPythonKeywords() {
        let tokens = SyntaxHighlighter.tokenize("def hello():\n    return True", language: "python")
        let keywords = tokens.filter { $0.type == .keyword }
        let keywordTexts = keywords.map { $0.text }
        XCTAssertTrue(keywordTexts.contains("def"))
        XCTAssertTrue(keywordTexts.contains("return"))
        XCTAssertTrue(keywordTexts.contains("True"))
    }

    func testJavaScriptKeywords() {
        let tokens = SyntaxHighlighter.tokenize("const x = () => { return null }", language: "javascript")
        let keywords = tokens.filter { $0.type == .keyword }
        let keywordTexts = keywords.map { $0.text }
        XCTAssertTrue(keywordTexts.contains("const"))
        XCTAssertTrue(keywordTexts.contains("return"))
        XCTAssertTrue(keywordTexts.contains("null"))
    }

    func testTypeIdentifiers() {
        let tokens = SyntaxHighlighter.tokenize("let x: String = \"hello\"", language: "swift")
        let types = tokens.filter { $0.type == .type }
        XCTAssertTrue(types.contains(where: { $0.text == "String" }))
    }

    func testUnknownLanguageFallback() {
        let tokens = SyntaxHighlighter.tokenize("hello = \"world\" // comment\nlet x = 42", language: "unknown")
        // Should still highlight strings, numbers, and comments
        XCTAssertTrue(tokens.contains(where: { $0.type == .string }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .number }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .comment }))
        // But no keywords
        XCTAssertFalse(tokens.contains(where: { $0.type == .keyword }))
    }

    func testNilLanguageFallback() {
        let tokens = SyntaxHighlighter.tokenize("x = 42 // note", language: nil)
        XCTAssertTrue(tokens.contains(where: { $0.type == .number }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .comment }))
    }

    // MARK: - AttributedString Output

    func testHighlightReturnsAttributedString() {
        let result = SyntaxHighlighter.highlight("func hello() {}", language: "swift")
        XCTAssertFalse(result.characters.isEmpty)
    }

    func testBashHighlighting() {
        let tokens = SyntaxHighlighter.tokenize("if [ -f file.txt ]; then echo \"found\"; fi", language: "bash")
        let keywords = tokens.filter { $0.type == .keyword }
        let keywordTexts = keywords.map { $0.text }
        XCTAssertTrue(keywordTexts.contains("if"))
        XCTAssertTrue(keywordTexts.contains("then"))
        XCTAssertTrue(keywordTexts.contains("fi"))
    }

    func testMultilineComments() {
        let code = """
        /* this is
        a multiline comment */
        let x = 1
        """
        let tokens = SyntaxHighlighter.tokenize(code, language: "swift")
        let comments = tokens.filter { $0.type == .comment }
        XCTAssertFalse(comments.isEmpty)
    }

    func testTokensCoverEntireInput() {
        let code = "func hello() { let x = 1 }"
        let tokens = SyntaxHighlighter.tokenize(code, language: "swift")
        let reconstructed = tokens.map { $0.text }.joined()
        XCTAssertEqual(reconstructed, code)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" -only-testing:BudahADETests/SyntaxHighlighterTests 2>&1 | tail -20
```

Expected: Compilation failure — `SyntaxHighlighter` not defined.

- [ ] **Step 3: Implement SyntaxHighlighter**

Create `BudahADE/Plan/Markdown/SyntaxHighlighter.swift`:

```swift
import SwiftUI

// MARK: - Token Types

enum SyntaxTokenType {
    case keyword
    case type
    case string
    case number
    case comment
    case plain
}

struct SyntaxToken {
    let text: String
    let type: SyntaxTokenType
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {

    /// Tokenize code into typed tokens for a given language.
    static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        let lang = language?.lowercased() ?? ""
        let rules = languageRules(for: lang)
        return applyRules(to: code, rules: rules)
    }

    /// Highlight code and return an AttributedString with colors.
    static func highlight(_ code: String, language: String?) -> AttributedString {
        let tokens = tokenize(code, language: language)
        var result = AttributedString()
        for token in tokens {
            var segment = AttributedString(token.text)
            segment.foregroundColor = color(for: token.type)
            result.append(segment)
        }
        return result
    }

    // MARK: - Colors

    private static func color(for type: SyntaxTokenType) -> Color {
        switch type {
        case .keyword: return Theme.accent       // #c4785c terra cotta
        case .type:    return Theme.info          // #6b8fb5 blue
        case .string:  return Theme.success       // #5a9a6b green
        case .number:  return Theme.warning       // #c4a85c gold
        case .comment: return Theme.textMuted     // #555555
        case .plain:   return Theme.textPrimary   // #e5e5e5
        }
    }

    // MARK: - Language Rules

    private struct HighlightRule {
        let pattern: String
        let type: SyntaxTokenType
        let options: NSRegularExpression.Options

        init(_ pattern: String, _ type: SyntaxTokenType, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.type = type
            self.options = options
        }
    }

    private static func languageRules(for language: String) -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // Comments — always first (highest priority)
        switch language {
        case "python":
            rules.append(HighlightRule(#"#[^\n]*"#, .comment))
        case "bash", "sh", "zsh", "shell":
            rules.append(HighlightRule(#"#[^\n]*"#, .comment))
        case "html", "xml":
            rules.append(HighlightRule(#"<!--[\s\S]*?-->"#, .comment, options: .dotMatchesLineSeparators))
        case "css":
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
        case "sql":
            rules.append(HighlightRule(#"--[^\n]*"#, .comment))
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
        default:
            // C-style comments (Swift, JS, TS, Rust, Go, etc.)
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
            rules.append(HighlightRule(#"//[^\n]*"#, .comment))
        }

        // Strings — second priority
        rules.append(HighlightRule(#""""[\s\S]*?""""#, .string, options: .dotMatchesLineSeparators)) // triple-quote
        rules.append(HighlightRule(#""(?:[^"\\]|\\.)*""#, .string))   // double-quote
        rules.append(HighlightRule(#"'(?:[^'\\]|\\.)*'"#, .string))   // single-quote
        rules.append(HighlightRule(#"`(?:[^`\\]|\\.)*`"#, .string))   // backtick

        // Numbers
        rules.append(HighlightRule(#"\b0x[0-9a-fA-F]+\b"#, .number))
        rules.append(HighlightRule(#"\b\d+\.?\d*\b"#, .number))

        // Keywords — language-specific
        let keywords = keywordsForLanguage(language)
        if !keywords.isEmpty {
            let pattern = #"\b(?:"# + keywords.joined(separator: "|") + #")\b"#
            rules.append(HighlightRule(pattern, .keyword))
        }

        // Type identifiers — PascalCase words (after keyword to avoid overlap)
        rules.append(HighlightRule(#"\b[A-Z][a-zA-Z0-9]+\b"#, .type))

        return rules
    }

    private static func keywordsForLanguage(_ language: String) -> [String] {
        switch language {
        case "swift":
            return ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                    "extension", "return", "if", "else", "guard", "switch", "case", "default",
                    "for", "while", "repeat", "break", "continue", "throw", "throws", "try",
                    "catch", "do", "in", "as", "is", "self", "Self", "super", "init", "deinit",
                    "nil", "true", "false", "static", "private", "public", "internal", "open",
                    "fileprivate", "override", "mutating", "nonmutating", "some", "any",
                    "async", "await", "actor", "nonisolated", "weak", "unowned", "lazy",
                    "where", "typealias", "associatedtype", "inout", "convenience", "required",
                    "final", "dynamic", "optional", "indirect", "precedencegroup", "operator"]

        case "python":
            return ["def", "class", "import", "from", "return", "if", "elif", "else",
                    "for", "while", "break", "continue", "try", "except", "finally",
                    "raise", "with", "as", "pass", "yield", "lambda", "and", "or", "not",
                    "in", "is", "None", "True", "False", "global", "nonlocal", "del",
                    "assert", "async", "await", "self"]

        case "javascript", "typescript", "js", "ts", "jsx", "tsx":
            return ["const", "let", "var", "function", "return", "if", "else", "for",
                    "while", "do", "switch", "case", "default", "break", "continue",
                    "try", "catch", "finally", "throw", "new", "delete", "typeof",
                    "instanceof", "in", "of", "class", "extends", "super", "this",
                    "import", "export", "from", "as", "async", "await", "yield",
                    "null", "undefined", "true", "false", "void", "static", "get", "set",
                    "interface", "type", "enum", "implements", "abstract", "readonly"]

        case "rust":
            return ["fn", "let", "mut", "const", "static", "struct", "enum", "trait",
                    "impl", "mod", "use", "pub", "crate", "super", "self", "Self",
                    "if", "else", "match", "for", "while", "loop", "break", "continue",
                    "return", "as", "in", "ref", "move", "async", "await", "dyn",
                    "where", "type", "unsafe", "extern", "true", "false"]

        case "go", "golang":
            return ["func", "var", "const", "type", "struct", "interface", "map",
                    "chan", "package", "import", "return", "if", "else", "for",
                    "range", "switch", "case", "default", "break", "continue",
                    "go", "defer", "select", "fallthrough", "nil", "true", "false"]

        case "bash", "sh", "zsh", "shell":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "in", "function", "return", "exit", "local",
                    "export", "source", "echo", "read", "set", "unset", "shift",
                    "true", "false"]

        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                    "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX",
                    "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR",
                    "NOT", "NULL", "IS", "IN", "AS", "ORDER", "BY", "GROUP", "HAVING",
                    "LIMIT", "OFFSET", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN",
                    "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT",
                    "select", "from", "where", "insert", "into", "values", "update",
                    "set", "delete", "create", "table", "alter", "drop", "join",
                    "left", "right", "inner", "outer", "on", "and", "or", "not",
                    "null", "is", "in", "as", "order", "by", "group", "having",
                    "limit", "offset", "distinct"]

        case "json":
            return ["true", "false", "null"]

        case "yaml", "yml":
            return ["true", "false", "null", "yes", "no", "on", "off"]

        default:
            return []
        }
    }

    // MARK: - Rule Application

    private static func applyRules(to code: String, rules: [HighlightRule]) -> [SyntaxToken] {
        // Build a map of character ranges to token types
        var typeMap = Array(repeating: SyntaxTokenType.plain, count: code.utf16.count)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let nsRange = NSRange(code.startIndex..<code.endIndex, in: code)
            let matches = regex.matches(in: code, range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: code) else { continue }
                let utf16Start = code.utf16.distance(from: code.utf16.startIndex, to: range.lowerBound.samePosition(in: code.utf16) ?? code.utf16.startIndex)
                let utf16End = code.utf16.distance(from: code.utf16.startIndex, to: range.upperBound.samePosition(in: code.utf16) ?? code.utf16.endIndex)
                // Only assign if currently plain (first match wins)
                for i in utf16Start..<min(utf16End, typeMap.count) {
                    if typeMap[i] == .plain {
                        typeMap[i] = rule.type
                    }
                }
            }
        }

        // Coalesce adjacent characters of the same type into tokens
        var tokens: [SyntaxToken] = []
        var currentType = typeMap.isEmpty ? .plain : typeMap[0]
        var currentChars: [Character] = []
        var utf16Index = 0

        for char in code {
            let charUTF16Count = String(char).utf16.count
            let charType = utf16Index < typeMap.count ? typeMap[utf16Index] : .plain

            if charType == currentType {
                currentChars.append(char)
            } else {
                if !currentChars.isEmpty {
                    tokens.append(SyntaxToken(text: String(currentChars), type: currentType))
                }
                currentChars = [char]
                currentType = charType
            }
            utf16Index += charUTF16Count
        }

        if !currentChars.isEmpty {
            tokens.append(SyntaxToken(text: String(currentChars), type: currentType))
        }

        return tokens
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and run tests**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" -only-testing:BudahADETests/SyntaxHighlighterTests 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Plan/Markdown/SyntaxHighlighter.swift BudahADETests/SyntaxHighlighterTests.swift
git commit -m "feat: add regex-based syntax highlighter with multi-language support"
```

---

### Task 4: CodeBlockView Component

**Files:**
- Create: `BudahADE/Plan/Markdown/CodeBlockView.swift`

- [ ] **Step 1: Implement CodeBlockView**

Create `BudahADE/Plan/Markdown/CodeBlockView.swift`:

```swift
import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            header

            // Code content
            codeContent
        }
        .background(Theme.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Header

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

    // MARK: - Code Content

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

    // MARK: - Copy

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
```

- [ ] **Step 2: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Plan/Markdown/CodeBlockView.swift
git commit -m "feat: add CodeBlockView with syntax highlighting and copy button"
```

---

### Task 5: MarkdownRenderer SwiftUI View + InlineNodesView

**Files:**
- Modify: `BudahADE/Plan/Markdown/MarkdownRenderer.swift` (add the SwiftUI view to the existing file)

- [ ] **Step 1: Add InlineNodesView and MarkdownRenderer view**

Append to the bottom of `BudahADE/Plan/Markdown/MarkdownRenderer.swift`:

```swift
// MARK: - Inline Nodes View

struct InlineNodesView: View {
    let nodes: [InlineNode]

    var body: some View {
        nodes.reduce(Text("")) { result, node in
            result + renderInline(node)
        }
        .textSelection(.enabled)
    }

    private func renderInline(_ node: InlineNode) -> Text {
        switch node {
        case .text(let string):
            return Text(string)

        case .code(let code):
            return Text(code)
                .font(Theme.mono(13))
                .foregroundColor(Theme.textPrimary)

        case .emphasis(let children):
            return children.reduce(Text("")) { result, child in
                result + renderInline(child)
            }
            .italic()
            .foregroundColor(Theme.textSecondary)

        case .strong(let children):
            return children.reduce(Text("")) { result, child in
                result + renderInline(child)
            }
            .bold()
            .foregroundColor(.white)

        case .link(let destination, let children):
            // SwiftUI Text concatenation doesn't support tappable links,
            // so we render as accent-colored text. The URL is available via
            // text selection + copy.
            let label = children.reduce(Text("")) { result, child in
                result + renderInline(child)
            }
            return label
                .foregroundColor(Theme.accent)
                .underline()

        case .lineBreak:
            return Text("\n")
        }
    }
}

// MARK: - Markdown Renderer View

struct MarkdownRenderer: View {
    let content: String
    let isStreaming: Bool

    init(_ content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isStreaming {
                streamingContent
            } else {
                renderedBlocks(from: content)
            }
        }
    }

    // MARK: - Streaming

    @ViewBuilder
    private var streamingContent: some View {
        let (stable, tail) = MarkdownParser.splitAtStableBoundary(content)

        if !stable.isEmpty {
            renderedBlocks(from: stable)
        }

        if !tail.isEmpty {
            Text(tail)
                .font(Theme.body(14))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.top, stable.isEmpty ? 0 : 8)
        }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func renderedBlocks(from markdown: String) -> some View {
        let blocks = MarkdownParser.parse(markdown)
        ForEach(blocks) { block in
            blockView(for: block)
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlockItem) -> some View {
        switch block.kind {
        case .heading(let level, let inlines):
            headingView(level: level, inlines: inlines)

        case .paragraph(let inlines):
            InlineNodesView(nodes: inlines)
                .font(Theme.body(14))
                .foregroundColor(Theme.textPrimary)
                .padding(.bottom, 8)

        case .codeBlock(let language, let code):
            CodeBlockView(code: code, language: language)
                .padding(.vertical, 4)

        case .unorderedList(let items):
            unorderedListView(items: items)
                .padding(.bottom, 8)

        case .orderedList(let start, let items):
            orderedListView(start: start, items: items)
                .padding(.bottom, 8)

        case .table(let headers, let rows, let alignments):
            MarkdownTableView(headers: headers, rows: rows, alignments: alignments)
                .padding(.vertical, 4)

        case .thematicBreak:
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, 12)
        }
    }

    // MARK: - Headings

    @ViewBuilder
    private func headingView(level: Int, inlines: [InlineNode]) -> some View {
        let (font, topPad, bottomPad): (Font, CGFloat, CGFloat) = {
            switch level {
            case 1: return (Theme.headline(22), 20, 8)
            case 2: return (Theme.headline(18), 16, 6)
            default: return (Theme.label(15), 12, 4)
            }
        }()

        InlineNodesView(nodes: inlines)
            .font(font)
            .foregroundColor(Theme.textPrimary)
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
    }

    // MARK: - Lists

    @ViewBuilder
    private func unorderedListView(items: [ListItem], indent: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textMuted)
                    InlineNodesView(nodes: item.content)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.leading, indent)

                // Nested lists
                ForEach(item.children) { child in
                    blockView(for: child)
                        .padding(.leading, indent + 20)
                }
            }
        }
    }

    @ViewBuilder
    private func orderedListView(start: Int, items: [ListItem], indent: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(start + idx).")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textMuted)
                        .frame(minWidth: 20, alignment: .trailing)
                    InlineNodesView(nodes: item.content)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.leading, indent)

                ForEach(item.children) { child in
                    blockView(for: child)
                        .padding(.leading, indent + 20)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/Markdown/MarkdownRenderer.swift
git commit -m "feat: add MarkdownRenderer SwiftUI view with inline rendering and streaming support"
```

---

### Task 6: MarkdownTableView Component

**Files:**
- Create: `BudahADE/Plan/Markdown/MarkdownTableView.swift`

- [ ] **Step 1: Implement MarkdownTableView**

Create `BudahADE/Plan/Markdown/MarkdownTableView.swift`:

```swift
import SwiftUI

struct MarkdownTableView: View {
    let headers: [[InlineNode]]
    let rows: [[[InlineNode]]]
    let alignments: [MarkdownTableAlignment?]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { colIdx, header in
                        InlineNodesView(nodes: header)
                            .font(Theme.label(13))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: alignment(for: colIdx))
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(height: 1)
                }

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            InlineNodesView(nodes: cell)
                                .font(Theme.body(13))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: alignment(for: colIdx))
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.white.opacity(0.02) : Color.clear)
                }
            }
        }
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .left, nil: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
```

- [ ] **Step 2: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Plan/Markdown/MarkdownTableView.swift
git commit -m "feat: add MarkdownTableView with alignment and alternating rows"
```

---

### Task 7: Wire MarkdownRenderer into PlanChatView

**Files:**
- Modify: `BudahADE/Plan/PlanChatView.swift`

- [ ] **Step 1: Replace assistant bubble with MarkdownRenderer**

In `PlanChatView.swift`, find the `assistantBubble` computed property inside `PlanMessageBubble` (around line 528) and replace it:

**Replace this:**
```swift
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tool calls — compact
            if let tools = message.toolCalls, !tools.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.bottom, 2)
            }

            if !message.content.isEmpty {
                HStack {
                    Text(message.content)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer(minLength: 80)
                }
            }
        }
    }
```

**With this:**
```swift
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tool calls — compact
            if let tools = message.toolCalls, !tools.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.bottom, 2)
            }

            if !message.content.isEmpty {
                MarkdownRenderer(message.content)
            }
        }
    }
```

- [ ] **Step 2: Replace streaming bubble with MarkdownRenderer**

Find the `streamingBubble` function (around line 193) and replace it:

**Replace this:**
```swift
    private func streamingBubble(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(Theme.body(14))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 80)
        }
    }
```

**With this:**
```swift
    private func streamingBubble(_ text: String) -> some View {
        MarkdownRenderer(text, isStreaming: true)
    }
```

- [ ] **Step 3: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all tests**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Plan/PlanChatView.swift
git commit -m "feat: wire MarkdownRenderer into PlanChatView for rich message rendering"
```

---

### Task 8: Build/Edit Action Buttons

**Files:**
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Modify: `BudahADE/Plan/PlanChatView.swift`

- [ ] **Step 1: Add spec state to PlanChatState**

In `PlanChatState.swift`, add these published properties after `selectedModel`:

```swift
    @Published var pendingSpec: String?
    @Published var editingMessageId: UUID?
    @Published var editingBlockIndex: Int?
```

- [ ] **Step 2: Add spec detection helper**

Add this method to `PlanChatState`:

```swift
    // MARK: - Spec Detection

    /// Check if a message content looks like a spec or plan.
    func looksLikeSpec(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let hasSpecHeading = lowered.contains("# spec") ||
            lowered.contains("# plan") ||
            lowered.contains("# implementation plan") ||
            lowered.contains("# design") ||
            lowered.contains("# architecture") ||
            lowered.contains("## spec") ||
            lowered.contains("## plan") ||
            lowered.contains("## implementation plan") ||
            lowered.contains("## design") ||
            lowered.contains("## architecture")

        let hasList = content.contains("\n- ") || content.contains("\n1. ") || content.contains("\n* ")

        return hasSpecHeading && hasList
    }
```

- [ ] **Step 3: Add Build/Edit buttons to PlanMessageBubble**

In `PlanChatView.swift`, the `PlanMessageBubble` struct needs access to state for spec detection and actions. Update the struct to accept closures. Replace the `PlanMessageBubble` struct definition:

**Replace this:**
```swift
private struct PlanMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemBubble
        }
    }
```

**With this:**
```swift
private struct PlanMessageBubble: View {
    let message: ChatMessage
    let isSpec: Bool
    let onBuild: (() -> Void)?
    let onEdit: (() -> Void)?

    init(message: ChatMessage, isSpec: Bool = false, onBuild: (() -> Void)? = nil, onEdit: (() -> Void)? = nil) {
        self.message = message
        self.isSpec = isSpec
        self.onBuild = onBuild
        self.onEdit = onEdit
    }

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            VStack(alignment: .leading, spacing: 0) {
                assistantBubble

                if isSpec {
                    specActionButtons
                }
            }
        case .system:
            systemBubble
        }
    }
```

- [ ] **Step 4: Add the spec action buttons view**

Add this to `PlanMessageBubble`, after the `systemBubble` computed property:

```swift
    private var specActionButtons: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                onEdit?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(Theme.label(12))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                onBuild?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 11))
                    Text("Build")
                        .font(Theme.label(12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
```

- [ ] **Step 5: Update the ForEach in messageList to pass spec detection**

In `PlanChatView`, find the `ForEach(session.messages)` block (around line 85) and update it:

**Replace this:**
```swift
                        ForEach(session.messages) { message in
                            PlanMessageBubble(message: message)
                                .id(message.id)
                        }
```

**With this:**
```swift
                        ForEach(session.messages) { message in
                            PlanMessageBubble(
                                message: message,
                                isSpec: message.role == .assistant && state.looksLikeSpec(message.content),
                                onBuild: {
                                    state.pendingSpec = message.content
                                    print("[PlanChat] Build requested for spec (\(message.content.count) chars)")
                                },
                                onEdit: {
                                    state.editingMessageId = message.id
                                }
                            )
                            .id(message.id)
                        }
```

- [ ] **Step 6: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Run all tests**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add BudahADE/Plan/PlanChatState.swift BudahADE/Plan/PlanChatView.swift
git commit -m "feat: add Build/Edit action buttons for spec messages"
```

---

### Task 9: Inline Block Editing

**Files:**
- Modify: `BudahADE/Plan/PlanChatView.swift`
- Modify: `BudahADE/Plan/Markdown/MarkdownRenderer.swift`

- [ ] **Step 1: Add editing support to MarkdownRenderer**

Add an editable variant of `MarkdownRenderer` by appending to `MarkdownRenderer.swift`:

```swift
// MARK: - Editable Markdown Renderer

struct EditableMarkdownRenderer: View {
    @Binding var content: String
    @State private var editingBlockId: UUID?
    @State private var editText: String = ""

    var body: some View {
        let blocks = MarkdownParser.parse(content)

        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                if block.id == editingBlockId {
                    // Editing mode for this block
                    editableBlock(block: block)
                } else {
                    // Rendered mode with hover affordance
                    renderableBlock(block: block)
                }
            }

            // Done button
            HStack {
                Spacer()
                Button("Done") {
                    commitEdit()
                    editingBlockId = nil
                }
                .font(Theme.label(12))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func renderableBlock(block: MarkdownBlockItem) -> some View {
        MarkdownRenderer(block.sourceText)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.iBeam.push()
                } else {
                    NSCursor.pop()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                    .opacity(0) // Becomes visible on hover via SwiftUI hover state
            )
            .onTapGesture {
                commitEdit() // commit any previous edit
                editingBlockId = block.id
                editText = block.sourceText
            }
    }

    @ViewBuilder
    private func editableBlock(block: MarkdownBlockItem) -> some View {
        TextEditor(text: $editText)
            .font(Theme.mono(13))
            .foregroundColor(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60)
            .padding(8)
            .background(Theme.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.borderActive, lineWidth: 1)
            )
            .onSubmit {
                commitEdit()
            }
    }

    private func commitEdit() {
        guard let blockId = editingBlockId else { return }
        let blocks = MarkdownParser.parse(content)
        guard let block = blocks.first(where: { $0.id == blockId }) else { return }

        // Replace the block's source text in the content
        if let range = content.range(of: block.sourceText) {
            content.replaceSubrange(range, with: editText)
        }

        editingBlockId = nil
        editText = ""
    }
}
```

- [ ] **Step 2: Wire editing into PlanChatView**

In `PlanChatView.swift`, add an `editableSpecContent` state variable and a sheet/overlay for editing. After the `ForEach(session.messages)` block, add handling for the edit mode.

Find the `onEdit` closure in the `ForEach` (from Task 8, Step 5) and update it:

**Replace:**
```swift
                                onEdit: {
                                    state.editingMessageId = message.id
                                }
```

**With:**
```swift
                                onEdit: {
                                    state.editingMessageId = message.id
                                    state.pendingSpec = message.content
                                }
```

Then, in `PlanMessageBubble`, update the assistant case in `body` to show the editable renderer when the message is being edited. Update the `PlanMessageBubble` struct to accept an `isEditing` flag and a content binding:

**Update `PlanMessageBubble` init to add:**
```swift
    let isEditing: Bool
    @Binding var editableContent: String

    init(message: ChatMessage, isSpec: Bool = false, isEditing: Bool = false, editableContent: Binding<String> = .constant(""), onBuild: (() -> Void)? = nil, onEdit: (() -> Void)? = nil) {
        self.message = message
        self.isSpec = isSpec
        self.isEditing = isEditing
        self._editableContent = editableContent
        self.onBuild = onBuild
        self.onEdit = onEdit
    }
```

**Update the assistant case in `body`:**
```swift
        case .assistant:
            VStack(alignment: .leading, spacing: 0) {
                if isEditing {
                    EditableMarkdownRenderer(content: $editableContent)
                } else {
                    assistantBubble
                }

                if isSpec && !isEditing {
                    specActionButtons
                }
            }
```

**Update the ForEach call to pass editing state:**

```swift
                        ForEach(session.messages) { message in
                            let isEditing = state.editingMessageId == message.id
                            PlanMessageBubble(
                                message: message,
                                isSpec: message.role == .assistant && state.looksLikeSpec(message.content),
                                isEditing: isEditing,
                                editableContent: Binding(
                                    get: { state.pendingSpec ?? message.content },
                                    set: { state.pendingSpec = $0 }
                                ),
                                onBuild: {
                                    state.pendingSpec = message.content
                                    print("[PlanChat] Build requested for spec (\(message.content.count) chars)")
                                },
                                onEdit: {
                                    state.editingMessageId = message.id
                                    state.pendingSpec = message.content
                                }
                            )
                            .id(message.id)
                        }
```

- [ ] **Step 3: Regenerate and verify build**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodegen generate
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all tests**

Run:
```bash
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" 2>&1 | tail -30
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Plan/Markdown/MarkdownRenderer.swift BudahADE/Plan/PlanChatView.swift
git commit -m "feat: add inline block editing for spec messages"
```

---

### Task 10: Integration Verification

**Files:**
- No new files — verification only

- [ ] **Step 1: Run the full test suite**

Run:
```bash
cd "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8"
xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination "platform=macOS" 2>&1 | grep -E "(Test Suite|Test Case|Executed|FAIL)"
```

Expected: All test suites pass. Zero failures.

- [ ] **Step 2: Verify the full build**

Run:
```bash
xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE -destination "platform=macOS" -quiet
```

Expected: BUILD SUCCEEDED with no warnings related to the new Markdown files.

- [ ] **Step 3: Commit any remaining changes**

```bash
git status
```

If any unstaged changes remain, stage and commit them with an appropriate message.

- [ ] **Step 4: Verify new file structure**

Run:
```bash
ls -la "/Users/amir/Documents/Cursor Projects/worktrees/planning-conversation-enhanement-4f8/BudahADE/Plan/Markdown/"
```

Expected:
```
CodeBlockView.swift
MarkdownRenderer.swift
MarkdownTableView.swift
SyntaxHighlighter.swift
```
