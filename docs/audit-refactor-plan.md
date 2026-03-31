# BudahADE Codebase Audit + Refactor Plan

## Executive Summary

BudahADE is a macOS IDE-like application (~22K LOC across 108 production Swift files) with three major subsystems: Plan Canvas (AI-driven design), Build Terminal (task execution), and Git Panel (version control). The architecture is generally sound with proper SwiftUI state management, but contains several moderate-risk issues around error handling, resource cleanup, and state synchronization.

**Overall Code Quality: 7.5/10**
- Strengths: Architecture, state management, testing approach
- Weaknesses: Error handling, redundancy, async safety

---

# Phase 1: Audit

## 1. Architecture Map

### Module Structure

```
BudahADE/
├── App/
│   ├── BudahADEApp.swift (312 LOC) — App entry point, window setup, state injection
│   ├── AppDelegate.swift (42 LOC) — Ghostty initialization, app lifecycle hooks
│   └── AppStatePersistence.swift (49 LOC) — Persists workspaces/tasks to ~/.budahade/
│
├── Workspace/
│   ├── WorkspaceView.swift (459 LOC) — Root layout, routes between Plan/Build per task
│   ├── WorkspaceState.swift (245 LOC) — Manages active workspace + task collection
│   ├── PaneLayout.swift — Left/right pane split configuration
│   ├── LeftPanelView.swift — Container for FileTree + Spec panels
│   ├── AgentsPanel.swift — Agent status sidebar
│   └── WorkspaceDropdown.swift — Workspace switcher UI
│
├── Task/ (9 files)
│   ├── TaskState.swift (621 LOC) — Core task model: terminal lifecycle, plan tabs, status
│   ├── TaskRailView.swift (341 LOC) — Left rail task list UI
│   ├── NewTaskSheet.swift (460 LOC) — Task creation modal with branch/prefix selection
│   ├── TaskArchive.swift — Archived/completed task storage
│   ├── TaskCompletionSheet.swift — Task finish/close flow
│   ├── BuildStatusState.swift — Tracks build pass/fail state per task
│   ├── BuildStatusWatcher.swift — Polls build output for status signals
│   └── GitWorktreeManager.swift — Creates/deletes git worktrees per task
│
├── Agent/ (5 files)
│   ├── AgentSession.swift (599 LOC) — Claude CLI session: stream parsing, activity feed
│   ├── ChatMessage.swift (525 LOC) — Message model + JSON stream event parser
│   ├── CLISubprocessManager.swift (389 LOC) — Spawns/manages claude CLI subprocess
│   ├── AgentRole.swift — Role definitions (researcher, designer, builder, etc.)
│   └── AgentMode.swift — Mode enum (.plan, .build, .claude)
│
├── Terminal/ (11 files)
│   ├── TerminalPanel.swift (87 LOC) — Ghostty terminal wrapper
│   ├── TerminalSurfaceView.swift (473 LOC) — Metal-backed terminal surface rendering
│   ├── GhosttyAppManager.swift — Ghostty app lifecycle + surface registry
│   ├── GhosttyConfig.swift — Ghostty configuration builder
│   ├── TmuxSessionManager.swift — tmux session create/attach/detach
│   ├── SessionPersistence.swift — Saves/restores terminal session metadata
│   ├── ScrollbackCapture.swift — Reads terminal scrollback buffer
│   ├── RestoredTerminalView.swift — UI for restoring a previous session
│   └── TerminalTabBar.swift (343 LOC) — Multi-tab terminal bar with status indicators
│
├── Plan/ (25+ files)
│   ├── PlanChatView.swift (1433 LOC) — Primary plan mode UI: tabs, chat, canvas split
│   ├── PlanCanvasState.swift (1123 LOC) — Canvas data model: tiles, connections, drag/resize
│   ├── PlanCanvasView.swift (536 LOC) — Canvas render loop + gesture handling
│   ├── PlanChatState.swift (245 LOC) — Per-tab session state, persistence, agent lifecycle
│   ├── CanvasNode.swift — Tile/frame data model (position, size, content type)
│   ├── CanvasPersistence.swift — Saves/loads canvas-state.json per worktree
│   ├── TileConnection.swift — Edge model between canvas tiles
│   ├── ConnectionsLayer.swift (485 LOC) — Arrow rendering for tile connections
│   ├── TileDragHandler.swift (381 LOC) — Drag gesture state machine
│   ├── TileResizeHandler.swift (381 LOC) — Resize handle gesture state machine
│   ├── TileSelectionManager.swift — Multi-select, marquee selection
│   ├── ConnectionSummaryManager.swift — Haiku-powered edge label summarization
│   ├── Markdown/ (6 files) — swift-markdown renderer, code blocks, syntax highlighting
│   └── TileViews/ (8 files) — Chat, Browser, Markdown, Terminal, Image, Sticky, Chrome tiles
│
├── GitPanel/ (14 files)
│   ├── GitRepository.swift (549 LOC) — Git state model: branches, diff, stage/commit ops
│   ├── GitSidebarView.swift — Git panel container
│   ├── CommitBarView.swift / CommitBar.swift — Commit message input + submit
│   ├── CommitHistoryView.swift — Recent commit log
│   ├── BranchHeaderView.swift / BranchPicker.swift — Branch switch UI
│   ├── DiffModalView.swift (364 LOC) — File diff viewer
│   ├── ChangesListView.swift / StagingView.swift — Staged/unstaged file lists
│   └── AICommitService.swift — Generates commit messages via Claude API
│
├── Spec/ (6 files)
│   ├── SpecState.swift (74 LOC) — Spec document model
│   ├── SpecWatcher.swift — File watcher for live spec updates
│   ├── SpecParser.swift — Parses markdown spec into structured sections
│   ├── SpecAssembler.swift — Combines plan chat output into spec document
│   └── SpecPanelView.swift (358 LOC) — Spec sidebar UI
│
├── FileTree/ (4 files) — Project file browser with live file watcher
├── ProjectPicker/ (2 files) — Workspace selection UI + persistent store
└── Shared/ — Theme, keyboard shortcuts, AgentStatusView
```

