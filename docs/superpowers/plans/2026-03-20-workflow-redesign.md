# BudahADE Workflow Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor BudahADE from its current workspace→task→tab model to the full Projects→Tasks→Conversations workflow with agent role specialization, adaptive spec tracking, and Plan/Build mode toggle.

**Architecture:** The refactor is additive — existing terminal, git, and file tree infrastructure stays intact. We add: agent role system (system prompt files + role picker UI), spec file watcher + parser, Plan/Build mode toggle, and left panel dashboard restructuring. Each task produces a buildable, testable increment.

**Tech Stack:** Swift 5.5+, SwiftUI, libghostty, FileManager for file watching, Process for git/claude CLI

**Spec Reference:** `docs/superpowers/specs/2026-03-20-workflow-redesign-design.md`

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `BudahADE/Agents/AgentRole.swift` | Role enum, system prompt definitions, role metadata |
| `BudahADE/Agents/AgentRolePicker.swift` | Popover UI for selecting agent role when creating conversation |
| `BudahADE/Agents/AgentSystemPrompts.swift` | Default system prompt content for each role |
| `BudahADE/Spec/SpecParser.swift` | Parse spec `.md` files for task checkboxes, compute progress |
| `BudahADE/Spec/SpecWatcher.swift` | Watch worktree for spec files, trigger re-parse on changes |
| `BudahADE/Spec/SpecState.swift` | Observable state for spec progress (tasks, completion, current item) |
| `BudahADE/Spec/SpecPanelSection.swift` | Left panel section showing compact spec progress |
| `BudahADE/Spec/PlanView.swift` | Full-screen Plan mode view (rich task cards, agent sidebar) |
| `BudahADE/Spec/SpecStripView.swift` | Thin progress strip shown below tab bar in Build mode |
| `BudahADE/ProjectPicker/CloneProjectView.swift` | Clone repo from URL flow |
| `BudahADE/ProjectPicker/CreateProjectView.swift` | Create new project with git init flow |

### Modified Files
| File | Changes |
|------|---------|
| `BudahADE/Task/TaskState.swift` | Add `agentRole` to TabInfo, update `createTab()` to accept role, modify `autoLaunchClaude()` to inject system prompt |
| `BudahADE/Terminal/TerminalTabBar.swift` | Update TabInfo struct with role field, show role name in tabs |
| `BudahADE/Workspace/WorkspaceState.swift` | Add `specState` per task, add `planModeActive` toggle |
| `BudahADE/Workspace/LeftPanelView.swift` | Replace tab-based layout with dashboard sections (Spec, Changes, Conversations) |
| `BudahADE/Workspace/WorkspaceView.swift` | Add Plan/Build toggle in tab bar area, conditionally show PlanView or terminal |
| `BudahADE/Workspace/AgentsPanel.swift` | Merge into new Conversations section in dashboard (remove as standalone) |
| `BudahADE/Workspace/ChangesPanel.swift` | Adapt to work as collapsible section (not standalone tab) |
| `BudahADE/Task/NewTaskSheet.swift` | Add base branch picker with remote branches, fork-from-local option |
| `BudahADE/ProjectPicker/ProjectPickerView.swift` | Add Create/Clone entry points alongside Open |
| `BudahADE/ProjectPicker/ProjectStore.swift` | Add `createProject()` and `cloneProject()` methods |
| `BudahADE/App/BudahADEApp.swift` | Add Cmd+P shortcut for Plan/Build toggle |
| `BudahADE/Terminal/GhosttyConfig.swift` | Support passing additional CLI args (for `--system-prompt`) |
| `BudahADE/Shared/Theme.swift` | Add spec-related colors (specStripBg, planViewBg) |

---

## Task 1: Agent Role Model & System Prompts

**Files:**
- Create: `BudahADE/Agents/AgentRole.swift`
- Create: `BudahADE/Agents/AgentSystemPrompts.swift`

- [ ] **Step 1: Create AgentRole enum**

