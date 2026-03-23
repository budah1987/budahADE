import XCTest
@testable import BudahADE

final class TileTypeTests: XCTestCase {
    func testMarkdownDisplayName() {
        let tile = TileType.markdown(path: "/tmp/spec.md")
        XCTAssertEqual(tile.displayName, "Markdown")
    }

    func testStickyNoteDisplayName() {
        let tile = TileType.stickyNote
        XCTAssertEqual(tile.displayName, "Sticky Note")
    }

    func testTextBoxDisplayName() {
        let tile = TileType.textBox
        XCTAssertEqual(tile.displayName, "Text Box")
    }

    func testMarkdownIconName() {
        let tile = TileType.markdown(path: "/tmp/test.md")
        XCTAssertEqual(tile.iconName, "doc.text")
    }
}