### Dependency Graph

```
BudahADEApp
  └→ WorkspaceView
      ├→ TaskRailView → TaskState
      ├→ LeftPanelView → (FileTree, Spec)
      ├→ TerminalPanelView → TerminalPanel → Ghostty/tmux
      ├→ GitSidebarView → GitRepository (polling)
      └→ PlanChatView [Plan mode]
          ├→ PlanChatState → AgentSession → CLISubprocessManager
          └→ PlanCanvasView
              ├→ PlanCanvasState → ConnectionSummaryManager
              ├→ ConnectionsLayer, TileDragHandler, TileResizeHandler
              └→ TileViews → (AgentSession, TerminalPanel, FileManager)
```

### Circular Dependencies

**None detected.** Clean layering observed throughout:
- App → Workspace → Task → {Plan, Build} (unidirectional)
- Agent (CLISubprocessManager) is stateless w.r.t. UI
- Canvas does not import Build or Spec modules
- Spec module is self-contained (watcher pattern)
- `PlanCanvasState` ↔ `ConnectionSummaryManager` uses callbacks with weak references — no retain cycle

---

## 2. Redundancy Report

### 2.1 — Duplicate Session ID Resolution Logic

**What:** Logic for finding the latest Claude session ID appears twice in the same file.

**Where:**
- `TaskState.swift:545–589` — `findLatestClaudeSessionId()` full implementation
- `TaskState.swift:467–469` — fallback call that triggers the same path