```swift
// BudahADE/Agents/AgentRole.swift
import SwiftUI

enum AgentRole: String, CaseIterable, Identifiable, Codable {
    case developer
    case assistant
    case manager
    case designer
    case qa
    case ideator
    case researcher
    case shell  // plain terminal, no Claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .assistant: return "Assistant"
        case .manager: return "Manager"
        case .designer: return "Designer"
        case .qa: return "QA"
        case .ideator: return "Ideator"
        case .researcher: return "Researcher"
        case .shell: return "Shell"
        }
    }

    var description: String {
        switch self {
        case .developer: return "Sr. Developer & Architect"
        case .assistant: return "Simple tasks, one-off changes"
        case .manager: return "Coordinates sub-agent work"
        case .designer: return "Front-end & UI expert"
        case .qa: return "Edge cases, code review"
        case .ideator: return "Product thinking, problem discovery"
        case .researcher: return "Research & analysis"
        case .shell: return "Plain terminal, no agent"
        }
    }

    var dotColor: Color {
        switch self {
        case .developer: return Theme.accent
        case .assistant: return Theme.info
        case .manager: return Theme.warning
        case .designer: return Color(hex: 0xb57aad)
        case .qa: return Theme.success
        case .ideator: return Color(hex: 0xc49a5c)
        case .researcher: return Color(hex: 0x7ab5a0)
        case .shell: return Theme.textMuted
        }
    }

    var launchesClaude: Bool {
        self != .shell
    }
}
```

- [ ] **Step 2: Create AgentSystemPrompts**

```swift
// BudahADE/Agents/AgentSystemPrompts.swift
import Foundation

enum AgentSystemPrompts {
    static func prompt(for role: AgentRole) -> String? {
        switch role {
        case .shell: return nil
        case .developer: return developerPrompt
        case .assistant: return assistantPrompt
        case .manager: return managerPrompt
        case .designer: return designerPrompt
        case .qa: return qaPrompt
        case .ideator: return ideatorPrompt
        case .researcher: return researcherPrompt
        }
    }

    private static let developerPrompt = """
    You are a Senior Developer and Architect. You have deep expertise across the full stack.
    You write clean, well-tested, production-ready code. You think about architecture,
    performance, and maintainability. When given a task, you plan before you code,
    write tests, and commit frequently with clear messages.
    """

    private static let assistantPrompt = """
    You are a helpful assistant for quick tasks. You handle simple, focused requests:
    one-off UI adjustments, small bug fixes, file edits, quick lookups. Keep responses
    concise and action-oriented. Do the task and move on.
    """

    private static let managerPrompt = """
    You are a Development Manager. You break down complex work into clear tasks,
    coordinate implementation across multiple concerns, and track progress.
    You create specs, delegate to sub-agents, and ensure quality. You think about
    the big picture while managing the details.
    """

    private static let designerPrompt = """
    You are a Front-End and UI Design Expert. You understand user outcomes and design
    exceptional interfaces. You think about accessibility, visual hierarchy, interaction
    patterns, and responsive design. You write clean, semantic front-end code.
    """

    private static let qaPrompt = """
    You are a QA Engineer. You detect edge cases, workflow issues, and code problems.
    You think adversarially about inputs, states, and failure modes. You write thorough
    test cases and review code for correctness, security, and robustness.
    """

    private static let ideatorPrompt = """
    You are a Product Thinker and Ideation Partner. You help form ideas by asking
    incisive questions. You know product frameworks (Jobs-to-be-Done, Design Thinking,
    First Principles). You help get to the truth of a problem before jumping to solutions.
    """

    private static let researcherPrompt = """
    You are a Research Expert. You investigate topics thoroughly, synthesize findings,
    and present clear analysis. You check multiple sources, consider opposing viewpoints,
    and distinguish facts from speculation. You cite your sources.
    """

    /// Write system prompt to a temp file in the worktree, return path
    static func writePromptFile(role: AgentRole, worktreePath: String) -> String? {
        guard let prompt = prompt(for: role) else { return nil }
        let filename = ".budahade-agent-\(role.rawValue).md"
        let path = (worktreePath as NSString).appendingPathComponent(filename)
        do {
            try prompt.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("Failed to write agent prompt: \(error)")
            return nil
        }
    }
}
```

- [ ] **Step 3: Add agent prompt files to .gitignore**

Append to `.gitignore`:
```
.budahade-agent-*.md
```

