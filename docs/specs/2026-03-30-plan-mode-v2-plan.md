# Plan Mode V2 — "The Planning Loop" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Plan mode from a simple chat into a role-based planning workspace with cross-tab context awareness, spec assembly via action buttons, bidirectional plan↔build bridging, spec versioning, and task archiving.

**Architecture:** Extend existing `AgentMode` → new `PlanRole` enum with 5 roles (Researcher, Ideator, Designer, Developer, Spec Author). Add role selection modal shown on plan entry and new-tab. Persist conversations to `.budahade/conversations/` for cross-tab injection. Add Conductor-style action buttons (Approve/Edit/Hand off) to `PlanChatView`. Spec versioning via numbered files in `.budahade/specs/`. Task archive in sidebar.

**Tech Stack:** Swift, SwiftUI, Foundation (JSON Codable), existing CLISubprocessManager + AgentSession infrastructure

---

### Task 1: Extend PlanRole to Replace AgentMode for Plan Tabs

**Files:**
- Modify: `BudahADE/Agent/AgentMode.swift`
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Modify: `BudahADE/Plan/AgentPrompts.swift`
- Test: `BudahADETests/PlanRoleTests.swift`

The existing `AgentMode` enum has 4 cases (claude, researcher, ideator, developer). We need to extend it with `designer` and `specAuthor` cases, and add properties needed for Plan mode role selection.

- [ ] **Step 1: Write failing tests for new roles**

```swift
// BudahADETests/PlanRoleTests.swift
import XCTest
@testable import BudahADE

final class PlanRoleTests: XCTestCase {
    func testAllPlanRolesExist() {
        let planRoles: [AgentMode] = [.researcher, .ideator, .designer, .developer, .specAuthor]
        XCTAssertEqual(planRoles.count, 5)
    }

    func testDesignerProperties() {
        let mode = AgentMode.designer
        XCTAssertEqual(mode.displayName, "Designer")
        XCTAssertEqual(mode.defaultChatModel, .opus)
        XCTAssertFalse(mode.chatAllowedTools.isEmpty)
        XCTAssertNotNil(mode.chatMaxTurns)
    }

    func testSpecAuthorProperties() {
        let mode = AgentMode.specAuthor
        XCTAssertEqual(mode.displayName, "Spec Author")
        XCTAssertEqual(mode.defaultChatModel, .opus)
        XCTAssertTrue(mode.chatAllowedTools.contains("Write"))
        XCTAssertNil(mode.chatMaxTurns) // Spec author needs unlimited turns
    }

    func testKeyboardShortcuts() {
        XCTAssertEqual(AgentMode.researcher.roleShortcutIndex, 1)
        XCTAssertEqual(AgentMode.ideator.roleShortcutIndex, 2)
        XCTAssertEqual(AgentMode.designer.roleShortcutIndex, 3)
        XCTAssertEqual(AgentMode.developer.roleShortcutIndex, 4)
        XCTAssertEqual(AgentMode.specAuthor.roleShortcutIndex, 5)
    }

    func testPlanRolesExcludesClaude() {
        // .claude is for raw CLI, not a plan role
        XCTAssertFalse(AgentMode.planRoles.contains(.claude))
        XCTAssertEqual(AgentMode.planRoles.count, 5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanRoleTests -quiet 2>&1 | tail -20`
Expected: Compilation errors — `designer`, `specAuthor`, `roleShortcutIndex`, `planRoles` don't exist yet

- [ ] **Step 3: Add designer and specAuthor cases to AgentMode**

In `BudahADE/Agent/AgentMode.swift`, add the two new cases and extend all computed properties:

```swift
enum AgentMode: String, CaseIterable, Codable {
    case claude
    case researcher
    case ideator
    case designer
    case developer
    case specAuthor

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .researcher: return "Researcher"
        case .ideator: return "Ideator"
        case .designer: return "Designer"
        case .developer: return "Developer"
        case .specAuthor: return "Spec Author"
        }
    }

    var description: String {
        switch self {
        case .claude: return "Raw CLI — all tools"
        case .researcher: return "Deep dives, web search, API docs, codebase patterns"
        case .ideator: return "Strategic thinking, trade-off analysis, approach exploration"
        case .designer: return "UI/UX decisions, component structure, interaction patterns"
        case .developer: return "Architecture, feasibility, code-level design"
        case .specAuthor: return "Synthesizes findings into a unified spec"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "terminal"
        case .researcher: return "magnifyingglass"
        case .ideator: return "lightbulb"
        case .designer: return "paintbrush"
        case .developer: return "hammer"
        case .specAuthor: return "doc.text"
        }
    }

    var dotColor: Color {
        switch self {
        case .claude: return .white
        case .researcher: return .blue
        case .ideator: return .purple
        case .designer: return .pink
        case .developer: return .green
        case .specAuthor: return .orange
        }
    }

    var defaultChatModel: AgentModel {
        switch self {
        case .claude, .researcher, .developer: return .sonnet
        case .ideator, .designer, .specAuthor: return .opus
        }
    }

    var chatAllowedTools: [String] {
        switch self {
        case .claude: return [] // empty = all tools
        case .researcher: return ["WebSearch", "WebFetch", "Read", "Glob", "Grep"]
        case .ideator: return ["Read", "Glob", "Grep"]
        case .designer: return ["Read", "Glob", "Grep"]
        case .developer: return ["Read", "Glob", "Grep", "Edit", "Write", "Bash"]
        case .specAuthor: return ["Read", "Glob", "Grep", "Write"]
        }
    }

    var chatMaxTurns: Int? {
        switch self {
        case .claude, .specAuthor: return nil
        case .researcher, .developer: return 10
        case .ideator, .designer: return 5
        }
    }

    /// Keyboard shortcut index for role selection modal (1-based)
    var roleShortcutIndex: Int? {
        switch self {
        case .researcher: return 1
        case .ideator: return 2
        case .designer: return 3
        case .developer: return 4
        case .specAuthor: return 5
        case .claude: return nil
        }
    }

    /// Roles available in Plan mode (excludes raw .claude)
    static var planRoles: [AgentMode] {
        [.researcher, .ideator, .designer, .developer, .specAuthor]
    }
}
```