**Code:**
```swift
// Line 545–589 — Full implementation
private static func findLatestClaudeSessionId(worktreePath: String) -> String? {
    let projectSlug = worktreePath
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: ".", with: "-")
    let claudeProjectDir = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claude/projects/\(projectSlug)")
    // ... directory scan + file sorting
}

// Line 467–469 — Fallback call
if sessionId == nil {
    sessionId = Self.findLatestClaudeSessionId(worktreePath: worktreePath)
}
```

**Why it matters:** The slug-generation pattern is duplicated — if the format ever changes, both sites need updating. Minor but a latent inconsistency risk.

**Suggested consolidation:** Extract to `BudahADE/Utilities/SessionIdResolver.swift`

---

### 2.2 — Duplicate Terminal Title Pattern Matching

**What:** Braille spinner detection and Claude title parsing appear in two separate places.

**Where:**
- `TaskState.swift:498–542` — inline status detection inside `observeTitleChanges()`
- `TaskState.swift:597–620` — `parseAgentStatus(from title:)` function

**Code:**
```swift
// Location 1 — Inline
let isClaude = title.contains("Claude") ||
    title.unicodeScalars.contains { $0.value >= 0x2800 && $0.value <= 0x28FF } ||
    title.contains("✳")

// Location 2 — Separate function with same logic
let hasBrailleSpinner = t.unicodeScalars.contains { $0.value >= 0x2800 && $0.value <= 0x28FF }
if hasBrailleSpinner { return .working }
```

**Why it matters:** Both patterns must stay in sync. A change to one without the other causes status desync between the tab bar and the task state machine.

**Suggested consolidation:** Single `TerminalTitleParser.parse(_ title: String) -> AgentStatus`

---

### 2.3 — Shadow Status Dictionary

**What:** Agent status is tracked in two places simultaneously — once in `TabInfo.agentStatus` (source of truth) and once in `TaskState.previousStatuses` (shadow copy).

**Where:**
- `TaskState.swift:71` — `var previousStatuses: [UUID: AgentStatus] = [:]`
- `TaskState.swift:525–527` — `self.previousStatuses[surfaceId] = newStatus`

**Why it matters:** Two sources of truth for the same fact. Low risk today, but future status logic could read from the wrong one.

**Suggested consolidation:** Derive previous status from the tabs array directly rather than maintaining a parallel dictionary.

---

## 3. Code Quality Issues

### 3.1 — Dead Code

**Issue 3.1.1 — `extractSessionIdFromScrollback()`**
`TaskState.swift:545–553`
```swift
private static func extractSessionIdFromScrollback(from text: String) -> String? {
    guard let range = text.range(of: "session_[A-Za-z0-9]+", options: [.regularExpression, .backwards]) else {
        return nil
    }
    return String(text[range])
}
```
Comment at line 546 says "Not used." Preserved intentionally but creates confusion.
**Risk: 🟢 Safe** — remove or add explicit `// kept for future use` doc comment.

---

### 3.2 — Error Handling Issues

**Issue 3.2.1 — Silent Image Copy Failure**
`PlanCanvasState.swift:93–101`
```swift
if !FileManager.default.fileExists(atPath: destPath) {
    try? FileManager.default.copyItem(atPath: path, toPath: destPath)
}
```
**Why it matters:** If the copy fails silently, a canvas element is created pointing to a non-existent path. The tile fails to render with no diagnostic. User loses work without any warning.
**Risk: 🔴 High**

Also present at:
- `PlanCanvasState.swift:194–196` — spec file append
- `AppStatePersistence.swift:27–29` — directory creation

---

**Issue 3.2.2 — Silent Git Operation Failures**
`GitRepository.swift:84–127`
```swift
func stage(_ file: String) {
    _ = runGit(["add", "--", file])  // Result discarded
    refresh()
}
```
**Why it matters:** Git operations fail with no user feedback. User assumes a file is staged when it isn't. Same pattern on `unstage`, `stageAll`, `unstageAll`, `commit`, `checkout`.
**Risk: 🔴 High**

---