- [ ] **Step 4: Verify files compile**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Agents/AgentRole.swift BudahADE/Agents/AgentSystemPrompts.swift .gitignore
git commit -m "feat: add agent role model and system prompt definitions"
```

---

## Task 2: Wire Agent Roles into TabInfo and Terminal Launch

**Files:**
- Modify: `BudahADE/Terminal/TerminalTabBar.swift:28-39` (TabInfo struct)
- Modify: `BudahADE/Task/TaskState.swift:79-87` (createTab), `147-154` (autoLaunchClaude)

- [ ] **Step 1: Add role to TabInfo**

In `TerminalTabBar.swift`, update the TabInfo struct (line 28):

```swift
struct TabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isRunning: Bool
    var agentStatus: AgentStatus = .inactive
    var role: AgentRole = .developer  // NEW

    init(id: UUID = UUID(), title: String, isRunning: Bool = false, agentStatus: AgentStatus = .inactive, role: AgentRole = .developer) {
        self.id = id
        self.title = title
        self.isRunning = isRunning
        self.agentStatus = agentStatus
        self.role = role
    }
}
```

- [ ] **Step 2: Update createTab() to accept role**

In `TaskState.swift`, update `createTab()` (line 79):

```swift
func createTab(role: AgentRole = .developer) -> UUID {
    let id = UUID()
    let terminal = TerminalPanel(workingDirectory: worktreePath)
    terminals[id] = terminal
    let tab = TabInfo(id: id, title: role.displayName, role: role)
    tabs.append(tab)
    selectedTabId = id
    observeTitleChanges()
    return id
}
```

- [ ] **Step 3: Update autoLaunchClaude() to use role system prompt**

In `TaskState.swift`, update `autoLaunchClaude()` (line 147):

```swift
private func autoLaunchClaude() {
    guard let firstTab = tabs.first,
          firstTab.role.launchesClaude,
          let terminal = terminals[firstTab.id] else { return }

    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))

        var command = "claude"
        if let promptPath = AgentSystemPrompts.writePromptFile(
            role: firstTab.role,
            worktreePath: worktreePath
        ) {
            // Claude CLI --system-prompt takes inline text, so use cat to read the file
            command = "claude --system-prompt \"$(cat \\\"\(promptPath)\\\")\""
        }
        terminal.sendCommand(command)
    }
}
```

- [ ] **Step 4: Update TabInfo Equatable conformance**

If `TabInfo` has a manual `==` implementation, add `role` to the equality check. If it uses synthesized Equatable, no change needed — the compiler picks up the new field automatically.

- [ ] **Step 5: Update tab rendering to show role dot color**

In `TerminalTabBar.swift`, in the ConversationTab view, replace the fixed status dot color logic to use `tab.role.dotColor` as the base tint when idle:

Find the status dot color logic and update so that `.idle` state uses `tab.role.dotColor` instead of `Color.clear`.

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add BudahADE/Terminal/TerminalTabBar.swift BudahADE/Task/TaskState.swift
git commit -m "feat: wire agent roles into tab creation and terminal launch"
```

---

## Task 3: Agent Role Picker UI

**Files:**
- Create: `BudahADE/Agents/AgentRolePicker.swift`
- Modify: `BudahADE/Task/TaskState.swift` (update init to accept role for first tab)
- Modify: `BudahADE/Workspace/WorkspaceView.swift` (wire + button to show picker)

- [ ] **Step 1: Create AgentRolePicker popover**

