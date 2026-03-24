# Phase 2.75: Session Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Terminal tabs and chat agent sessions survive app quit — scrollback snapshots display above fresh terminals, Claude resumes with `--resume`, and tab order/names persist.

**Architecture:** Save tab metadata + scrollback text to `.budahade/sessions/` on quit. On relaunch, recreate tabs in order, show scrollback as read-only styled text above the fresh Ghostty terminal, relaunch Claude with `--resume {sessionId}`. Chat tiles persist `claudeSessionId` in `canvas.json` for the same resume behavior.

**Tech Stack:** Swift, Ghostty C API (`ghostty_surface_read_text`), Foundation `Codable`, JSON persistence

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Terminal/SessionPersistence.swift` | Create | `TabSnapshot` model + save/load to `.budahade/sessions/tabs.json` |
| `Terminal/ScrollbackCapture.swift` | Create | Extract scrollback text from Ghostty surface via `ghostty_surface_read_text` |
| `Terminal/TerminalTabBar.swift` | Modify | Add `claudeSessionId` and `agentMode` to `TabInfo` |
| `Task/TaskState.swift` | Modify | Save/restore tabs on quit/launch, relaunch Claude with `--resume` |
| `Terminal/TerminalPanel.swift` | Modify | Add `readScrollback()` method |
| `Plan/CanvasPersistence.swift` | Modify | Add `claudeSessionIds` dict to `CanvasSnapshot` |
| `Plan/PlanCanvasState.swift` | Modify | Persist/restore `claudeSessionId` per chat session |
| `App/BudahADEApp.swift` | Modify | Save tab state in `willTerminateNotification` |
| `Terminal/TerminalContentView.swift` | Modify | Show scrollback snapshot above live terminal |

---

### Task 1: TabSnapshot Model + Persistence

**Files:**
- Create: `BudahADE/Terminal/SessionPersistence.swift`
- Test: `BudahADETests/SessionPersistenceTests.swift`

- [ ] **Step 1: Write failing test for TabSnapshot encode/decode**

```swift
import XCTest
@testable import BudahADE