- [ ] **Step 4: Update AgentPrompts.swift system prompts for new roles**

In `BudahADE/Plan/AgentPrompts.swift`, add cases to `systemPrompt()` for `.designer` and `.specAuthor`:

```swift
// Inside systemPrompt() switch:
case .designer:
    return """
    You are a UI/UX Designer. \(taskContext)
    Focus on user experience, component structure, interaction patterns, visual hierarchy, and accessibility.
    When analyzing code, evaluate it from the user's perspective — what's intuitive, what's confusing, what's missing.
    Present design decisions as options with trade-offs. Use sketches (ASCII/text) when helpful.
    Be opinionated — recommend the better option and explain why.
    \(specBlock)
    """

case .specAuthor:
    return """
    You are a Spec Author — your job is to synthesize findings from planning conversations into a clear, actionable specification document.
    \(taskContext)

    Your workflow:
    1. Review the context from sibling conversations (research findings, design decisions, architectural proposals)
    2. Present the spec ONE SECTION AT A TIME for user review
    3. For each section, ask "Does this look right?" before moving to the next
    4. Once all sections are approved, assemble the full document
    5. Present the complete spec for final review

    Spec format: Problem statement, goals, architecture, components, data flow, edge cases, implementation checklist.
    Be concise. Every sentence should earn its place. Remove fluff.
    \(specBlock)
    """
```

- [ ] **Step 5: Update PlanChatState to store role**

In `BudahADE/Plan/PlanChatState.swift`, add a `role` property:

```swift
// Add to PlanChatState properties (after line 20):
let role: AgentMode

// Update init to accept role:
init(worktreePath: String, taskName: String, branchName: String, role: AgentMode = .researcher) {
    self.worktreePath = worktreePath
    self.taskName = taskName
    self.branchName = branchName
    self.role = role
    self.selectedModel = role.defaultChatModel
}
```

Update `plannerSystemPrompt()` to delegate to `AgentPrompts.systemPrompt()` using `self.role` instead of hardcoding the planner prompt.

- [ ] **Step 6: Update PlanTabInfo to store role**

In `BudahADE/Plan/PlanTabInfo.swift`, add role to the struct:

```swift
struct PlanTabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var status: PlanTabStatus
    let role: AgentMode  // New: which role this tab represents
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanRoleTests -quiet 2>&1 | tail -20`
Expected: All 4 tests PASS

- [ ] **Step 8: Fix any compilation errors in files referencing AgentMode**

Check all callers of `AgentMode` that use exhaustive switches — they'll need new cases for `.designer` and `.specAuthor`. Fix each one.

- [ ] **Step 9: Commit**

```bash
git add BudahADE/Agent/AgentMode.swift BudahADE/Plan/AgentPrompts.swift BudahADE/Plan/PlanChatState.swift BudahADE/Plan/PlanTabInfo.swift BudahADETests/PlanRoleTests.swift
git commit -m "feat: add Designer and Spec Author roles to AgentMode for Plan mode V2"
```

---

### Task 2: Role Selection Modal

**Files:**
- Create: `BudahADE/Plan/RoleSelectionModal.swift`
- Modify: `BudahADE/Plan/PlanTabBar.swift`
- Modify: `BudahADE/Task/TaskState.swift`
- Modify: `BudahADE/Workspace/WorkspaceView.swift`

Build the modal that appears when Plan mode opens with no tabs and when creating a new tab. Numbered shortcuts (1-5) for keyboard selection.

- [ ] **Step 1: Write failing test for role selection**

```swift
// BudahADETests/PlanRoleTests.swift (append to existing file)
final class RoleSelectionTests: XCTestCase {
    func testCreatePlanTabWithRole() {
        // TaskState.createPlanTab should now require a role
        let task = TaskState(
            name: "test-task",
            worktreePath: "/tmp/test",
            branchName: "test-branch"
        )
        let tabId = task.createPlanTab(role: .researcher)
        XCTAssertNotNil(task.planChats[tabId])
        XCTAssertEqual(task.planChats[tabId]?.role, .researcher)
        XCTAssertEqual(task.planTabs.first?.role, .researcher)
        XCTAssertEqual(task.planTabs.first?.title, "Researcher")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/RoleSelectionTests -quiet 2>&1 | tail -20`
Expected: FAIL — `createPlanTab(role:)` signature doesn't exist

- [ ] **Step 3: Update TaskState.createPlanTab to accept role**

In `BudahADE/Task/TaskState.swift`, update `createPlanTab()`:

```swift
@discardableResult
func createPlanTab(role: AgentMode = .researcher) -> UUID {
    let id = UUID()
    let chatState = PlanChatState(
        worktreePath: worktreePath,
        taskName: name,
        branchName: branchName,
        role: role
    )
    planChats[id] = chatState
    planTabs.append(PlanTabInfo(
        id: id,
        title: role.displayName,
        status: .idle,
        role: role
    ))
    selectedPlanTabId = id
    observePlanChatStatus(chatState, tabId: id)
    return id
}
```

Update `enterPlanMode()` to NOT auto-create a tab — let the modal handle it:

```swift
func enterPlanMode() {
    mode = .plan
    // Don't auto-create tab; modal will handle role selection
    // Only create if returning to plan mode with existing tabs
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/RoleSelectionTests -quiet 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Create RoleSelectionModal view**

```swift
// BudahADE/Plan/RoleSelectionModal.swift
import SwiftUI