```swift
// BudahADE/Agents/AgentRolePicker.swift
import SwiftUI

struct AgentRolePicker: View {
    let onSelect: (AgentRole) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AgentRole.allCases) { role in
                Button {
                    onSelect(role)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(role.dotColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(role.displayName)
                                .font(Theme.label(13))
                                .foregroundColor(Theme.textPrimary)
                            Text(role.description)
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.0001))
                )
                .onHover { hovering in
                    // hover handled by buttonStyle
                }
            }
        }
        .padding(8)
        .frame(width: 260)
        .background(Theme.surface2)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Wire role picker into new tab creation**

In `WorkspaceView.swift`, find the `.newTerminalTab` notification handler (around line 55). Update so that instead of directly calling `task.createTab()`, it sets a state to show the role picker popover. The popover calls `task.createTab(role:)` and then launches Claude with that role.

Add to WorkspaceView:
```swift
@State private var showRolePicker = false
```

Update the `+` button / newTerminalTab handler to toggle `showRolePicker`.

Add `.popover(isPresented: $showRolePicker)` with `AgentRolePicker { role in ... }`.

- [ ] **Step 3: Update TaskState init to accept initial role**

In `TaskState.swift` init, change the first tab creation to accept a role parameter:

```swift
init(name: String, branchName: String, worktreePath: String, repoPath: String, initialRole: AgentRole = .developer) {
    // ... existing init code ...
    let tabId = createTab(role: initialRole)
    // ... rest of init ...
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Agents/AgentRolePicker.swift BudahADE/Task/TaskState.swift BudahADE/Workspace/WorkspaceView.swift
git commit -m "feat: add agent role picker for new conversations"
```

---

## Task 4: Spec Parser and Watcher

**Files:**
- Create: `BudahADE/Spec/SpecParser.swift`
- Create: `BudahADE/Spec/SpecWatcher.swift`
- Create: `BudahADE/Spec/SpecState.swift`

- [ ] **Step 1: Create SpecParser**

```swift
// BudahADE/Spec/SpecParser.swift
import Foundation

struct SpecTask: Identifiable, Equatable {
    let id: Int  // index in file
    let title: String
    let isCompleted: Bool
    let description: String?  // line after task if not a checkbox

    var status: SpecTaskStatus {
        isCompleted ? .completed : .pending
    }
}

enum SpecTaskStatus {
    case completed
    case inProgress  // determined by app, not parser
    case pending
}

struct SpecParseResult: Equatable {
    let title: String?
    let description: String?
    let tasks: [SpecTask]
    let filePath: String

    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var totalCount: Int { tasks.count }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

enum SpecParser {
    /// Parse a markdown spec file for title and checkbox tasks
    static func parse(fileAt path: String) -> SpecParseResult? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var title: String?
        var description: String?
        var tasks: [SpecTask] = []
        var index = 0

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // First H1 is the title
            if title == nil && trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
                // Next non-empty line might be description
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !nextLine.isEmpty && !nextLine.hasPrefix("#") && !nextLine.hasPrefix("- [") {
                        description = nextLine
                    }
                }
                continue
            }

            // Checkbox tasks: - [x] or - [ ]
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                tasks.append(SpecTask(id: index, title: taskTitle, isCompleted: true, description: nil))
                index += 1
            } else if trimmed.hasPrefix("- [ ] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                tasks.append(SpecTask(id: index, title: taskTitle, isCompleted: false, description: nil))
                index += 1
            }
        }

        guard !tasks.isEmpty else { return nil }

        return SpecParseResult(
            title: title,
            description: description,
            tasks: tasks,
            filePath: path
        )
    }

    /// Find spec files in a directory
    static func findSpecFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else {
            return []
        }

        let specPatterns = ["-spec.md", "-plan.md", ".spec.md"]
        return contents
            .filter { name in specPatterns.contains(where: { name.lowercased().hasSuffix($0) }) }
            .map { (directory as NSString).appendingPathComponent($0) }
    }
}
```

- [ ] **Step 2: Create SpecState observable**

```swift
// BudahADE/Spec/SpecState.swift
import SwiftUI
import Combine

@MainActor
final class SpecState: ObservableObject {
    @Published var result: SpecParseResult?
    @Published var currentTaskIndex: Int?  // first uncompleted task

    var hasSpec: Bool { result != nil }
    var progress: Double { result?.progress ?? 0 }
    var completedCount: Int { result?.completedCount ?? 0 }
    var totalCount: Int { result?.totalCount ?? 0 }
    var currentTaskTitle: String? {
        guard let idx = currentTaskIndex, let result = result,
              idx < result.tasks.count else { return nil }
        return result.tasks[idx].title
    }

    func update(from result: SpecParseResult?) {
        self.result = result
        // First uncompleted task is "current"
        self.currentTaskIndex = result?.tasks.firstIndex(where: { !$0.isCompleted })
    }
}
```

- [ ] **Step 3: Create SpecWatcher**

```swift
// BudahADE/Spec/SpecWatcher.swift
import Foundation
import Combine

@MainActor
final class SpecWatcher: ObservableObject {
    let specState: SpecState
    private var timer: Timer?
    private let worktreePath: String
    private var lastContent: String?

    init(worktreePath: String, specState: SpecState) {
        self.worktreePath = worktreePath
        self.specState = specState
    }

