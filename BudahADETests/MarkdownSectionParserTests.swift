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
        // Checkbox must be inside a ## section to be toggled
        let original = """
        ## Tasks
        - [ ] unchecked task
        """
        let toggled = SpecParser.toggleCheckbox(in: original, at: 0)
        XCTAssertTrue(toggled.contains("- [x] unchecked task"))
    }

    func testDuplicateHeadingsGetUniqueIds() {
        let md = """
        ## Design
        First design section.

        ## Design
        Second design section.
        """
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "design")
        XCTAssertEqual(result[1].id, "design-2")
    }

    func testToggleCheckboxIgnoresOrphanCheckboxes() {
        let md = """
        - [ ] orphan checkbox

        ## Tasks
        - [ ] real task A
        - [ ] real task B
        """
        // Toggle task at index 0 should toggle "real task A", not the orphan
        let toggled = SpecParser.toggleCheckbox(in: md, at: 0)
        XCTAssertTrue(toggled.contains("- [x] real task A"))
        XCTAssertTrue(toggled.contains("- [ ] orphan checkbox"))  // orphan untouched
    }
}
