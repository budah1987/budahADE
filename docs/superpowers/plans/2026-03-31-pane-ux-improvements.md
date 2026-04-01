# Pane UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the file tree, add a pane-dim visual cue, replace pane focus shortcuts with directional Cmd+Arrow, and change Shift+Cmd+B to always create a new browser tab.

**Architecture:** All changes are self-contained — model changes (TaskState, SplitPaneState) are wired through the existing notification → WorkspaceView → task method chain. No new files are needed.

**Tech Stack:** SwiftUI, AppKit, macOS, XcodeGen (`project.yml` is source of truth)

---

## File Map

| File | Role |
|------|------|
| `BudahADE/FileTree/FileTreeNode.swift` | Fix: diagnose + patch scan() |
| `BudahADE/FileTree/FileWatcher.swift` | Fix: expand path before open() |
| `BudahADE/Workspace/WorkspaceView.swift` | Add pane scrim; wire new notifications; fix browser handler |
| `BudahADE/Workspace/SplitPaneState.swift` | Add PaneArrow; remove PaneFocusDirection |
| `BudahADE/Task/TaskState.swift` | Add focusPane(arrow:); remove moveFocus |
| `BudahADE/App/BudahADEApp.swift` | Replace focus shortcuts; update notification names |
| `BudahADETests/PaneFocusTests.swift` | Unit tests for focusPane logic |

---

## Task 1: Diagnose and Fix File Tree

**Files:**
- Modify: `BudahADE/FileTree/FileTreeNode.swift`
- Modify: `BudahADE/FileTree/FileWatcher.swift`

The tree is empty. Root cause: `try? fm.contentsOfDirectory(atPath:)` silently swallows errors. Step 1 surfaces the real error; steps that follow patch the most likely causes.

- [ ] **Step 1: Surface the scan error**

In `FileTreeNode.swift`, temporarily replace the silent `try?` with a throwing variant that prints:

```swift
static func scan(directory: String) -> [FileTreeNode] {
    let fm = FileManager.default
    // DIAGNOSTIC — replace try? with do/catch
    let entries: [String]
    do {
        entries = try fm.contentsOfDirectory(atPath: directory)
    } catch {
        print("[FileTree] scan failed for '\(directory)': \(error)")
        return []
    }

    var dirs: [FileTreeNode] = []
    var files: [FileTreeNode] = []

    for entry in entries.sorted() {
        if ignoredNames.contains(entry) || entry.hasPrefix(".") { continue }
        let fullPath = (directory as NSString).appendingPathComponent(entry)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }
        let node = FileTreeNode(name: entry, path: fullPath, isDirectory: isDir.boolValue)
        if isDir.boolValue { dirs.append(node) } else { files.append(node) }
    }

    return dirs + files
}
```

- [ ] **Step 2: Build and run to read the log**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Open the app. Look at the Xcode console or run output for a `[FileTree]` line. If no line appears, the scan is not being called at all (view rendering issue). If a line appears, the error message identifies the root cause.

- [ ] **Step 3: Apply path-hardening fixes**

Whether or not the diagnostic fired, apply these defensive fixes — they are correct regardless of root cause.

In `FileTreeNode.swift`, resolve the path before use (handles tilde and symlink issues):

```swift
static func scan(directory: String) -> [FileTreeNode] {
    let resolved = URL(fileURLWithPath: directory).standardizedFileURL.path
    let fm = FileManager.default
    do {
        let entries = try fm.contentsOfDirectory(atPath: resolved)
        var dirs: [FileTreeNode] = []
        var files: [FileTreeNode] = []
        for entry in entries.sorted() {
            if ignoredNames.contains(entry) || entry.hasPrefix(".") { continue }
            let fullPath = (resolved as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }
            let node = FileTreeNode(name: entry, path: fullPath, isDirectory: isDir.boolValue)
            if isDir.boolValue { dirs.append(node) } else { files.append(node) }
        }
        return dirs + files
    } catch {
        print("[FileTree] scan failed for '\(resolved)': \(error)")
        return []
    }
}
```

Also update `toggle()` in `FileTreeNode.swift` — children scan already uses `self.path` which is derived from the resolved parent, so no change needed there.

In `FileWatcher.swift`, resolve the path before opening:

