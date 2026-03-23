import XCTest
@testable import BudahADE

final class MarkdownSectionParserTests: XCTestCase {
    func testSplitByHeadings() {
        let md = """
        # Title
        Intro text.

        ## Section One
        Content one.

        ## Section Two
        Content two.
        - [ ] Task A
        - [x] Task B
        """
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].heading, "Section One")
        XCTAssertEqual(result[1].heading, "Section Two")
        XCTAssertEqual(result[1].checkboxItems.count, 2)
        XCTAssertFalse(result[1].checkboxItems[0].isCompleted)
        XCTAssertTrue(result[1].checkboxItems[1].isCompleted)
    }

    func testSourceAttribution() {
        let md = """
        ## Design
        <!-- source: abc-123 -->
        Design content here.
        """
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result[0].sourceId, "abc-123")
    }

    func testNoSections() {
        let md = "Just some text with no headings."
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result.count, 0)
    }

    func testCheckboxToggleRewrite() {
        let original = "- [ ] unchecked task"
        let toggled = SpecParser.toggleCheckbox(in: original, at: 0)
        XCTAssertEqual(toggled, "- [x] unchecked task")
    }
}
