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

final class FrameDataTests: XCTestCase {
    func testEmptyFrameSize() {
        let frame = FrameData()
        XCTAssertEqual(frame.computedSize, CGSize(width: 240, height: 180))
    }

    func testHorizontalChildPositions() {
        var frame = FrameData(axis: .horizontal, gap: 10, padding: 20)
        frame.children = [
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
        ]
        let positions = frame.childPositions()
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].x, 20) // padding
        XCTAssertEqual(positions[1].x, 130) // padding + width + gap
    }

    func testVerticalChildPositions() {
        var frame = FrameData(axis: .vertical, gap: 10, padding: 20)
        frame.children = [
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
        ]
        let positions = frame.childPositions()
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].y, frame.headerHeight + 20) // header + padding
        XCTAssertEqual(positions[1].y, frame.headerHeight + 20 + 80 + 10) // header + padding + height + gap
    }
}

final class TextDataTests: XCTestCase {
    func testDefaultColor() {
        let data = TextData()
        XCTAssertEqual(data.colorHex, 0xe5e5e5)
    }

    func testMeasuredSizeNonZero() {
        let data = TextData(content: "Hello world")
        let size = data.measuredSize(maxWidth: 200)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
