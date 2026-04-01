import XCTest
@testable import BudahADE

@MainActor
final class PaneFocusTests: XCTestCase {

    var task: TaskState!

    override func setUp() async throws {
        task = TaskState(
            id: UUID(),
            name: "test",
            branchName: "main",
            baseBranch: "main",
            worktreePath: "/tmp",
            repoPath: "/tmp"
        )
    }

    // No split — all arrow presses are no-ops
    func testFocusPaneNoSplitIsNoop() {
        task.focusedPane = .primary
        task.focusPane(arrow: .right)
        XCTAssertEqual(task.focusedPane, .primary)
    }

    // Horizontal split: left → primary, right → secondary
    func testFocusPaneHorizontalLeftRight() {
        task.splitPane = SplitPaneState(
            secondaryTabIds: [UUID()],
            secondarySelectedId: nil,
            orientation: .horizontal
        )
        task.focusedPane = .primary
        task.focusPane(arrow: .right)
        XCTAssertEqual(task.focusedPane, .secondary)

        task.focusPane(arrow: .left)
        XCTAssertEqual(task.focusedPane, .primary)
    }

    // Horizontal split: up/down are no-ops
    func testFocusPaneHorizontalUpDownIsNoop() {
        task.splitPane = SplitPaneState(
            secondaryTabIds: [UUID()],
            secondarySelectedId: nil,
            orientation: .horizontal
        )
        task.focusedPane = .primary
        task.focusPane(arrow: .up)
        XCTAssertEqual(task.focusedPane, .primary)
        task.focusPane(arrow: .down)
        XCTAssertEqual(task.focusedPane, .primary)
    }

    // Vertical split: up → primary, down → secondary
    func testFocusPaneVerticalUpDown() {
        task.splitPane = SplitPaneState(
            secondaryTabIds: [UUID()],
            secondarySelectedId: nil,
            orientation: .vertical
        )
        task.focusedPane = .primary
        task.focusPane(arrow: .down)
        XCTAssertEqual(task.focusedPane, .secondary)

        task.focusPane(arrow: .up)
        XCTAssertEqual(task.focusedPane, .primary)
    }

    // Vertical split: left/right are no-ops
    func testFocusPaneVerticalLeftRightIsNoop() {
        task.splitPane = SplitPaneState(
            secondaryTabIds: [UUID()],
            secondarySelectedId: nil,
            orientation: .vertical
        )
        task.focusedPane = .primary
        task.focusPane(arrow: .left)
        XCTAssertEqual(task.focusedPane, .primary)
        task.focusPane(arrow: .right)
        XCTAssertEqual(task.focusedPane, .primary)
    }
}