    func startWatching() {
        // Poll every 3 seconds (matches git polling interval)
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
        // Initial check
        checkForChanges()
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// Call stopWatching() before letting this object dealloc.
    /// deinit cannot access @MainActor-isolated properties safely.

    private func checkForChanges() {
        let specFiles = SpecParser.findSpecFiles(in: worktreePath)

        guard let firstSpec = specFiles.first else {
            if specState.hasSpec {
                specState.update(from: nil)
            }
            return
        }

        // Only re-parse if content changed
        if let content = try? String(contentsOfFile: firstSpec, encoding: .utf8) {
            if content != lastContent {
                lastContent = content
                let result = SpecParser.parse(fileAt: firstSpec)
                specState.update(from: result)
            }
        }
    }

    // Note: call stopWatching() explicitly before dealloc.
    // deinit on @MainActor classes cannot safely access isolated properties.
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Spec/
git commit -m "feat: add spec parser, watcher, and state for progress tracking"
```

---

## Task 5: Wire SpecWatcher into TaskState

**Files:**
- Modify: `BudahADE/Task/TaskState.swift`
- Modify: `BudahADE/Workspace/WorkspaceState.swift`

- [ ] **Step 1: Add SpecState and SpecWatcher to TaskState**

In `TaskState.swift`, add properties after the existing properties (around line 24):

```swift
let specState = SpecState()
private var specWatcher: SpecWatcher?
```

In the `init`, after the existing setup, start the watcher:

```swift
// Start spec watcher
specWatcher = SpecWatcher(worktreePath: worktreePath, specState: specState)
specWatcher?.startWatching()
```

- [ ] **Step 2: Forward specState changes through WorkspaceState**

In `WorkspaceState.swift`, in the `createTask()` method where `taskCancellables` are set up, add forwarding for `specState.objectWillChange`:

```swift
// Forward spec state changes
let specCancellable = task.specState.objectWillChange.sink { [weak self] in
    self?.objectWillChange.send()
}
```

Store this cancellable alongside the existing task cancellable.

- [ ] **Step 3: Add planModeActive to WorkspaceState**

In `WorkspaceState.swift`, add:

```swift
@Published var planModeActive: Bool = false
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Task/TaskState.swift BudahADE/Workspace/WorkspaceState.swift
git commit -m "feat: wire spec watcher into task lifecycle"
```

---

## Task 6: Left Panel Dashboard Restructure

**Files:**
- Create: `BudahADE/Spec/SpecPanelSection.swift`
- Modify: `BudahADE/Workspace/LeftPanelView.swift`
- Modify: `BudahADE/Workspace/AgentsPanel.swift` (adapt to section)
- Modify: `BudahADE/Workspace/ChangesPanel.swift` (adapt to section)

- [ ] **Step 1: Create SpecPanelSection**

```swift
// BudahADE/Spec/SpecPanelSection.swift
import SwiftUI

struct SpecPanelSection: View {
    @ObservedObject var specState: SpecState
    let onViewTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("SPEC")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 6) {
                    Text("\(specState.completedCount)/\(specState.totalCount)")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundColor(Theme.accent)
                    Button("View") { onViewTapped() }
                        .buttonStyle(.plain)
                        .font(Theme.body(11))
                        .foregroundColor(Theme.textMuted)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * specState.progress, height: 3)
                }
            }
            .frame(height: 3)

            // Current task
            if let current = specState.currentTaskTitle {
                Text(current)
                    .font(Theme.body(12))
                    .foregroundColor(Theme.accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

- [ ] **Step 2: Refactor LeftPanelView from tabs to dashboard sections**

Replace the tab bar in `LeftPanelView.swift` with a dashboard layout. The new structure:

```swift
// Header: task name + branch badge
// Divider
// IF spec exists: SpecPanelSection + Divider
// Changes section (always)
// Divider
// Conversations section (always)
```

Remove the `LeftPanelTab` enum switching. Instead, stack sections vertically in a ScrollView. Keep the resizable width and drag handle.

**Note on FileTreeView:** The Files tab is removed from the left panel dashboard. FileTreeView will be accessible via Cmd+B toggle or a future dedicated shortcut. For now, the left panel focuses exclusively on task context (spec, changes, conversations).

The header should show:
```swift
HStack {
    Text(task.name).font(Theme.headline(14)).foregroundColor(Theme.textPrimary)
    Text(task.branchName).font(Theme.mono(11)).foregroundColor(Theme.accent)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Theme.accent.opacity(0.12)).cornerRadius(4)
}
```

- [ ] **Step 3: Convert AgentsPanel to ConversationsSection**

Rename/refactor `AgentsPanel.swift` to work as an inline section (no outer ScrollView or VStack wrapper — the parent handles layout). Keep the agent row rendering but update labels from "Agents" to "Conversations".

- [ ] **Step 4: Convert ChangesPanel to work as section**

The ChangesPanel currently has its own ScrollView and full layout. Wrap it so it can be embedded as a section in the dashboard. The collapsible sections (unstaged/staged/commits) remain.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Spec/SpecPanelSection.swift BudahADE/Workspace/LeftPanelView.swift BudahADE/Workspace/AgentsPanel.swift BudahADE/Workspace/ChangesPanel.swift
git commit -m "feat: restructure left panel from tabs to dashboard sections"
```

---

## Task 7: Spec Strip and Plan/Build Toggle

**Files:**
- Create: `BudahADE/Spec/SpecStripView.swift`
- Create: `BudahADE/Spec/PlanView.swift`
- Modify: `BudahADE/Workspace/WorkspaceView.swift`
- Modify: `BudahADE/App/BudahADEApp.swift` (add Cmd+P shortcut)

- [ ] **Step 1: Create SpecStripView**

```swift
// BudahADE/Spec/SpecStripView.swift
import SwiftUI

struct SpecStripView: View {
    @ObservedObject var specState: SpecState

    var body: some View {
        HStack(spacing: 12) {
            Text("SPEC")
                .font(Theme.label(11))
                .foregroundColor(Theme.accent)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 2)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * specState.progress, height: 2)
                }
            }
            .frame(height: 2)

            Text("\(specState.completedCount)/\(specState.totalCount)")
                .font(Theme.mono(11))
                .foregroundColor(Theme.accent)

            if let current = specState.currentTaskTitle {
                Text(current)
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.04))
        .overlay(
            Rectangle()
                .fill(Theme.accent.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
```

- [ ] **Step 2: Create PlanView (full spec view for Plan mode)**

```swift
// BudahADE/Spec/PlanView.swift
import SwiftUI

struct PlanView: View {
    @ObservedObject var specState: SpecState
    @ObservedObject var task: TaskState

    var body: some View {
        HStack(spacing: 0) {
            // Main spec content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title
                    if let title = specState.result?.title {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(Theme.headline(24))
                                .foregroundColor(Theme.textPrimary)
                            if let desc = specState.result?.description {
                                Text(desc)
                                    .font(Theme.body(14))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }

                    // Progress bar
                    HStack(spacing: 16) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent)
                                    .frame(width: geo.size.width * specState.progress, height: 4)
                            }
                        }
                        .frame(height: 4)
                        Text("\(specState.completedCount) / \(specState.totalCount)")
                            .font(Theme.mono(12, weight: .medium))
                            .foregroundColor(Theme.accent)
                    }

                    // Task cards
                    if let tasks = specState.result?.tasks {
                        VStack(spacing: 2) {
                            ForEach(tasks) { specTask in
                                specTaskRow(specTask)
                            }
                        }
                    }
                }
                .padding(48)
            }

            // Right sidebar: agent status
            agentSidebar
        }
        .background(Theme.contentBg)
    }

    @ViewBuilder
    private func specTaskRow(_ specTask: SpecTask) -> some View {
        let isCurrent = specTask.id == specState.currentTaskIndex

        HStack(alignment: .top, spacing: 12) {
            if specTask.isCompleted {
                Text("✓")
                    .font(Theme.body(13))
                    .foregroundColor(Theme.success)
            } else if isCurrent {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            } else {
                Circle()
                    .stroke(Theme.textMuted, lineWidth: 1)
                    .frame(width: 10, height: 10)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(specTask.title)
                    .font(Theme.label(13))
                    .foregroundColor(
                        specTask.isCompleted ? Theme.success :
                        isCurrent ? Theme.textPrimary : Theme.textSecondary
                    )
            }

            Spacer()

            if isCurrent {
                Text("in progress")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Theme.accent.opacity(0.08) : specTask.isCompleted ? Theme.success.opacity(0.04) : Color.clear)
        )
        .overlay(
            isCurrent ? RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.15), lineWidth: 1) : nil
        )
    }

    private var agentSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE AGENTS")
                .font(Theme.label(11))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.5)

            ForEach(task.tabs, id: \.id) { tab in
                HStack(spacing: 8) {
                    Circle()
                        .fill(tab.role.dotColor)
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.role.displayName)
                            .font(Theme.label(12))
                            .foregroundColor(Theme.textPrimary)
                        if tab.isRunning {
                            Text("Working...")
                                .font(Theme.body(11))
                                .foregroundColor(tab.role.dotColor)
                        }
                    }
                }
                .padding(8)
                .background(
                    tab.isRunning ?
                    RoundedRectangle(cornerRadius: 6).fill(tab.role.dotColor.opacity(0.08)) : nil
                )
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 220)
        .background(Color(hex: "18181b"))
        .overlay(
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1),
            alignment: .leading
        )
    }
}
```

- [ ] **Step 3: Add Plan/Build toggle to WorkspaceView**

In `WorkspaceView.swift`, modify the terminal area section (around line 79). The new structure:

```swift
// Tab bar area
VStack(spacing: 0) {
    // Unified bar: Plan/Build toggle + conversation tabs
    HStack(spacing: 0) {
        // Plan/Build toggle (only when spec exists)
        if let task = state.activeTask, task.specState.hasSpec {
            PlanBuildToggle(isPlanMode: $state.planModeActive)
            Divider().frame(height: 16).padding(.horizontal, 12)
        }

        // Existing TerminalTabBar
        TerminalTabBar(...)
    }

    // Spec strip (only in Build mode when spec exists)
    if let task = state.activeTask, task.specState.hasSpec, !state.planModeActive {
        SpecStripView(specState: task.specState)
    }

    // Content: Plan or Terminal
    if state.planModeActive, let task = state.activeTask, task.specState.hasSpec {
        PlanView(specState: task.specState, task: task)
    } else {
        // Existing terminal ZStack
    }
}
```

Create a small `PlanBuildToggle` view inline or as a separate component:

```swift
struct PlanBuildToggle: View {
    @Binding var isPlanMode: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Plan", isActive: isPlanMode) { isPlanMode = true }
            toggleButton("Build", isActive: !isPlanMode) { isPlanMode = false }
        }
        .padding(2)
        .background(Color.white.opacity(0.04))
        .cornerRadius(5)
    }

    private func toggleButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.label(11))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.white.opacity(0.08) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Add Cmd+P shortcut**