**Issue 3.2.3 — Worktree Error Not User-Facing**
`TaskState.swift:84–96`
```swift
Task {
    do {
        try await GitWorktreeManager.createWorktree(...)
    } catch {
        print("Worktree creation failed: \(error.localizedDescription)")
    }
    task.startTerminal()  // Proceeds regardless
}
```
Error is printed to console only. Task proceeds with fallback path. User never knows the worktree failed.
**Risk: 🟡 Low-Medium**

---

### 3.3 — Type Safety Issues

**Issue 3.3.1 — Loose String-Key JSON Navigation**
`ChatMessage.swift:243–262`
```swift
switch typeStr {
case "system":
    let subtype = decoded["subtype"]?.stringValue
    if subtype == "hook_started" || subtype == "hook_response" { ... }
case "assistant":
    guard let messageObj = decoded["message"]?.objectValue else { ... }
    if let contentArray = messageObj["content"]?.arrayValue { ... }
```
Works because Claude CLI output is validated upstream, but no compile-time safety. If the JSON schema changes, parser accepts wrong data silently.
**Risk: 🟡 Low**

---

**Issue 3.3.2 — Two Parallel Role Hierarchies**
`AgentRole.swift` + `AgentMode.swift`
- `AgentMode` is the enum (`.researcher`, `.designer`, `.builder`, `.claude`)
- `AgentRole` is a struct with `String id, name, systemPrompt`
- `AgentRole.from(agent:)` bridges them

Could be unified into a single type. Not actively harmful, just redundant abstraction.
**Risk: 🟢 Low**

---

### 3.4 — Async/Concurrency Issues

**Issue 3.4.1 — `GitRepository` Missing `@MainActor`**
`GitRepository.swift:36`
```swift
// Current
final class GitRepository: ObservableObject { }

// Should be
@MainActor
final class GitRepository: ObservableObject { }
```
Modifies `@Published` properties without explicit main-thread enforcement. Works today because all callers happen to be on the main actor, but will silently violate Swift Concurrency rules if any background call is added.
**Risk: 🟡 Low-Medium**

---

**Issue 3.4.2 — Race Condition in Conversation Persistence**
`PlanChatState.swift:161–174`
```swift
func persistConversation() {
    persistenceTask?.cancel()
    persistenceTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        guard let session = plannerSession else { return }  // ← too late
        let snapshot = ConversationSnapshot(...)
        PlanConversationPersistence.save(snapshot, to: worktreePath)
    }
}
```
`plannerSession` is read *after* the 1-second sleep. If the session is cleared during that window (e.g., tab closed), the guard exits and the conversation is not saved.
**Risk: 🟡 Medium** — rare but causes silent data loss

---

### 3.5 — State Management Issues

**Issue 3.5.1 — Deep Prop Drilling in Canvas Tile Views**
```
PlanCanvasView → CanvasElementView → TileChrome → ChatTileView
```
Tile-specific props thread 3–4 levels deep. Works correctly but creates friction when adding new tile capabilities — each level needs a new parameter.
**Risk: 🟢 Low** — `@EnvironmentObject` would be cleaner for deeply-shared canvas context

---

### 3.6 — Performance Issues

**Issue 3.6.1 — Unbounded Activity Feed Growth**
`AgentSession.swift:94–95`
```swift
@Published var activityFeed: [ActivityFeedEntry] = []
// Appended on every tool call, never trimmed
```
Long sessions accumulate hundreds of entries. `ActivityFeedView` renders all of them. Memory grows linearly with session length.
**Risk: 🟡 Medium**

---

**Issue 3.6.2 — High-Frequency Git Polling**
`GitRepository.swift:60–65`
```swift
pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
    self?.refresh()  // Runs 4+ git commands every 1.5s
}
```
Runs whenever the git panel is visible. Four shell-out calls every 1.5 seconds during active work is noticeable on large repos.
**Risk: 🟡 Low**

---

### 3.7 — Inconsistent Patterns