struct RoleSelectionModal: View {
    let onSelect: (AgentMode) -> Void
    @State private var hoveredRole: AgentMode?

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a role")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(AgentMode.planRoles, id: \.self) { role in
                    RoleOptionRow(
                        role: role,
                        isHovered: hoveredRole == role,
                        onSelect: { onSelect(role) }
                    )
                    .onHover { hovering in
                        hoveredRole = hovering ? role : nil
                    }
                }
            }

            Text("Press 1–\(AgentMode.planRoles.count) to select")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = Int(press.characters.first.map(String.init) ?? ""),
                  digit >= 1, digit <= AgentMode.planRoles.count else {
                return .ignored
            }
            onSelect(AgentMode.planRoles[digit - 1])
            return .handled
        }
    }
}

struct RoleOptionRow: View {
    let role: AgentMode
    let isHovered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text("\(role.roleShortcutIndex ?? 0)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Image(systemName: role.iconName)
                    .foregroundStyle(role.dotColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role.displayName)
                        .font(.body.weight(.medium))
                    Text(role.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 6: Wire modal into WorkspaceView**

In `BudahADE/Workspace/WorkspaceView.swift`, update the plan mode rendering to show the modal when no tabs exist:

```swift
if let task = state.activeTask, task.mode == .plan {
    VStack(spacing: 0) {
        if task.planTabs.isEmpty {
            // No tabs yet — show role selection
            RoleSelectionModal { role in
                task.createPlanTab(role: role)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlanTabBar(
                selectedTabID: Binding(
                    get: { task.selectedPlanTabId },
                    set: { task.selectPlanTab($0 ?? task.planTabs[0].id) }
                ),
                tabs: task.planTabs,
                onSelectTab: { task.selectPlanTab($0) },
                onCloseTab: { task.closePlanTab($0) },
                onNewTab: { showRoleModal = true }
            )
            if let planChat = task.activePlanChat {
                PlanChatView(state: planChat)
            }
        }
    }
    .sheet(isPresented: $showRoleModal) {
        RoleSelectionModal { role in
            task.createPlanTab(role: role)
            showRoleModal = false
        }
    }
}
```

Add `@State private var showRoleModal = false` to `WorkspaceView`.

- [ ] **Step 7: Update PlanTabBar to show role badge**

In `BudahADE/Plan/PlanTabBar.swift`, pass the role's `dotColor` and `iconName` to `ConversationTab` so each tab shows its role identity.

- [ ] **Step 8: Update new-tab notification handler**

In `WorkspaceView`, update `.newTerminalTab` handler to show the role modal instead of directly creating a tab:

```swift
.onReceive(NotificationCenter.default.publisher(for: .newTerminalTab)) { _ in
    if let task = state.activeTask {
        if task.mode == .plan {
            showRoleModal = true
        } else {
            task.createTab()
        }
    }
}
```

- [ ] **Step 9: Commit**

```bash
git add BudahADE/Plan/RoleSelectionModal.swift BudahADE/Plan/PlanTabBar.swift BudahADE/Task/TaskState.swift BudahADE/Workspace/WorkspaceView.swift BudahADETests/PlanRoleTests.swift
git commit -m "feat: add role selection modal for Plan mode tab creation"
```

---

### Task 3: Conversation Persistence

**Files:**
- Create: `BudahADE/Plan/PlanConversationPersistence.swift`
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Modify: `BudahADE/Agent/AgentSession.swift`
- Test: `BudahADETests/PlanConversationPersistenceTests.swift`

Auto-persist each tab's conversation to `.budahade/conversations/{tabId}.json` as messages accumulate. This is the foundation for cross-tab context injection (Task 4).

- [ ] **Step 1: Write failing tests for conversation persistence**

```swift
// BudahADETests/PlanConversationPersistenceTests.swift
import XCTest
@testable import BudahADE

final class PlanConversationPersistenceTests: XCTestCase {
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("budahade-test-\(UUID().uuidString)")
        .path

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            atPath: testDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testSaveConversation() {
        let tabId = UUID()
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "Hello", toolCalls: nil,
                       timestamp: Date(), inputTokens: 10, outputTokens: 0),
            ChatMessage(id: UUID(), role: .assistant, content: "Hi there", toolCalls: nil,
                       timestamp: Date(), inputTokens: 0, outputTokens: 15),
        ]

        let snapshot = ConversationSnapshot(
            tabId: tabId,
            role: .researcher,
            messages: messages
        )

        PlanConversationPersistence.save(snapshot, to: testDir)

        let path = "\(testDir)/.budahade/conversations/\(tabId.uuidString).json"
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testLoadConversation() {
        let tabId = UUID()
        let messages: [ChatMessage] = [
            ChatMessage(id: UUID(), role: .user, content: "Research APIs", toolCalls: nil,
                       timestamp: Date(), inputTokens: 10, outputTokens: 0),
            ChatMessage(id: UUID(), role: .assistant, content: "Found 3 options", toolCalls: nil,
                       timestamp: Date(), inputTokens: 0, outputTokens: 50),
        ]

        let snapshot = ConversationSnapshot(tabId: tabId, role: .researcher, messages: messages)
        PlanConversationPersistence.save(snapshot, to: testDir)

        let loaded = PlanConversationPersistence.load(tabId: tabId, from: testDir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.messages.count, 2)
        XCTAssertEqual(loaded?.role, .researcher)
        XCTAssertEqual(loaded?.messages[0].content, "Research APIs")
    }

    func testLoadAllConversations() {
        let tab1 = UUID()
        let tab2 = UUID()

        PlanConversationPersistence.save(
            ConversationSnapshot(tabId: tab1, role: .researcher, messages: [
                ChatMessage(id: UUID(), role: .user, content: "q1", toolCalls: nil,
                           timestamp: Date(), inputTokens: 5, outputTokens: 0)
            ]),
            to: testDir
        )
        PlanConversationPersistence.save(
            ConversationSnapshot(tabId: tab2, role: .ideator, messages: [
                ChatMessage(id: UUID(), role: .user, content: "q2", toolCalls: nil,
                           timestamp: Date(), inputTokens: 5, outputTokens: 0)
            ]),
            to: testDir
        )

        let all = PlanConversationPersistence.loadAll(from: testDir)
        XCTAssertEqual(all.count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanConversationPersistenceTests -quiet 2>&1 | tail -20`
Expected: Compilation error — `ConversationSnapshot` and `PlanConversationPersistence` don't exist

- [ ] **Step 3: Implement PlanConversationPersistence**

```swift
// BudahADE/Plan/PlanConversationPersistence.swift
import Foundation

struct ConversationSnapshot: Codable {
    let tabId: UUID
    let role: AgentMode
    let messages: [ChatMessage]
}

enum PlanConversationPersistence {
    private static let directoryName = "conversations"

    static func save(_ snapshot: ConversationSnapshot, to worktreePath: String) {
        let dir = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("\(snapshot.tabId.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load(tabId: UUID, from worktreePath: String) -> ConversationSnapshot? {
        let fileURL = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent(directoryName)
            .appendingPathComponent("\(tabId.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ConversationSnapshot.self, from: data)
    }

    static func loadAll(from worktreePath: String) -> [ConversationSnapshot] {
        let dir = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent(directoryName)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(ConversationSnapshot.self, from: $0) }
    }

    static func loadAllExcluding(tabId: UUID, from worktreePath: String) -> [ConversationSnapshot] {
        loadAll(from: worktreePath).filter { $0.tabId != tabId }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanConversationPersistenceTests -quiet 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Wire auto-persistence into PlanChatState**

In `BudahADE/Plan/PlanChatState.swift`, add debounced persistence. Observe `plannerSession?.messages` and save after changes:

```swift
// Add property:
private var persistenceTask: Task<Void, Never>?

// Add method:
func persistConversation() {
    persistenceTask?.cancel()
    persistenceTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(1)) // debounce
        guard !Task.isCancelled else { return }
        guard let session = plannerSession else { return }
        let snapshot = ConversationSnapshot(
            tabId: session.id,
            role: self.role,
            messages: session.messages
        )
        PlanConversationPersistence.save(snapshot, to: worktreePath)
    }
}
```

Call `persistConversation()` at the end of `sendMessage()` and also observe session message changes to trigger persistence after assistant responses complete.

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/PlanConversationPersistence.swift BudahADE/Plan/PlanChatState.swift BudahADETests/PlanConversationPersistenceTests.swift
git commit -m "feat: add conversation persistence to .budahade/conversations/ with debounced auto-save"
```

---

### Task 4: Cross-Tab Context Injection

**Files:**
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Modify: `BudahADE/Plan/AgentPrompts.swift`
- Test: `BudahADETests/CrossTabContextTests.swift`

When a new tab launches, inject sibling conversation histories into its system prompt. Uses the persistence layer from Task 3.

- [ ] **Step 1: Write failing tests for context assembly**

```swift
// BudahADETests/CrossTabContextTests.swift
import XCTest
@testable import BudahADE

final class CrossTabContextTests: XCTestCase {
    func testSiblingContextBlock() {
        let siblings: [ConversationSnapshot] = [
            ConversationSnapshot(
                tabId: UUID(),
                role: .researcher,
                messages: [
                    ChatMessage(id: UUID(), role: .user, content: "Research auth patterns",
                               toolCalls: nil, timestamp: Date(), inputTokens: 10, outputTokens: 0),
                    ChatMessage(id: UUID(), role: .assistant, content: "Found OAuth2 and SAML options",
                               toolCalls: nil, timestamp: Date(), inputTokens: 0, outputTokens: 50),
                ]
            ),
            ConversationSnapshot(
                tabId: UUID(),
                role: .ideator,
                messages: [
                    ChatMessage(id: UUID(), role: .user, content: "Which approach?",
                               toolCalls: nil, timestamp: Date(), inputTokens: 8, outputTokens: 0),
                    ChatMessage(id: UUID(), role: .assistant, content: "OAuth2 is simpler for our case",
                               toolCalls: nil, timestamp: Date(), inputTokens: 0, outputTokens: 30),
                ]
            ),
        ]

        let context = AgentPrompts.siblingContextBlock(from: siblings)

        XCTAssertTrue(context.contains("## Context from other planning conversations"))
        XCTAssertTrue(context.contains("### Researcher"))
        XCTAssertTrue(context.contains("Found OAuth2 and SAML options"))
        XCTAssertTrue(context.contains("### Ideator"))
        XCTAssertTrue(context.contains("OAuth2 is simpler"))
    }

    func testEmptySiblingsProducesEmptyBlock() {
        let context = AgentPrompts.siblingContextBlock(from: [])
        XCTAssertTrue(context.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/CrossTabContextTests -quiet 2>&1 | tail -20`
Expected: FAIL — `siblingContextBlock` doesn't exist

- [ ] **Step 3: Implement siblingContextBlock in AgentPrompts**

In `BudahADE/Plan/AgentPrompts.swift`, add:

```swift
static func siblingContextBlock(from siblings: [ConversationSnapshot]) -> String {
    guard !siblings.isEmpty else { return "" }

    var block = "\n## Context from other planning conversations\n"

    for sibling in siblings {
        block += "\n### \(sibling.role.displayName)\n"
        for message in sibling.messages {
            let prefix = message.role == .user ? "**User:**" : "**\(sibling.role.displayName):**"
            block += "\(prefix) \(message.content)\n\n"
        }
    }

    return block
}
```

- [ ] **Step 4: Wire sibling context into PlanChatState.ensureSession()**

In `PlanChatState.ensureSession()`, before creating the session, load sibling conversations and append to the system prompt:

```swift
func ensureSession() -> AgentSession {
    if let existing = plannerSession { return existing }

    // Load sibling conversations for context injection
    let siblings = PlanConversationPersistence.loadAllExcluding(
        tabId: sessionTabId,
        from: worktreePath
    )
    let siblingContext = AgentPrompts.siblingContextBlock(from: siblings)
    let prompt = roleSystemPrompt() + siblingContext

    let session = chatManager.createSession(
        model: selectedModel,
        agentMode: role,
        systemPrompt: prompt,
        workingDirectory: worktreePath,
        enableAgentTeams: true,
        disableMcp: true
    )
    plannerSession = session
    return session
}
```

Add `let sessionTabId: UUID` property to `PlanChatState`, set during init.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/CrossTabContextTests -quiet 2>&1 | tail -20`
Expected: All 2 tests PASS

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/AgentPrompts.swift BudahADE/Plan/PlanChatState.swift BudahADETests/CrossTabContextTests.swift
git commit -m "feat: inject sibling conversation context into new plan tab system prompts"
```

---

### Task 5: Action Buttons (Approve / Edit / Hand off)

**Files:**
- Create: `BudahADE/Plan/PlanActionButtons.swift`
- Modify: `BudahADE/Plan/PlanChatView.swift`
- Create: `BudahADE/Plan/SpecVersionManager.swift`
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Test: `BudahADETests/SpecVersionManagerTests.swift`

Add Conductor-style action buttons above the text input. Approve writes spec to disk, Edit triggers conversational refinement, Hand off sends output to another tab.

- [ ] **Step 1: Write failing tests for spec version manager**

```swift
// BudahADETests/SpecVersionManagerTests.swift
import XCTest
@testable import BudahADE

final class SpecVersionManagerTests: XCTestCase {
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("budahade-test-\(UUID().uuidString)")
        .path

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            atPath: testDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testApproveCreatesVersionedSpec() {
        let content = "# My Spec\n\n## Architecture\nUse REST API"

        let version = SpecVersionManager.approve(content: content, in: testDir)

        XCTAssertEqual(version, 1)
        let specPath = "\(testDir)/.budahade/specs/spec-v1.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: specPath))

        let activePath = "\(testDir)/.budahade/spec.md"
        XCTAssertTrue(FileManager.default.fileExists(atPath: activePath))

        let activeContent = try? String(contentsOfFile: activePath)
        XCTAssertEqual(activeContent, content)
    }

    func testMultipleApprovalsIncrement() {
        SpecVersionManager.approve(content: "v1 content", in: testDir)
        let v2 = SpecVersionManager.approve(content: "v2 content", in: testDir)

        XCTAssertEqual(v2, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: "\(testDir)/.budahade/specs/spec-v1.md"
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: "\(testDir)/.budahade/specs/spec-v2.md"
        ))

        let active = try? String(contentsOfFile: "\(testDir)/.budahade/spec.md")
        XCTAssertEqual(active, "v2 content")
    }

    func testListVersions() {
        SpecVersionManager.approve(content: "v1", in: testDir)
        SpecVersionManager.approve(content: "v2", in: testDir)

        let versions = SpecVersionManager.listVersions(in: testDir)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, 1)
        XCTAssertEqual(versions[1].version, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/SpecVersionManagerTests -quiet 2>&1 | tail -20`
Expected: FAIL — `SpecVersionManager` doesn't exist

- [ ] **Step 3: Implement SpecVersionManager**

```swift
// BudahADE/Plan/SpecVersionManager.swift
import Foundation

struct SpecVersion {
    let version: Int
    let path: String
    let content: String
}

enum SpecVersionManager {
    private static let specsDir = "specs"

    @discardableResult
    static func approve(content: String, in worktreePath: String) -> Int {
        let budahDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".budahade")
        let specsURL = budahDir.appendingPathComponent(specsDir)
        try? FileManager.default.createDirectory(at: specsURL, withIntermediateDirectories: true)

        // Determine next version number
        let existing = listVersions(in: worktreePath)
        let nextVersion = (existing.last?.version ?? 0) + 1

        // Write versioned copy
        let versionFile = specsURL.appendingPathComponent("spec-v\(nextVersion).md")
        try? content.write(to: versionFile, atomically: true, encoding: .utf8)

        // Write active spec
        let activeFile = budahDir.appendingPathComponent("spec.md")
        try? content.write(to: activeFile, atomically: true, encoding: .utf8)

        return nextVersion
    }

    static func listVersions(in worktreePath: String) -> [SpecVersion] {
        let specsURL = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent(specsDir)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: specsURL, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.lastPathComponent.hasPrefix("spec-v") && $0.pathExtension == "md" }
            .compactMap { url -> SpecVersion? in
                let name = url.deletingPathExtension().lastPathComponent
                guard let vStr = name.split(separator: "v").last,
                      let version = Int(vStr),
                      let content = try? String(contentsOf: url) else { return nil }
                return SpecVersion(version: version, path: url.path, content: content)
            }
            .sorted { $0.version < $1.version }
    }

    static func activeSpec(in worktreePath: String) -> String? {
        let path = URL(fileURLWithPath: worktreePath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent("spec.md")
        return try? String(contentsOf: path)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/SpecVersionManagerTests -quiet 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Create PlanActionButtons view**

```swift
// BudahADE/Plan/PlanActionButtons.swift
import SwiftUI

struct PlanActionButtons: View {
    let onApprove: () -> Void
    let onEdit: () -> Void
    let onHandOff: () -> Void
    let siblingTabs: [PlanTabInfo]
    @State private var showHandOffPicker = false

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.06), in: Capsule())

            Button(action: {
                if siblingTabs.isEmpty {
                    onHandOff()
                } else {
                    showHandOffPicker = true
                }
            }) {
                Label("Hand off", systemImage: "arrowshape.turn.up.right")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.06), in: Capsule())
            .popover(isPresented: $showHandOffPicker) {
                HandOffTargetPicker(
                    tabs: siblingTabs,
                    onSelect: { _ in
                        showHandOffPicker = false
                        onHandOff()
                    }
                )
            }

            Button(action: onApprove) {
                Label("Approve", systemImage: "checkmark")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

struct HandOffTargetPicker: View {
    let tabs: [PlanTabInfo]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Send to...")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            ForEach(tabs) { tab in
                Button {
                    onSelect(tab.id)
                } label: {
                    HStack {
                        Image(systemName: tab.role.iconName)
                            .foregroundStyle(tab.role.dotColor)
                        Text(tab.title)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(minWidth: 180)
    }
}
```

- [ ] **Step 6: Wire action buttons into PlanChatView**

In `BudahADE/Plan/PlanChatView.swift`, add `PlanActionButtons` above the text input area. The buttons should appear when the conversation has at least one assistant message:

```swift
// Above the existing input area, add:
if let session = state.plannerSession, !session.messages.isEmpty {
    PlanActionButtons(
        onApprove: { handleApprove() },
        onEdit: { handleEdit() },
        onHandOff: { handleHandOff() },
        siblingTabs: siblingTabs
    )
}
```

Implement the action handlers in `PlanChatView`:

```swift
private func handleApprove() {
    guard let session = state.plannerSession,
          let lastAssistant = session.messages.last(where: { $0.role == .assistant }) else { return }
    let version = SpecVersionManager.approve(content: lastAssistant.content, in: state.worktreePath)
    // Send system message confirming
    state.sendMessage("Spec approved and saved as version \(version).")
}

private func handleEdit() {
    state.sendMessage("[Edit requested] What would you like to change about the above?")
}

private func handleHandOff() {
    // Implementation: inject last assistant message into target tab's next system prompt
    // This will be wired via PlanChatState.receiveHandOff()
}
```

- [ ] **Step 7: Add receiveHandOff to PlanChatState**

In `BudahADE/Plan/PlanChatState.swift`, add:

```swift
/// Content handed off from another tab
@Published var handedOffContext: [(role: AgentMode, content: String)] = []

func receiveHandOff(from role: AgentMode, content: String) {
    handedOffContext.append((role: role, content: content))
}
```

Include `handedOffContext` in the system prompt when building it — after sibling context, add a "## Handed-off context (weighted)" section.

- [ ] **Step 8: Wire Hand off action through TaskState**

In `TaskState`, add a method to route hand-offs between tabs:

```swift
func handOff(from sourceTabId: UUID, to targetTabId: UUID) {
    guard let sourceChat = planChats[sourceTabId],
          let targetChat = planChats[targetTabId],
          let sourceSession = sourceChat.plannerSession,
          let lastAssistant = sourceSession.messages.last(where: { $0.role == .assistant }) else { return }

    targetChat.receiveHandOff(from: sourceChat.role, content: lastAssistant.content)
}
```

- [ ] **Step 9: Commit**

```bash
git add BudahADE/Plan/PlanActionButtons.swift BudahADE/Plan/SpecVersionManager.swift BudahADE/Plan/PlanChatView.swift BudahADE/Plan/PlanChatState.swift BudahADE/Task/TaskState.swift BudahADETests/SpecVersionManagerTests.swift
git commit -m "feat: add Approve/Edit/Hand off action buttons with spec versioning"
```

---

### Task 6: Plan↔Build Bridge

**Files:**
- Modify: `BudahADE/Plan/AgentPrompts.swift`
- Modify: `BudahADE/Task/TaskState.swift`
- Modify: `BudahADE/Plan/PlanChatState.swift`
- Test: `BudahADETests/PlanBuildBridgeTests.swift`

When switching from Build back to Plan, inject build context (git diffs, completed spec items, agent output) into new plan tabs.

- [ ] **Step 1: Write failing tests for build context assembly**

```swift
// BudahADETests/PlanBuildBridgeTests.swift
import XCTest
@testable import BudahADE

final class PlanBuildBridgeTests: XCTestCase {
    let testDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("budahade-test-\(UUID().uuidString)")
        .path

    override func setUp() {
        super.setUp()
        let budahDir = "\(testDir)/.budahade"
        try? FileManager.default.createDirectory(
            atPath: budahDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testDir)
        super.tearDown()
    }

    func testBuildContextBlockWithSpec() {
        // Write a spec with some completed items
        let spec = """
        # Spec
        - [x] Setup project
        - [x] Add auth
        - [ ] Add dashboard
        - [ ] Add tests
        """
        let specPath = "\(testDir)/.budahade/spec.md"
        try? spec.write(toFile: specPath, atomically: true, encoding: .utf8)

        let context = AgentPrompts.buildContextBlock(worktreePath: testDir)

        XCTAssertTrue(context.contains("## Build Progress"))
        XCTAssertTrue(context.contains("2 of 4 tasks completed"))
    }

    func testBuildContextBlockWithAgentOutput() {
        let outputDir = "\(testDir)/.budahade/agent-output"
        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true
        )
        try? "Built auth module successfully".write(
            toFile: "\(outputDir)/builder-1.md",
            atomically: true, encoding: .utf8
        )

        let context = AgentPrompts.buildContextBlock(worktreePath: testDir)
        XCTAssertTrue(context.contains("Built auth module"))
    }

    func testEmptyBuildContextWhenNoBuildHistory() {
        let context = AgentPrompts.buildContextBlock(worktreePath: testDir)
        XCTAssertTrue(context.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanBuildBridgeTests -quiet 2>&1 | tail -20`
Expected: FAIL — `buildContextBlock` doesn't exist

- [ ] **Step 3: Implement buildContextBlock in AgentPrompts**

In `BudahADE/Plan/AgentPrompts.swift`, add:

```swift
static func buildContextBlock(worktreePath: String) -> String {
    let budahDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".budahade")
    var sections: [String] = []

    // Check spec progress
    let specURL = budahDir.appendingPathComponent("spec.md")
    if let spec = try? String(contentsOf: specURL) {
        let completed = spec.components(separatedBy: "\n")
            .filter { $0.contains("- [x]") }.count
        let total = spec.components(separatedBy: "\n")
            .filter { $0.contains("- [x]") || $0.contains("- [ ]") }.count
        if total > 0 {
            sections.append("### Spec Progress\n\(completed) of \(total) tasks completed\n")

            // List what's done and what's remaining
            let items = spec.components(separatedBy: "\n")
                .filter { $0.contains("- [x]") || $0.contains("- [ ]") }
            sections.append(items.joined(separator: "\n"))
        }
    }

    // Check agent output
    let outputDir = budahDir.appendingPathComponent("agent-output")
    if let files = try? FileManager.default.contentsOfDirectory(
        at: outputDir, includingPropertiesForKeys: nil
    ) {
        let outputs = files
            .filter { $0.pathExtension == "md" }
            .compactMap { try? String(contentsOf: $0) }
        if !outputs.isEmpty {
            sections.append("### Agent Output\n" + outputs.joined(separator: "\n---\n"))
        }
    }

    guard !sections.isEmpty else { return "" }
    return "\n## Build Progress\n\n" + sections.joined(separator: "\n\n")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PlanBuildBridgeTests -quiet 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Wire build context into plan tab creation**

In `PlanChatState.ensureSession()`, after sibling context, also append build context:

```swift
let buildContext = AgentPrompts.buildContextBlock(worktreePath: worktreePath)
let prompt = roleSystemPrompt() + siblingContext + buildContext
```

This means any plan tab created mid-build automatically knows what's happened.

- [ ] **Step 6: Update TaskState.enterPlanMode for mid-build return**

In `TaskState.enterPlanMode()`, if returning from build mode, don't clear existing plan tabs:

```swift
func enterPlanMode() {
    mode = .plan
    // Plan tabs persist — they're still here from before build mode
    // New tabs created from here will get build context injected automatically
}
```

- [ ] **Step 7: Commit**

```bash
git add BudahADE/Plan/AgentPrompts.swift BudahADE/Plan/PlanChatState.swift BudahADE/Task/TaskState.swift BudahADETests/PlanBuildBridgeTests.swift
git commit -m "feat: inject build progress context when returning to Plan mode mid-build"
```

---

### Task 7: Task Archive

**Files:**
- Create: `BudahADE/Task/TaskArchive.swift`
- Create: `BudahADE/Task/TaskArchiveView.swift`
- Modify: `BudahADE/Workspace/WorkspaceState.swift`
- Modify: `BudahADE/Workspace/WorkspaceView.swift` (sidebar)
- Test: `BudahADETests/TaskArchiveTests.swift`

Add "Task Archive" button to sidebar. Completed tasks move to archive with all data preserved.

- [ ] **Step 1: Write failing tests for task archive**

```swift
// BudahADETests/TaskArchiveTests.swift
import XCTest
@testable import BudahADE

final class TaskArchiveTests: XCTestCase {
    func testArchiveTask() {
        let archive = TaskArchive()
        let snapshot = ArchivedTask(
            name: "auth-feature",
            branchName: "feature/auth",
            worktreePath: "/tmp/auth",
            completedAt: Date(),
            specVersionCount: 2,
            conversationCount: 3
        )

        archive.add(snapshot)
        XCTAssertEqual(archive.tasks.count, 1)
        XCTAssertEqual(archive.tasks[0].name, "auth-feature")
    }

    func testArchivePersistence() {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-test-\(UUID().uuidString)")
            .path
        try? FileManager.default.createDirectory(
            atPath: testDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let archive = TaskArchive()
        archive.add(ArchivedTask(
            name: "test-task",
            branchName: "test",
            worktreePath: "/tmp/test",
            completedAt: Date(),
            specVersionCount: 1,
            conversationCount: 2
        ))

        TaskArchive.save(archive, to: testDir)

        let loaded = TaskArchive.load(from: testDir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tasks.count, 1)
        XCTAssertEqual(loaded?.tasks[0].name, "test-task")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/TaskArchiveTests -quiet 2>&1 | tail -20`
Expected: FAIL — `TaskArchive` and `ArchivedTask` don't exist

- [ ] **Step 3: Implement TaskArchive model**

```swift
// BudahADE/Task/TaskArchive.swift
import Foundation

struct ArchivedTask: Codable, Identifiable {
    let id: UUID
    let name: String
    let branchName: String
    let worktreePath: String
    let completedAt: Date
    let specVersionCount: Int
    let conversationCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        branchName: String,
        worktreePath: String,
        completedAt: Date,
        specVersionCount: Int,
        conversationCount: Int
    ) {
        self.id = id
        self.name = name
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.completedAt = completedAt
        self.specVersionCount = specVersionCount
        self.conversationCount = conversationCount
    }
}

class TaskArchive: ObservableObject, Codable {
    @Published var tasks: [ArchivedTask] = []

    enum CodingKeys: CodingKey {
        case tasks
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([ArchivedTask].self, forKey: .tasks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tasks, forKey: .tasks)
    }

    func add(_ task: ArchivedTask) {
        tasks.insert(task, at: 0) // newest first
    }

    static func save(_ archive: TaskArchive, to projectPath: String) {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent("task-archive.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(archive) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(from projectPath: String) -> TaskArchive? {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".budahade")
            .appendingPathComponent("task-archive.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TaskArchive.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/TaskArchiveTests -quiet 2>&1 | tail -20`
Expected: All 2 tests PASS

- [ ] **Step 5: Create TaskArchiveView**

```swift
// BudahADE/Task/TaskArchiveView.swift
import SwiftUI

struct TaskArchiveView: View {
    @ObservedObject var archive: TaskArchive
    let onReopen: (ArchivedTask) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Task Archive")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            if archive.tasks.isEmpty {
                VStack {
                    Spacer()
                    Text("No archived tasks yet")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(archive.tasks) { task in
                    ArchivedTaskRow(task: task, onReopen: onReopen)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ArchivedTaskRow: View {
    let task: ArchivedTask
    let onReopen: (ArchivedTask) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 12) {
                    Label("\(task.conversationCount) conversations", systemImage: "bubble.left.and.bubble.right")
                    Label("\(task.specVersionCount) spec versions", systemImage: "doc.text")
                    Text(task.completedAt, style: .relative) + Text(" ago")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reopen") {
                onReopen(task)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.06), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 6: Wire archive into WorkspaceState**

In `BudahADE/Workspace/WorkspaceState.swift`, add:

```swift
@Published var taskArchive = TaskArchive()

func archiveTask(_ task: TaskState) {
    let specVersions = SpecVersionManager.listVersions(in: task.worktreePath)
    let conversations = PlanConversationPersistence.loadAll(from: task.worktreePath)

    let archived = ArchivedTask(
        name: task.name,
        branchName: task.branchName,
        worktreePath: task.worktreePath,
        completedAt: Date(),
        specVersionCount: specVersions.count,
        conversationCount: conversations.count
    )
    taskArchive.add(archived)
    TaskArchive.save(taskArchive, to: projectPath)

    // Remove from active tasks
    removeTask(task)
}
```

Load archive on init: `taskArchive = TaskArchive.load(from: projectPath) ?? TaskArchive()`

- [ ] **Step 7: Add "Task Archive" button to sidebar**

In the sidebar area of `WorkspaceView` (wherever the task list and "+ New Task" button are), add the archive button above "+ New Task":

```swift
Button {
    showTaskArchive = true
} label: {
    Label("Task Archive", systemImage: "archivebox")
        .font(.caption)
}
.buttonStyle(.plain)
.sheet(isPresented: $showTaskArchive) {
    TaskArchiveView(
        archive: state.taskArchive,
        onReopen: { archived in
            // Reopen task from archive
            state.reopenArchivedTask(archived)
            showTaskArchive = false
        }
    )
}
```

- [ ] **Step 8: Commit**

```bash
git add BudahADE/Task/TaskArchive.swift BudahADE/Task/TaskArchiveView.swift BudahADE/Workspace/WorkspaceState.swift BudahADE/Workspace/WorkspaceView.swift BudahADETests/TaskArchiveTests.swift
git commit -m "feat: add Task Archive with sidebar button, persistence, and reopen support"
```

---

### Task 8: Integration Wiring & Polish

**Files:**
- Modify: `BudahADE/Workspace/WorkspaceView.swift`
- Modify: `BudahADE/Task/TaskState.swift`
- Modify: `BudahADE/Plan/PlanChatView.swift`
- Modify: `BudahADE/Plan/PlanTabBar.swift`
- Modify: `BudahADE/App/BudahADEApp.swift`

Final wiring: ensure all pieces connect, keyboard shortcuts work, role badges show in tabs, and the full plan→build→plan loop functions end-to-end.

- [ ] **Step 1: Verify role badge in PlanTabBar**

Ensure `PlanTabBar` passes role info to `ConversationTab`. Each tab should show:
- Role icon (from `role.iconName`)
- Role dot color (from `role.dotColor`)
- Role name as tab title

- [ ] **Step 2: Update PlanChatView to show role context**

Add a subtle role indicator at the top of `PlanChatView` — small badge showing the current role name and icon, so the user always knows which lens they're in.

```swift
// At the top of the chat area, before messages:
HStack(spacing: 6) {
    Image(systemName: state.role.iconName)
        .foregroundStyle(state.role.dotColor)
    Text(state.role.displayName)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    Spacer()
}
.padding(.horizontal, 16)
.padding(.top, 8)
```

- [ ] **Step 3: Verify Cmd+Shift+P toggle preserves plan tabs**

Test that toggling plan↔build mode:
- Preserves all plan tabs and their conversations
- Returns to the same selected tab
- Injects build context into new plan tabs created after returning from build

- [ ] **Step 4: Verify keyboard shortcuts for role modal**

Test that pressing 1-5 in the role selection modal selects the correct role and creates a tab immediately.

- [ ] **Step 5: End-to-end flow test**

Manual test of the full loop:
1. Enter Plan mode → role modal appears
2. Select Researcher (press 1) → tab opens with Researcher prompt
3. Have a conversation → messages persist to `.budahade/conversations/`
4. Open new tab (Cmd+T) → modal appears → select Ideator (press 2)
5. Ideator tab has Researcher context in its system prompt
6. Open Spec Author tab (press 5) → has all sibling context
7. Direct spec assembly → Approve → spec written to `.budahade/spec.md` and `.budahade/specs/spec-v1.md`
8. Switch to Build mode (Cmd+Shift+P) → builder agents can read spec
9. Return to Plan mode (Cmd+Shift+P) → plan tabs still there
10. Open new tab → has build progress context

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: complete Plan Mode V2 integration wiring and polish"
```
