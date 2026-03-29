import XCTest
@testable import BudahADE

final class SyntaxHighlighterTests: XCTestCase {

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
        XCTAssertTrue(tokens.contains(where: { $0.type == .string }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .number }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .comment }))
        XCTAssertFalse(tokens.contains(where: { $0.type == .keyword }))
    }

    func testNilLanguageFallback() {
        let tokens = SyntaxHighlighter.tokenize("x = 42 // note", language: nil)
        XCTAssertTrue(tokens.contains(where: { $0.type == .number }))
        XCTAssertTrue(tokens.contains(where: { $0.type == .comment }))
    }

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