```swift
func start() {
    stop()
    let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
    fileDescriptor = open(resolved, O_EVTONLY)
    guard fileDescriptor >= 0 else {
        print("[FileWatcher] open() failed for '\(resolved)'")
        return
    }
    // ... rest unchanged ...
```

The full updated `start()`:

```swift
func start() {
    stop()

    let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
    fileDescriptor = open(resolved, O_EVTONLY)
    guard fileDescriptor >= 0 else {
        print("[FileWatcher] open() failed for '\(resolved)'")
        return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: [.write, .delete, .rename],
        queue: .global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
        self?.scheduleUpdate()
    }

    source.setCancelHandler { [weak self] in
        guard let self = self, self.fileDescriptor >= 0 else { return }
        close(self.fileDescriptor)
        self.fileDescriptor = -1
    }

    source.resume()
    self.source = source
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` with no errors.

Run the app. Open the Files panel. Files should appear. If still empty, the diagnostic print will now show what's failing — investigate from there before continuing.

- [ ] **Step 5: Commit**

```bash
git add BudahADE/FileTree/FileTreeNode.swift BudahADE/FileTree/FileWatcher.swift
git commit -m "fix: harden file tree path resolution, surface scan errors"
```

---

## Task 2: Inactive Pane Dim

**Files:**
- Modify: `BudahADE/Workspace/WorkspaceView.swift`

When split, the non-focused pane gets a `Color.black.opacity(0.25)` scrim overlaid on its entire VStack (tab bar + content). The focused pane has no scrim.

- [ ] **Step 1: Add the paneScrim helper**

In `WorkspaceView.swift`, add this private helper alongside the existing `paneFocusBorder`:

```swift
private func paneScrim(focused: Bool) -> some View {
    Color.black
        .opacity(focused ? 0 : 0.25)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: focused)
}
```

- [ ] **Step 2: Apply the scrim to both split panes**

In `terminalArea`, find the split-mode block — the `PaneLayout` with `first:` and `second:` panes. Add `.overlay(paneScrim(...))` to each pane's outermost `VStack`:

```swift
PaneLayout(orientation: split.orientation) {
    VStack(spacing: 0) {
        TerminalTabBar(
            selectedTabID: Binding(
                get: { task.selectedTabId ?? UUID() },
                set: { task.selectTab($0) }
            ),
            tabs: task.primaryTabs,
            renameTarget: renameTarget,
            onSelectTab: { task.selectTab($0) },
            onCloseTab: { requestCloseTab(.build($0)) },
            onNewTab: { task.createTab() },
            onNewBrowserTab: { task.createBrowserTab() }
        )
        tabContentView(for: task, tabId: task.selectedTabId)
            .overlay(paneFocusBorder(focused: task.focusedPane == .primary))
            .onTapGesture { task.focusedPane = .primary }
    }
    .overlay(paneScrim(focused: task.focusedPane == .primary))
} second: {
    VStack(spacing: 0) {
        TerminalTabBar(
            selectedTabID: Binding(
                get: { split.secondarySelectedId ?? UUID() },
                set: { task.selectSecondaryTab($0) }
            ),
            tabs: task.secondaryTabs,
            renameTarget: renameTarget,
            onSelectTab: { task.selectSecondaryTab($0) },
            onCloseTab: { requestCloseTab(.build($0)) },
            onNewTab: { task.createTabInSecondaryPane() },
            onNewBrowserTab: { task.createBrowserTabInSecondaryPane() }
        )
        tabContentView(for: task, tabId: split.secondarySelectedId)
            .overlay(paneFocusBorder(focused: task.focusedPane == .secondary))
            .onTapGesture { task.focusedPane = .secondary }
    }
    .overlay(paneScrim(focused: task.focusedPane == .secondary))
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Run the app, create a split. Click between panes — the inactive one should dim smoothly.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Workspace/WorkspaceView.swift
git commit -m "feat: dim inactive split pane with animated scrim"
```

---

## Task 3: PaneArrow Enum + focusPane in Model

**Files:**
- Modify: `BudahADE/Workspace/SplitPaneState.swift`
- Modify: `BudahADE/Task/TaskState.swift`
- Create: `BudahADETests/PaneFocusTests.swift`

Replace the old `PaneFocusDirection` + `moveFocus` with a directional `PaneArrow` + `focusPane(arrow:)`.

- [ ] **Step 1: Write the failing tests first**