**Issue 3.7.1 — Mixed Binding vs Direct Mutation**
`WorkspaceView.swift:46–49` uses setter methods (`task.selectPlanTab($0)`) while some views directly mutate `@State` properties. Inconsistent convention across the codebase.
**Risk: 🟢 Low**

**Issue 3.7.2 — Inconsistent Error Logging**
- `TaskState.swift:92` — `print("Worktree creation failed: ...")`
- `CLISubprocessManager.swift:59` — `print("[CLISubprocessManager] ⚠️ No session found")`
- `GitRepository.swift` — No logging at all

No unified logging format or severity levels.
**Risk: 🟢 Low**

---

## 4. Risk Assessment Summary

| Issue | File | Lines | Risk |
|-------|------|-------|------|
| Silent image copy failure | PlanCanvasState.swift | 93–101 | 🔴 High |
| Silent spec file append | PlanCanvasState.swift | 194–196 | 🔴 High |
| Silent git command failures | GitRepository.swift | 84–127 | 🔴 High |
| Race condition in persist task | PlanChatState.swift | 161–174 | 🟡 Medium |
| Missing @MainActor | GitRepository.swift | 36 | 🟡 Medium |
| Worktree error not user-facing | TaskState.swift | 84–96 | 🟡 Medium |
| Unbounded activity feed | AgentSession.swift | 94–95 | 🟡 Medium |
| Duplicate session ID logic | TaskState.swift | 467–589 | 🟡 Low |
| Duplicate title parsing | TaskState.swift | 498–620 | 🟡 Low |
| Shadow status dictionary | TaskState.swift | 71, 525–527 | 🟡 Low |
| High-frequency git polling | GitRepository.swift | 60–65 | 🟡 Low |
| Loose JSON string parsing | ChatMessage.swift | 243–262 | 🟡 Low |
| Two parallel role hierarchies | AgentRole/Mode.swift | — | 🟢 Low |
| Deep prop drilling in canvas | PlanCanvasView.swift | — | 🟢 Low |
| Dead code (intentional) | TaskState.swift | 545–553 | 🟢 Safe |
| Inconsistent binding patterns | WorkspaceView.swift | 46–49 | 🟢 Low |
| Inconsistent error logging | Multiple | — | 🟢 Low |

---

# Phase 2: Refactor Plan

All batches are read-only until you approve execution. Ordered by dependency — 🟢 first.

---

## Batch 1 — Fix Silent Error Handling in File I/O
**Goal:** Replace `try?` silences in file operations with explicit `do/catch` + logging.
**Risk: 🟢 Safe**

**Files:**
- `BudahADE/Plan/PlanCanvasState.swift` (lines 93–101, 194–196)
- `BudahADE/App/AppStatePersistence.swift` (lines 27–29)

**What changes:**
- `try? FileManager.default.copyItem` → `do/catch` with `print("[PlanCanvasState] ⚠️ ...")`
- `try? FileManager.default.createDirectory` → same pattern
- No behavior change — only surfaces previously invisible failures

**What could break:** Nothing. Adding logging to previously swallowed errors cannot regress existing behavior.

