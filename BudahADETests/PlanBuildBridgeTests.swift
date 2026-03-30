import XCTest
@testable import BudahADE

final class PlanBuildBridgeTests: XCTestCase {

    // MARK: - Helpers

    private func makeTmpDir() -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.path
    }

    private func write(_ content: String, to relativePath: String, in dir: String) {
        let full = (dir as NSString).appendingPathComponent(relativePath)
        let parent = (full as NSString).deletingLastPathComponent
        try! FileManager.default.createDirectory(
            atPath: parent, withIntermediateDirectories: true
        )
        try! content.write(toFile: full, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    func testBuildContextBlockWithSpec() {
        let dir = makeTmpDir()
        let spec = """
        # My Feature Spec

        - [x] Setup project
        - [x] Add auth
        - [ ] Add dashboard
        - [ ] Add tests
        """
        write(spec, to: ".budahade/spec.md", in: dir)

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertTrue(result.contains("## Build Progress"), "Should contain Build Progress header")
        XCTAssertTrue(result.contains("### Spec Progress"), "Should contain Spec Progress section")
        XCTAssertTrue(result.contains("2 of 4 tasks completed"), "Should report 2 of 4 completed")
        XCTAssertTrue(result.contains("- [x] Setup project"), "Should include completed items")
        XCTAssertTrue(result.contains("- [x] Add auth"), "Should include completed items")
        XCTAssertTrue(result.contains("- [ ] Add dashboard"), "Should include remaining items")
        XCTAssertTrue(result.contains("- [ ] Add tests"), "Should include remaining items")
    }

    func testBuildContextBlockWithAgentOutput() {
        let dir = makeTmpDir()
        let panelId = UUID()
        let outputContent = "## Research Findings\n\nThe auth flow needs JWT tokens."
        write(outputContent, to: ".budahade/agent-output/\(panelId.uuidString).md", in: dir)

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertTrue(result.contains("## Build Progress"), "Should contain Build Progress header")
        XCTAssertTrue(result.contains("### Agent Output"), "Should contain Agent Output section")
        XCTAssertTrue(result.contains("Research Findings"), "Should include agent output content")
        XCTAssertTrue(result.contains("JWT tokens"), "Should include agent output content")
    }

    func testBuildContextBlockWithBothSpecAndOutput() {
        let dir = makeTmpDir()
        let spec = """
        # Spec

        - [x] Task one
        - [ ] Task two
        """
        write(spec, to: ".budahade/spec.md", in: dir)
        write("## Summary\n\nAgent finished task one.", to: ".budahade/agent-output/output.md", in: dir)

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertTrue(result.contains("### Spec Progress"), "Should contain Spec Progress")
        XCTAssertTrue(result.contains("1 of 2 tasks completed"), "Should report 1 of 2")
        XCTAssertTrue(result.contains("### Agent Output"), "Should contain Agent Output")
        XCTAssertTrue(result.contains("Agent finished task one"), "Should include agent output")
    }

    func testEmptyBuildContextWhenNoBuildHistory() {
        let dir = makeTmpDir()

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertEqual(result, "", "Should return empty string when no spec or agent output exists")
    }

    func testEmptyBuildContextWhenSpecExistsButHasNoCheckboxes() {
        let dir = makeTmpDir()
        let spec = "# Spec\n\nSome prose without checkboxes."
        write(spec, to: ".budahade/spec.md", in: dir)

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertEqual(result, "", "Should return empty string when spec has no checkbox items")
    }

    func testEmptyBuildContextWhenAgentOutputIsEmpty() {
        let dir = makeTmpDir()
        write("   \n  ", to: ".budahade/agent-output/empty.md", in: dir)

        let result = AgentPrompts.buildContextBlock(worktreePath: dir)

        XCTAssertEqual(result, "", "Should return empty string when agent output files are blank")
    }

    // MARK: - enterPlanMode preserves tabs

    @MainActor
    func testEnterPlanModePreservesExistingTabs() {
        let dir = makeTmpDir()
        let task = TaskState(
            name: "Test Task",
            branchName: "feat/test",
            worktreePath: dir,
            repoPath: dir
        )

        // Enter plan mode and manually create a tab (modal would do this in UI)
        task.enterPlanMode()
        let tabId = task.createPlanTab(role: .researcher)
        XCTAssertEqual(task.planTabs.count, 1, "Should have 1 tab after manual creation")

        // Simulate going to build mode then back to plan
        task.mode = .build
        task.enterPlanMode()

        XCTAssertEqual(task.planTabs.count, 1, "Should still have exactly 1 tab after re-entering plan mode")
        XCTAssertEqual(task.planTabs.first?.id, tabId, "Tab ID should be unchanged")
        XCTAssertEqual(task.mode, .plan, "Mode should be .plan")
    }
}