Create `BudahADETests/PaneFocusTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PaneFocusTests -quiet 2>&1 | tail -20
```

Expected: compile error — `focusPane(arrow:)` and `PaneArrow` do not exist yet.

- [ ] **Step 3: Add PaneArrow to SplitPaneState.swift**

In `SplitPaneState.swift`, replace the `PaneFocusDirection` enum with `PaneArrow`:

Remove this block:
```swift
// MARK: - Pane Focus Direction

enum PaneFocusDirection {
    case next
    case previous
}
```

Add in its place:
```swift
// MARK: - Pane Arrow

enum PaneArrow {
    case left, right, up, down
}
```

- [ ] **Step 4: Add focusPane(arrow:) to TaskState.swift — keep moveFocus for now**

In `TaskState.swift`, ADD `focusPane(arrow:)` directly below the existing `moveFocus` method. Do NOT remove `moveFocus` yet — Task 4 removes it after the notification wiring is updated.

```swift
func focusPane(arrow: PaneArrow) {
    guard let split = splitPane else { return }
    let newFocus: PanePosition?
    switch (split.orientation, arrow) {
    case (.horizontal, .left):  newFocus = .primary
    case (.horizontal, .right): newFocus = .secondary
    case (.vertical, .up):      newFocus = .primary
    case (.vertical, .down):    newFocus = .secondary
    default:                    newFocus = nil   // wrong axis — no-op
    }
    guard let newFocus else { return }
    focusedPane = newFocus
    let tabId = focusedPane == .primary ? selectedTabId : splitPane?.secondarySelectedId
    if let tabId, let idx = tabs.firstIndex(where: { $0.id == tabId }), tabs[idx].isTerminal {
        terminals[tabId]?.focus()
    }
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BudahADE -only-testing:BudahADETests/PaneFocusTests -quiet 2>&1 | tail -20
```

Expected: all 5 tests pass.

- [ ] **Step 6: Build to confirm no compile errors**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` — `moveFocus` still exists so WorkspaceView compiles. `PaneFocusDirection` also still exists and is still referenced by `moveFocus`, so no orphaned-type errors.

- [ ] **Step 7: Commit model changes**

```bash
git add BudahADE/Workspace/SplitPaneState.swift BudahADE/Task/TaskState.swift BudahADETests/PaneFocusTests.swift
git commit -m "feat: add PaneArrow + focusPane(arrow:), remove moveFocus"
```

---

## Task 4: Wire Directional Cmd+Arrow Shortcuts

**Files:**
- Modify: `BudahADE/App/BudahADEApp.swift`
- Modify: `BudahADE/Workspace/WorkspaceView.swift`

Replace the old `Cmd+Option+Arrow` menu items and `focusNextPane`/`focusPrevPane` notifications with four directional ones.

- [ ] **Step 1: Update notification names in BudahADEApp.swift**

Find the `extension Notification.Name` block at the bottom of `BudahADEApp.swift`. Replace:

```swift
static let focusNextPane = Notification.Name("budahADE.focusNextPane")
static let focusPrevPane = Notification.Name("budahADE.focusPrevPane")
```

With:

```swift
static let focusLeftPane   = Notification.Name("budahADE.focusLeftPane")
static let focusRightPane  = Notification.Name("budahADE.focusRightPane")
static let focusTopPane    = Notification.Name("budahADE.focusTopPane")
static let focusBottomPane = Notification.Name("budahADE.focusBottomPane")
```

- [ ] **Step 2: Replace focus menu items in BudahADEApp.swift**

Find the `CommandGroup(after: .toolbar)` block. Remove:

```swift
Button("Focus Next Pane") {
    NotificationCenter.default.post(name: .focusNextPane, object: nil)
}
.keyboardShortcut(.rightArrow, modifiers: [.command, .option])

Button("Focus Previous Pane") {
    NotificationCenter.default.post(name: .focusPrevPane, object: nil)
}
.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
```

Add in their place:

```swift
Button("Focus Left Pane") {
    NotificationCenter.default.post(name: .focusLeftPane, object: nil)
}
.keyboardShortcut(.leftArrow, modifiers: .command)

Button("Focus Right Pane") {
    NotificationCenter.default.post(name: .focusRightPane, object: nil)
}
.keyboardShortcut(.rightArrow, modifiers: .command)

Button("Focus Top Pane") {
    NotificationCenter.default.post(name: .focusTopPane, object: nil)
}
.keyboardShortcut(.upArrow, modifiers: .command)