In `BudahADEApp.swift`, add to the keyboard shortcuts section:

```swift
Button("Toggle Plan") {
    NotificationCenter.default.post(name: .togglePlanMode, object: nil)
}
.keyboardShortcut("p", modifiers: .command)
```

Add `.togglePlanMode` to Notification.Name extensions.

Handle in WorkspaceView:

```swift
.onReceive(NotificationCenter.default.publisher(for: .togglePlanMode)) { _ in
    if let task = state.activeTask, task.specState.hasSpec {
        state.planModeActive.toggle()
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Spec/SpecStripView.swift BudahADE/Spec/PlanView.swift BudahADE/Workspace/WorkspaceView.swift BudahADE/App/BudahADEApp.swift
git commit -m "feat: add spec strip, Plan view, and Plan/Build mode toggle"
```

---

## Task 8: Enhanced New Task Sheet (Branch Picker)

**Files:**
- Modify: `BudahADE/Task/NewTaskSheet.swift`
- Modify: `BudahADE/Task/GitWorktreeManager.swift` (add listBranches)

- [ ] **Step 1: Add listBranches to GitWorktreeManager**

```swift
/// List all local and remote branches
static func listBranches(repoPath: String) async throws -> (local: [String], remote: [String]) {
    let localOutput = try await runGit(args: ["branch", "--format=%(refname:short)"], repoPath: repoPath)
    let local = localOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }

    let remoteOutput = try await runGit(args: ["branch", "-r", "--format=%(refname:short)"], repoPath: repoPath)
    let remote = remoteOutput.components(separatedBy: .newlines)
        .filter { !$0.isEmpty && !$0.contains("HEAD") }
        .map { $0.replacingOccurrences(of: "origin/", with: "") }

    return (local, remote)
}
```

