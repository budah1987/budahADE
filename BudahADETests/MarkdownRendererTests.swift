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
        XCTAssertEqual(blocks.count, 4)
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
