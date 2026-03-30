import XCTest
@testable import BudahADE

final class PlanRoleTests: XCTestCase {

    // MARK: - All Plan Roles Exist

    func testAllPlanRolesExist() {
        let planRoles = AgentMode.planRoles
        XCTAssertEqual(planRoles.count, 5, "Expected 5 plan roles")
        XCTAssertTrue(planRoles.contains(.researcher))
        XCTAssertTrue(planRoles.contains(.ideator))
        XCTAssertTrue(planRoles.contains(.designer))
        XCTAssertTrue(planRoles.contains(.developer))
        XCTAssertTrue(planRoles.contains(.specAuthor))
    }

    // MARK: - Designer Properties

    func testDesignerProperties() {
        let mode = AgentMode.designer
        XCTAssertEqual(mode.displayName, "Designer")
        XCTAssertEqual(mode.defaultChatModel, .opus)
        XCTAssertEqual(mode.chatAllowedTools, ["Read", "Glob", "Grep"])
        XCTAssertEqual(mode.chatMaxTurns, 5)
    }

    // MARK: - Spec Author Properties

    func testSpecAuthorProperties() {
        let mode = AgentMode.specAuthor
        XCTAssertEqual(mode.displayName, "Spec Author")
        XCTAssertEqual(mode.defaultChatModel, .opus)
        XCTAssertEqual(mode.chatAllowedTools, ["Read", "Glob", "Grep", "Write"])
        XCTAssertNil(mode.chatMaxTurns)
    }

    // MARK: - Keyboard Shortcuts

    func testKeyboardShortcuts() {
        XCTAssertEqual(AgentMode.researcher.roleShortcutIndex, 1)
        XCTAssertEqual(AgentMode.ideator.roleShortcutIndex, 2)
        XCTAssertEqual(AgentMode.designer.roleShortcutIndex, 3)
        XCTAssertEqual(AgentMode.developer.roleShortcutIndex, 4)
        XCTAssertEqual(AgentMode.specAuthor.roleShortcutIndex, 5)
        XCTAssertNil(AgentMode.claude.roleShortcutIndex)
    }

    // MARK: - Plan Roles Excludes Claude

    func testPlanRolesExcludesClaude() {
        let planRoles = AgentMode.planRoles
        XCTAssertFalse(planRoles.contains(.claude), "planRoles should not include .claude")
    }

    // MARK: - Role Icon Names

    func testDesignerIconName() {
        XCTAssertEqual(AgentMode.designer.iconName, "paintbrush")
    }

    func testSpecAuthorIconName() {
        XCTAssertEqual(AgentMode.specAuthor.iconName, "doc.text")
    }

    // MARK: - Role Descriptions

    func testDesignerDescription() {
        XCTAssertFalse(AgentMode.designer.description.isEmpty)
    }

    func testSpecAuthorDescription() {
        XCTAssertFalse(AgentMode.specAuthor.description.isEmpty)
    }

    // MARK: - PlanChatState Role Integration

    @MainActor
    func testPlanChatStateDefaultRole() {
        let state = PlanChatState(
            worktreePath: "/tmp",
            taskName: "Test",
            branchName: "main"
        )
        XCTAssertEqual(state.role, .researcher)
        XCTAssertEqual(state.selectedModel, AgentMode.researcher.defaultChatModel)
    }

    @MainActor
    func testPlanChatStateCustomRole() {
        let state = PlanChatState(
            worktreePath: "/tmp",
            taskName: "Test",
            branchName: "main",
            role: .specAuthor
        )
        XCTAssertEqual(state.role, .specAuthor)
        XCTAssertEqual(state.selectedModel, AgentMode.specAuthor.defaultChatModel)
    }

    // MARK: - PlanTabInfo Role Integration

    func testPlanTabInfoRole() {
        let tab = PlanTabInfo(title: "Spec", role: .specAuthor)
        XCTAssertEqual(tab.role, .specAuthor)
    }

    func testPlanTabInfoDefaultRole() {
        let tab = PlanTabInfo()
        XCTAssertEqual(tab.role, .researcher)
    }
}