- [ ] **Step 2: Update NewTaskSheet with branch picker**

Replace the text field for `baseBranch` with a Picker that loads branches on appear:

```swift
@State private var availableBranches: [String] = ["main"]
@State private var loadingBranches = false

// In form body, replace baseBranch TextField with:
Picker("Base branch", selection: $baseBranch) {
    ForEach(availableBranches, id: \.self) { branch in
        Text(branch).tag(branch)
    }
}
.onAppear {
    loadBranches()
}

private func loadBranches() {
    loadingBranches = true
    Task {
        do {
            let (local, remote) = try await GitWorktreeManager.listBranches(repoPath: workspace.projectPath)
            let all = Array(Set(local + remote)).sorted()
            await MainActor.run {
                availableBranches = all.isEmpty ? ["main"] : all
                loadingBranches = false
            }
        } catch {
            loadingBranches = false
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Task/NewTaskSheet.swift BudahADE/Task/GitWorktreeManager.swift
git commit -m "feat: enhanced task creation with branch picker"
```

---

## Task 9: Project Picker — Create & Clone

**Files:**
- Create: `BudahADE/ProjectPicker/CreateProjectView.swift`
- Create: `BudahADE/ProjectPicker/CloneProjectView.swift`
- Modify: `BudahADE/ProjectPicker/ProjectPickerView.swift`
- Modify: `BudahADE/ProjectPicker/ProjectStore.swift`

- [ ] **Step 1: Add createProject and cloneProject to ProjectStore**

```swift
/// Create a new project: make directory + git init
func createProject(name: String, at parentDirectory: URL) async throws -> String {
    let projectDir = parentDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["init"]
    process.currentDirectoryURL = projectDir
    try process.run()
    process.waitUntilExit()

    let path = projectDir.path
    addRecent(path: path, name: name)
    return path
}

/// Clone a repo from URL
func cloneProject(url: String, to parentDirectory: URL, name: String?) async throws -> String {
    let dirName = name ?? URL(string: url)?.lastPathComponent?.replacingOccurrences(of: ".git", with: "") ?? "project"
    let targetDir = parentDirectory.appendingPathComponent(dirName)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["clone", url, targetDir.path]
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Clone failed"
        throw NSError(domain: "BudahADE", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }

    let path = targetDir.path
    addRecent(path: path, name: dirName)
    return path
}
```