**Verify:**
1. `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
2. Add an image tile on canvas — confirm it works
3. Check console for unexpected error messages

**Rollback:** `git revert` single commit for this batch

---

## Batch 2 — Fix Session Persistence Race Condition
**Goal:** Capture `plannerSession` before the async sleep to prevent stale-nil reads.
**Risk: 🟢 Safe**

**Files:**
- `BudahADE/Plan/PlanChatState.swift` (lines 161–174)

**What changes:**
- Move `guard let session = plannerSession` to before the `Task.sleep` call
- Snapshot creation uses the captured local reference, not a re-read

**What could break:** Nothing — semantically equivalent in the happy path, strictly better in the edge case.

**Verify:**
1. Build succeeds
2. Open plan tab, send a message, immediately switch tabs — confirm conversation persists

**Rollback:** Single-line revert

---

## Batch 3 — Consolidate Duplicate Session ID Logic
**Goal:** Extract `findLatestClaudeSessionId` into a shared utility.
**Risk: 🟢 Safe**

**Files:**
- `BudahADE/Task/TaskState.swift` (lines 467–469, 545–589)
- New: `BudahADE/Utilities/SessionIdResolver.swift`

**What changes:**
- Move slug-generation + directory scan to `SessionIdResolver.findLatest(worktreePath:)`
- Replace both call sites with the shared call
- Delete `extractSessionIdFromScrollback()` (confirmed unused)

**What could break:** Nothing — `findLatestClaudeSessionId` is `private static`, no external references exist.

**Verify:**
1. Build succeeds
2. Reopen app — confirm terminal sessions restore with correct Claude session ID

**Rollback:** Delete `SessionIdResolver.swift`, restore private method in `TaskState`

---

## Batch 4 — Consolidate Duplicate Terminal Title Parsing
**Goal:** Merge both braille-spinner detection blocks into a single typed parser.
**Risk: 🟢 Safe**

**Files:**
- `BudahADE/Task/TaskState.swift` (lines 498–542, 597–620)

**What changes:**
- Extract to `TerminalTitleParser.parse(_ title: String) -> AgentStatus`
- Remove inline detection from `observeTitleChanges()`
- Both call sites use the shared parser

**What could break:** If the two inline patterns were intentionally different. Audit confirms they are identical.

**Verify:**
1. Build succeeds
2. Run `claude` in terminal — confirm spinner/idle/active status matches previous behavior
3. Switch tasks — confirm status resets correctly

**Rollback:** Restore original inline logic, delete parser

---

## Batch 5 — Add `@MainActor` to `GitRepository`
**Goal:** Explicitly enforce main-thread access for all `@Published` properties.
**Risk: 🟡 Low risk**

**Files:**
- `BudahADE/GitPanel/GitRepository.swift` (line 36)

**What changes:**
- Add `@MainActor` to the class declaration
- Compiler will flag any call sites not already on the main actor — those will need `await`

**What could break:** Any background task calling `GitRepository` methods directly. Requires grep of call sites before executing.

**Verify:**
1. Build succeeds (compiler flags any violations)
2. Open git panel — stage/unstage/commit — confirm UI updates correctly

**Rollback:** Remove `@MainActor` annotation

---

## Batch 6 — Cap Activity Feed at 50 Entries
**Goal:** Prevent unbounded memory growth in long agent sessions.
**Risk: 🟡 Low risk**

**Files:**
- `BudahADE/Agent/AgentSession.swift` (lines 94–95)

**What changes:**
- After each `activityFeed.append(...)`, trim to last 50 entries

**What could break:** Users who scroll the activity feed during very long sessions will no longer see entries older than 50. This is intentional.

**Verify:**
1. Build succeeds
2. Run a long agent session with many tool calls
3. Confirm feed stops growing after 50 entries, most recent always visible

**Rollback:** Remove trim line

---

## Deferred — Needs Explicit Approval Before Inclusion

| Issue | Why deferred |
|-------|--------------|
| Silent git `stage`/`commit`/`checkout` failures | Changing to `throws` requires error-handling changes across multiple call sites in the UI layer — not a single-file change |
| Deep prop drilling in canvas tile views | Moving to `@EnvironmentObject` touches 8+ files and could subtly change state ownership semantics |
| Loose JSON parsing in `ChatMessage.swift` | Moving to `Codable` is a full rewrite of the stream parser — behavior-changing, needs its own spec |
| Git polling interval (1.5s → 3s) | Minor perf win, but touches a timing assumption — your call |

---

## Execution Order

```
Batch 1 (🟢) → Batch 2 (🟢) → Batch 3 (🟢) → Batch 4 (🟢)
                                      ↓
                               Batch 5 (🟡) — approve separately
                               Batch 6 (🟡) — approve separately
```