final class SessionPersistenceTests: XCTestCase {
    func testTabSnapshotRoundTrip() throws {
        let snapshot = TabSnapshot(
            id: UUID(),
            title: "Builder",
            claudeSessionId: "sess_abc123",
            agentMode: "claude",
            isActive: true,
            scrollbackPath: "sessions/abc-scrollback.txt"
        )
        let session = SessionSnapshot(tabs: [snapshot], selectedTabId: snapshot.id)

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.tabs.count, 1)
        XCTAssertEqual(decoded.tabs[0].title, "Builder")
        XCTAssertEqual(decoded.tabs[0].claudeSessionId, "sess_abc123")
        XCTAssertEqual(decoded.selectedTabId, snapshot.id)
    }

    func testSaveAndLoad() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let tab = TabSnapshot(id: UUID(), title: "Test", claudeSessionId: nil, agentMode: nil, isActive: false, scrollbackPath: nil)
        let session = SessionSnapshot(tabs: [tab], selectedTabId: tab.id)

        try SessionPersistence.save(session, to: dir)
        let loaded = SessionPersistence.load(from: dir)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs[0].title, "Test")
    }

    func testLoadMissingFileReturnsNil() {
        let result = SessionPersistence.load(from: "/nonexistent/path")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/SessionPersistenceTests 2>&1 | tail -20`

- [ ] **Step 3: Implement SessionPersistence**

```swift
// BudahADE/Terminal/SessionPersistence.swift
import Foundation

struct TabSnapshot: Codable {
    let id: UUID
    let title: String
    let claudeSessionId: String?
    let agentMode: String?       // AgentMode rawValue or nil
    let isActive: Bool
    let scrollbackPath: String?  // relative path to scrollback text file
}

struct SessionSnapshot: Codable {
    let tabs: [TabSnapshot]
    let selectedTabId: UUID?
}

enum SessionPersistence {
    private static let directory = "sessions"
    private static let filename = "tabs.json"

    static func save(_ snapshot: SessionSnapshot, to worktreePath: String) throws {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func load(from worktreePath: String) -> SessionSnapshot? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)/\(filename)")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    static func saveScrollback(_ text: String, tabId: UUID, to worktreePath: String) throws -> String {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filename = "\(tabId.uuidString)-scrollback.txt"
        let path = (dir as NSString).appendingPathComponent(filename)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return "\(directory)/\(filename)"
    }

    static func loadScrollback(relativePath: String, from worktreePath: String) -> String? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(relativePath)")
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run tests — verify pass**
- [ ] **Step 5: Commit**

```bash
git add BudahADE/Terminal/SessionPersistence.swift BudahADETests/SessionPersistenceTests.swift
git commit -m "feat: TabSnapshot model and SessionPersistence save/load"
```

---

### Task 2: Scrollback Capture from Ghostty Surface

**Files:**
- Create: `BudahADE/Terminal/ScrollbackCapture.swift`
- Modify: `BudahADE/Terminal/TerminalPanel.swift`

- [ ] **Step 1: Create ScrollbackCapture utility**

```swift
// BudahADE/Terminal/ScrollbackCapture.swift
import Foundation

/// Reads terminal text content from a Ghostty surface using the C API.
enum ScrollbackCapture {

    /// Read all visible + scrollback text from a Ghostty surface.
    /// Returns nil if the surface is unavailable or the API call fails.
    static func readAll(from surface: ghostty_surface_t) -> String? {
        // Select from screen origin (0,0) to a large bottom-right to capture everything
        var selection = ghostty_selection_s()
        selection.top_left = ghostty_point_s(
            tag: GHOSTTY_POINT_SCREEN,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        selection.bottom_right = ghostty_point_s(
            tag: GHOSTTY_POINT_ACTIVE,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        selection.rectangle = false

        var textInfo = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &textInfo) else {
            return nil
        }
        defer { ghostty_surface_free_text(surface, &textInfo) }

        guard let ptr = textInfo.text, textInfo.text_len > 0 else { return nil }
        return String(cString: ptr)
    }
}
```

- [ ] **Step 2: Add `readScrollback()` to TerminalPanel**

In `BudahADE/Terminal/TerminalPanel.swift`, add:

```swift
/// Capture current terminal scrollback text. Returns nil if unavailable.
func readScrollback() -> String? {
    guard let ghosttySurface = surface.surface else { return nil }
    return ScrollbackCapture.readAll(from: ghosttySurface)
}
```

- [ ] **Step 3: Build and verify compiles**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE -configuration Debug build 2>&1 | tail -5`

Note: `ghostty_point_s` init may need adjustment based on actual struct layout. If the struct fields are `tag`, `coord`, `x`, `y` — use member-wise init. If it's a C struct with different field order, adjust accordingly. Check compile errors and fix.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Terminal/ScrollbackCapture.swift BudahADE/Terminal/TerminalPanel.swift
git commit -m "feat: scrollback capture from Ghostty surface via ghostty_surface_read_text"
```

---

### Task 3: Add claudeSessionId to TabInfo + Track in TaskState

**Files:**
- Modify: `BudahADE/Terminal/TerminalTabBar.swift` (lines 28-39)
- Modify: `BudahADE/Task/TaskState.swift` (lines 130-180)

- [ ] **Step 1: Extend TabInfo with session tracking fields**

In `TerminalTabBar.swift`, modify `TabInfo`:

```swift
struct TabInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isRunning: Bool
    var agentStatus: AgentStatus = .inactive
    var claudeSessionId: String?   // For --resume on restart
    var agentMode: AgentMode?      // Which agent role launched this tab

    static func == (lhs: TabInfo, rhs: TabInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isRunning == rhs.isRunning &&
        lhs.agentStatus == rhs.agentStatus
    }
}
```

- [ ] **Step 2: Track claudeSessionId from OSC title updates**

In `TaskState.swift`, find `observeTitleChanges()` which watches for `.terminalTitleChanged`. Add a parallel observer for `.terminalPwdChanged` or add session ID extraction from the terminal title. Alternatively, parse the Claude session ID from the terminal's title string if Claude sets it.

**Simpler approach:** Track session ID when launching Claude. In `launchClaudeInTab()`, after sending the command, the Claude CLI will eventually set the terminal title. But the `--session-id` is not directly surfaced this way.

**Best approach:** After Claude launches, read the `.claude/projects/*/sessions/` directory to find the most recent session file matching this terminal's launch time. Or, parse the `--resume` session ID from the `.claude` state.

**Simplest viable approach:** When the user sends `claude` command, Claude's stream-json output includes session_id. But Build mode terminals don't parse stream-json (they're full PTY terminals). So we need to:

1. Before launching Claude, generate a session ID or let Claude generate one
2. After Claude exits, scan for the session file

**Pragmatic approach for Build mode tabs:** Store the launch command and let Claude manage sessions via `--resume` with the last known session. Track by scanning `.claude/projects/*/sessions/` sorted by mtime after terminal creation.

For now, add the field and populate it when available. Chat tiles already have it. Build mode will get it in a follow-up if needed.

- [ ] **Step 3: Pass agentMode to createTab**

Modify `createTab` in `TaskState.swift`:

```swift
@discardableResult
func createTab(launchAgent: Bool = false, agent: AgentMode? = nil) -> UUID {
    let panel = TerminalPanel(workingDirectory: worktreePath)
    let id = panel.id
    var tab = TabInfo(id: id, title: "Terminal", isRunning: false)
    tab.agentMode = agent
    tabs.append(tab)
    terminals[id] = panel
    selectedTabId = id

    if launchAgent {
        launchClaudeInTab(id, agent: agent)
    }

    return id
}
```

- [ ] **Step 4: Build and verify**
- [ ] **Step 5: Commit**

```bash
git add BudahADE/Terminal/TerminalTabBar.swift BudahADE/Task/TaskState.swift
git commit -m "feat: add claudeSessionId and agentMode to TabInfo"
```

---

### Task 4: Save Tab State on App Quit

**Files:**
- Modify: `BudahADE/Task/TaskState.swift`
- Modify: `BudahADE/App/BudahADEApp.swift` (line 15-21)

- [ ] **Step 1: Add `saveSessionState()` to TaskState**

```swift
// In TaskState.swift
func saveSessionState() {
    var tabSnapshots: [TabSnapshot] = []

    for tab in tabs {
        // Capture scrollback if terminal is alive
        var scrollbackPath: String?
        if let panel = terminals[tab.id] {
            if let text = panel.readScrollback(), !text.isEmpty {
                scrollbackPath = try? SessionPersistence.saveScrollback(
                    text, tabId: tab.id, to: worktreePath
                )
            }
        }

        tabSnapshots.append(TabSnapshot(
            id: tab.id,
            title: tab.title,
            claudeSessionId: tab.claudeSessionId,
            agentMode: tab.agentMode?.rawValue,
            isActive: tab.id == selectedTabId,
            scrollbackPath: scrollbackPath
        ))
    }

    let session = SessionSnapshot(tabs: tabSnapshots, selectedTabId: selectedTabId)
    try? SessionPersistence.save(session, to: worktreePath)
}
```

- [ ] **Step 2: Call saveSessionState in app quit hook**

In `BudahADEApp.swift`, modify the `willTerminateNotification` handler:

```swift
.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
    for workspace in appState.workspaces {
        for task in workspace.tasks {
            task.saveSessionState()   // Save tabs + scrollback
            task.planCanvas?.saveNow() // Save canvas
        }
    }
}
```

- [ ] **Step 3: Build and verify**
- [ ] **Step 4: Commit**

```bash
git add BudahADE/Task/TaskState.swift BudahADE/App/BudahADEApp.swift
git commit -m "feat: save tab state + scrollback on app quit"
```

---

### Task 5: Restore Tabs on Task Start

**Files:**
- Modify: `BudahADE/Task/TaskState.swift` (lines 92-98)

- [ ] **Step 1: Add `restoreSessionState()` to TaskState**

```swift
// In TaskState.swift
func restoreSessionState() -> Bool {
    guard let session = SessionPersistence.load(from: worktreePath) else { return false }
    guard !session.tabs.isEmpty else { return false }

    for tabSnapshot in session.tabs {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        // Use the panel's auto-generated ID (not the old snapshot ID — surface is new)
        let id = panel.id
        var tab = TabInfo(id: id, title: tabSnapshot.title, isRunning: false)
        tab.claudeSessionId = tabSnapshot.claudeSessionId
        tab.agentMode = tabSnapshot.agentMode.flatMap { AgentMode(rawValue: $0) }
        tabs.append(tab)
        terminals[id] = panel

        // Store scrollback for display (loaded lazily by TerminalContentView)
        if let scrollbackPath = tabSnapshot.scrollbackPath,
           let scrollback = SessionPersistence.loadScrollback(relativePath: scrollbackPath, from: worktreePath) {
            panel.restoredScrollback = scrollback
        }

        // Relaunch Claude with --resume if we have a session ID
        if let sessionId = tabSnapshot.claudeSessionId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                let agent = tab.agentMode
                let command = AgentPrompts.launchCommand(
                    agent: agent ?? .claude,
                    taskName: self.name,
                    branchName: self.branchName,
                    worktreePath: self.worktreePath,
                    panelId: id,
                    specFilePath: self.specState.activeSpec?.filePath,
                    specProgress: self.specState.activeSpec.map { ($0.completedCount, $0.totalCount) }
                ) + " --resume \(sessionId)"
                panel.sendCommand(command)
            }
        }

        if tabSnapshot.isActive || tabSnapshot.id == session.selectedTabId {
            selectedTabId = id
        }
    }

    if selectedTabId == nil, let first = tabs.first {
        selectedTabId = first.id
    }

    return true
}
```

- [ ] **Step 2: Modify `startTerminal()` to try restore first**

```swift
func startTerminal() {
    guard tabs.isEmpty else { return }

    // Try restoring from saved session state
    if restoreSessionState() {
        specWatcher = SpecWatcher(worktreePath: worktreePath, specState: specState)
        specWatcher?.startWatching()
        return
    }

    // No saved state — create fresh tab
    createTab()
    autoLaunchClaude()
    specWatcher = SpecWatcher(worktreePath: worktreePath, specState: specState)
    specWatcher?.startWatching()
}
```

- [ ] **Step 3: Add `restoredScrollback` property to TerminalPanel**

In `TerminalPanel.swift`:

```swift
/// Scrollback text from previous session (displayed as read-only snapshot above terminal)
var restoredScrollback: String?
```

- [ ] **Step 4: Build and verify**
- [ ] **Step 5: Commit**

```bash
git add BudahADE/Task/TaskState.swift BudahADE/Terminal/TerminalPanel.swift
git commit -m "feat: restore tabs from saved session state with --resume"
```

---

### Task 6: Scrollback Snapshot UI

**Files:**
- Modify: `BudahADE/Terminal/TerminalContentView.swift` (or wherever the terminal is rendered in Build mode)

- [ ] **Step 1: Find the Build mode terminal view**

Search for where `TerminalPanelView` (the NSViewRepresentable) is used in Build mode. This is likely in `TerminalContentView.swift` or `BuildModeView.swift`.

- [ ] **Step 2: Add scrollback snapshot display above terminal**

When `panel.restoredScrollback` is non-nil, show it as a read-only, faded, monospace text view above the live Ghostty terminal with a "Session resumed" divider:

```swift
VStack(spacing: 0) {
    // Scrollback snapshot from previous session
    if let scrollback = panel.restoredScrollback {
        ScrollView {
            Text(scrollback)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.textMuted.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 300) // Capped height, scrollable

        // Divider
        HStack {
            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
            Text("Session resumed")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textMuted)
            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // Live terminal
    TerminalPanelView(panel: panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 3: Build and verify**
- [ ] **Step 4: Commit**

```bash
git add BudahADE/Terminal/TerminalContentView.swift
git commit -m "feat: scrollback snapshot display with session resumed divider"
```

---

### Task 7: Chat Tile claudeSessionId Persistence

**Files:**
- Modify: `BudahADE/Plan/CanvasPersistence.swift`
- Modify: `BudahADE/Plan/PlanCanvasState.swift`

- [ ] **Step 1: Add claudeSessionIds to CanvasSnapshot**

In `CanvasPersistence.swift`:

```swift
struct CanvasSnapshot: Codable {
    let elements: [CanvasElement]
    let zoom: CGFloat
    let panOffsetWidth: CGFloat
    let panOffsetHeight: CGFloat
    let chatMessages: [UUID: [ChatMessage]]
    let claudeSessionIds: [UUID: String]?  // sessionId → claude session ID for --resume
}
```

Make it optional (`?`) for backwards compatibility with existing canvas.json files.

- [ ] **Step 2: Persist claudeSessionId in snapshot()**

In `PlanCanvasState.swift`, modify `snapshot()`:

```swift
func snapshot() -> CanvasSnapshot {
    var messages: [UUID: [ChatMessage]] = [:]
    var sessionIds: [UUID: String] = [:]
    for (id, session) in chatSessions {
        messages[id] = session.messages
        if let claudeId = session.claudeSessionId {
            sessionIds[id] = claudeId
        }
    }
    return CanvasSnapshot(
        elements: elements,
        zoom: zoom,
        panOffsetWidth: panOffset.width,
        panOffsetHeight: panOffset.height,
        chatMessages: messages,
        claudeSessionIds: sessionIds.isEmpty ? nil : sessionIds
    )
}
```

- [ ] **Step 3: Restore claudeSessionId in restore(from:)**

In `PlanCanvasState.swift`, modify `restore(from:)` to set `claudeSessionId`:

```swift
// Inside the chat agent restore loop:
if let claudeId = snapshot.claudeSessionIds?[sessionId] {
    restoredSession.claudeSessionId = claudeId
}
```

- [ ] **Step 4: Write test for round-trip**

```swift
func testCanvasSnapshotWithClaudeSessionIds() throws {
    let snapshot = CanvasSnapshot(
        elements: [],
        zoom: 1.0,
        panOffsetWidth: 0,
        panOffsetHeight: 0,
        chatMessages: [:],
        claudeSessionIds: [UUID(): "sess_test123"]
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: data)
    XCTAssertEqual(decoded.claudeSessionIds?.values.first, "sess_test123")
}
```

- [ ] **Step 5: Build and run tests**
- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/CanvasPersistence.swift BudahADE/Plan/PlanCanvasState.swift BudahADETests/CanvasPersistenceTests.swift
git commit -m "feat: persist claudeSessionId for chat tiles in canvas.json"
```

---

### Task 8: Integration Testing

- [ ] **Step 1: Build and launch app**

```bash
xcodebuild -project BudahADE.xcodeproj -scheme BudahADE -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 2: Verification checklist (from spec)**

1. **Build mode tabs persist** — open 3 builder tabs. Quit app, reopen. All 3 tabs recreate with correct names and order.
2. **Scrollback snapshot** — previous terminal output visible as read-only text above the fresh terminal.
3. **Session resumed divider** — clear visual separator between old snapshot and new live terminal.
4. **Claude --resume works** — send a follow-up message after relaunch. Claude remembers prior context.
5. **Chat tile claudeSessionId** — quit with a chat agent on canvas, reopen. Send a message — Claude resumes.
6. **Canvas terminal tiles** — same scrollback + resume behavior as Build mode tabs.
7. **Tab order** — tabs restore in the same order. Active tab is re-selected.
8. **No scrollback available** — if scrollback capture fails, terminal relaunches with just `--resume`, no crash.

- [ ] **Step 3: Fix any issues found**
- [ ] **Step 4: Final commit**

```bash
git commit -m "fix: integration test fixes for session persistence"
```