- [ ] **Step 2: Create CreateProjectView**

Simple form: project name + directory picker (NSOpenPanel) + "Create" button.

- [ ] **Step 3: Create CloneProjectView**

Simple form: repo URL + directory picker + optional name override + "Clone" button with progress indicator.

- [ ] **Step 4: Update ProjectPickerView with three entry points**

Add segmented control or three buttons at the top: "Open" (existing), "Create" (new), "Clone" (from URL). Each shows the relevant view.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add BudahADE/ProjectPicker/
git commit -m "feat: add Create and Clone flows to project picker"
```

---

## Task 10: Theme Updates and Final Polish

**Files:**
- Modify: `BudahADE/Shared/Theme.swift`
- Modify: `BudahADE/Workspace/WorkspaceState.swift` (cleanup LeftPanelTab if unused)

- [ ] **Step 1: Add spec-related theme colors**

In `Theme.swift`, add:

```swift
// Spec-related
static let specStripBg = accent.opacity(0.04)
static let specStripBorder = accent.opacity(0.08)
static let planViewSidebar = Color(hex: "18181b")
```

- [ ] **Step 2: Remove unused LeftPanelTab enum**

If the tab-based left panel has been fully replaced by the dashboard, remove the `LeftPanelTab` enum from `WorkspaceState.swift` (line 6-10) and the `activeLeftTab` property (line 19).

- [ ] **Step 3: Full build and manual test**

Run: `xcodebuild -scheme BudahADE -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Manual verification checklist:
- [ ] Open project → see project picker with Create/Clone/Open
- [ ] Create task → branch picker shows real branches
- [ ] New conversation → role picker appears with 7 roles + Shell
- [ ] Developer conversation → Claude launches with system prompt
- [ ] Shell conversation → plain terminal, no Claude
- [ ] Create a `test-spec.md` with checkboxes in worktree → spec UI appears
- [ ] Delete the spec file → spec UI disappears
- [ ] Toggle Plan/Build with Cmd+P → views switch
- [ ] Left panel shows dashboard sections (not tabs)
- [ ] Ctrl+1..9 switches tasks, Cmd+1..9 switches conversations

- [ ] **Step 4: Final commit**

```bash
git add BudahADE/Shared/Theme.swift BudahADE/Workspace/WorkspaceState.swift
git commit -m "feat: theme updates and cleanup for workflow redesign"
```

---

## Summary

| Task | What it builds | Dependencies |
|------|---------------|-------------|
| 1 | Agent role model + system prompts | None |
| 2 | Wire roles into TabInfo + terminal launch | Task 1 |
| 3 | Role picker UI | Task 2 |
| 4 | Spec parser + watcher + state | None |
| 5 | Wire spec into TaskState | Task 4 |
| 6 | Left panel dashboard restructure | Task 5 |
| 7 | Spec strip + Plan view + toggle | Task 5, 6 |
| 8 | Enhanced New Task sheet | None |
| 9 | Project picker Create/Clone | None |
| 10 | Theme + cleanup + integration test | All |

Tasks 1-3 (agents) and 4-5 (spec) can run in parallel.
Tasks 8-9 (task sheet, project picker) are independent and can run anytime.
Task 10 is the final integration.

---

## Deferred to Future Iterations

These features are described in the spec but intentionally deferred from this plan:

1. **Git-correlation hybrid tracking** — The spec describes the app watching git commits and correlating them to spec items via keyword matching. This plan implements the Claude-driven side (file watching + checkbox parsing). Git correlation adds complexity and can be layered on later.

2. **Fork existing local branch** — The New Task sheet gets a branch picker (Task 8) which covers "new branch from base" and selecting any local branch as base. The explicit "fork from local" UX (distinct from picking a base) is deferred.

3. **Rebase mid-work** — The spec mentions right-click task → "Rebase onto...". This is a future addition to the task context menu.

4. **Recursive spec file discovery** — SpecParser searches the worktree root only. Specs in subdirectories (e.g., `docs/`) are not found. Can add recursive search later if needed.

5. **Custom agent roles** — Users can't create/edit roles yet. The 7 defaults + Shell cover the initial use cases. A settings UI for custom roles comes later.

6. **`addRecent()` in ProjectStore** — Task 9 references this method. The implementer should check `ProjectStore.swift` for the existing persistence method (likely `saveLastProject()`) and either use it or add `addRecent()`.