Button("Focus Bottom Pane") {
    NotificationCenter.default.post(name: .focusBottomPane, object: nil)
}
.keyboardShortcut(.downArrow, modifiers: .command)
```

- [ ] **Step 3: Replace notification handlers in WorkspaceView.swift**

In `WorkspaceView.coreView`, find:

```swift
.onReceive(NotificationCenter.default.publisher(for: .focusNextPane)) { _ in
    state.activeTask?.moveFocus(.next)
}
.onReceive(NotificationCenter.default.publisher(for: .focusPrevPane)) { _ in
    state.activeTask?.moveFocus(.previous)
}
```

Replace with:

```swift
.onReceive(NotificationCenter.default.publisher(for: .focusLeftPane)) { _ in
    state.activeTask?.focusPane(arrow: .left)
}
.onReceive(NotificationCenter.default.publisher(for: .focusRightPane)) { _ in
    state.activeTask?.focusPane(arrow: .right)
}
.onReceive(NotificationCenter.default.publisher(for: .focusTopPane)) { _ in
    state.activeTask?.focusPane(arrow: .up)
}
.onReceive(NotificationCenter.default.publisher(for: .focusBottomPane)) { _ in
    state.activeTask?.focusPane(arrow: .down)
}
```

- [ ] **Step 4: Remove moveFocus and PaneFocusDirection (now unused)**

In `TaskState.swift`, delete the `moveFocus` method:
```swift
// DELETE this entire method:
func moveFocus(_ direction: PaneFocusDirection) {
    guard splitPane != nil else { return }
    switch direction {
    case .next:
        focusedPane = focusedPane == .primary ? .secondary : .primary
    case .previous:
        focusedPane = focusedPane == .secondary ? .primary : .secondary
    }
    let tabId = focusedPane == .primary ? selectedTabId : splitPane?.secondarySelectedId
    if let tabId, let idx = tabs.firstIndex(where: { $0.id == tabId }), tabs[idx].isTerminal {
        terminals[tabId]?.focus()
    }
}
```

In `SplitPaneState.swift`, delete the `PaneFocusDirection` enum:
```swift
// DELETE this entire block:
// MARK: - Pane Focus Direction

enum PaneFocusDirection {
    case next
    case previous
}
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -scheme BudahADE -quiet 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add BudahADE/App/BudahADEApp.swift BudahADE/Workspace/WorkspaceView.swift BudahADE/Task/TaskState.swift BudahADE/Workspace/SplitPaneState.swift
git commit -m "feat: directional Cmd+Arrow pane focus, replace Cmd+Option+Arrow"
```

---

## Task 5: Shift+Cmd+B Always Creates a New Browser Tab

**Files:**
- Modify: `BudahADE/Workspace/WorkspaceView.swift`

Currently `Shift+Cmd+B` fires `.toggleBrowser` which finds-or-creates a single browser tab. Change it to always create a new browser tab in the focused pane.

- [ ] **Step 1: Update the toggleBrowser handler in WorkspaceView.swift**

Find:

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleBrowser)) { _ in
    if let task = state.activeTask, task.mode == .build {
        if let existing = task.tabs.first(where: { $0.isBrowser }) {
            task.selectTab(existing.id)
        } else {
            task.createBrowserTab()
        }
    }
}
```

Replace with:

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleBrowser)) { _ in
    if let task = state.activeTask, task.mode == .build {
        if task.focusedPane == .secondary && task.splitPane != nil {
            task.createBrowserTabInSecondaryPane()
        } else {
            task.createBrowserTab()
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all tests**

```bash
xcodebuild test -scheme BudahADE -quiet 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Workspace/WorkspaceView.swift
git commit -m "feat: Shift+Cmd+B always creates new browser tab in focused pane"
```

---

## Final Verification

- [ ] Build the app and do a manual smoke test:
  - File tree shows files in the Files panel
  - Creating a split dims the inactive pane; clicking switches focus with animated transition
  - `Cmd+Left`/`Cmd+Right` switches pane focus on a horizontal split; `Cmd+Up`/`Cmd+Down` on a vertical split; wrong-axis arrows are no-ops
  - `Cmd+T` creates a new terminal tab
  - `Shift+Cmd+B` always creates a new browser tab (in the focused pane if split)
