# Pane UX Improvements — Design Spec
Date: 2026-03-31

## Overview

Four focused improvements to the split-pane workspace:

1. Visual dim on inactive pane
2. Directional pane focus via `Cmd+Arrow`
3. `Shift+Cmd+B` creates a new browser tab directly
4. File tree bug fix

---

## 1. Inactive Pane Dim

**Goal:** Make it immediately clear which pane is focused without relying solely on the thin accent border.

**Approach:** Overlay a `Color.black.opacity(0.25)` scrim on each pane's `VStack` (tab bar + content) when it is not focused. This dims the pane without reducing `.opacity` on the container (which would affect text legibility and interactivity).

**Implementation:**
- In `WorkspaceView.terminalArea`, each split pane's `VStack` gets an `.overlay` with a `Color.black.opacity(task.focusedPane == .primary ? 0 : 0.25)` for the primary pane, and the inverse for the secondary pane.
- Animated with `.animation(.easeInOut(duration: 0.15), value: task.focusedPane)`.
- The existing `paneFocusBorder` accent ring is kept as a secondary indicator on the focused pane.
- Only applies in split mode. Single-pane view is unaffected.

---

## 2. Directional Cmd+Arrow Pane Focus

**Goal:** Replace the awkward `Cmd+Option+Arrow` shortcut with the more intuitive `Cmd+Arrow`, with directional semantics.

**Approach:** Two new notifications replace the old next/previous focus notifications. `TaskState` resolves direction against split orientation.

**Shortcut mapping:**
- Horizontal split: `Cmd+Left` → primary pane, `Cmd+Right` → secondary pane
- Vertical split: `Cmd+Up` → primary pane, `Cmd+Down` → secondary pane
- Mismatched axis (e.g. `Cmd+Up` on a horizontal split) → no-op

**Implementation:**

In `BudahADEApp.swift`:
- Remove the `Focus Next Pane` / `Focus Previous Pane` menu items with `Cmd+Option+Arrow` bindings.
- Add four new menu items: `Focus Left Pane` (`Cmd+Left`), `Focus Right Pane` (`Cmd+Right`), `Focus Top Pane` (`Cmd+Up`), `Focus Bottom Pane` (`Cmd+Down`), each posting a new notification.

New notifications: `.focusLeftPane`, `.focusRightPane`, `.focusTopPane`, `.focusBottomPane`. Remove `.focusNextPane` and `.focusPrevPane` from the `Notification.Name` extension — nothing else references them.

In `TaskState`:
- Add `func focusPane(arrow: PaneArrow)` where `PaneArrow` is an enum `{ left, right, up, down }`.
- Logic: map `(split.orientation, arrow)` → `.primary` or `.secondary`, or no-op if axes don't match.
- Replace the `moveFocus(.next/.previous)` calls in `WorkspaceView` with the four new notification handlers.
- `moveFocus` can be removed or kept for backward compat — remove it since nothing else calls it.

---

## 3. Shift+Cmd+B — New Browser Tab

**Goal:** A direct shortcut to create a new browser tab in the focused pane, without toggling.

**Current state:** `toggleBrowser` (`Cmd+Shift+B` may or may not be bound — check `BudahADEApp.swift`) finds or creates a single browser tab. There's no "always create new" shortcut.

**Approach:**
- Add a new notification `.newBrowserTab`.
- In `WorkspaceView`, handle `.newBrowserTab`: call `task.createBrowserTab()` for primary pane, or `task.createBrowserTabInSecondaryPane()` if `task.focusedPane == .secondary`.
- In `BudahADEApp.swift`, bind `Shift+Cmd+B` to this notification.
- `Cmd+T` remains unchanged (always terminal).

---

## 4. File Tree Bug Fix

**Goal:** The Files panel shows an empty list when a task's worktree path is not accessible via `FileManager.contentsOfDirectory(atPath:)`.

**Root cause (hypothesis):** `contentsOfDirectory(atPath:)` does not expand `~` or relative paths. If `worktreePath` is stored with a tilde or as a relative path, the scan silently returns `[]`. Verify by inspecting the actual string value at runtime vs. what `FileManager` expects (an absolute POSIX path).

**Fix:**
- In `FileTreeNode.scan(directory:)`, resolve the path before use:
  ```swift
  let resolved = (directory as NSString).expandingTildeInPath
  guard let entries = try? fm.contentsOfDirectory(atPath: resolved) else { return [] }
  ```
- Also apply the same expansion in `FileWatcher.start()` when calling `open(path, O_EVTONLY)`.
- If the path is already absolute (confirmed by inspection), add a debug `print` to surface the actual error from `contentsOfDirectory` using the throwing variant to identify the real cause.

**Secondary investigation:** If tilde expansion isn't the issue, use the throwing variant `try fm.contentsOfDirectory(atPath:)` (catch and print) to surface the actual `NSError` during development.

---

## Files Touched

| File | Change |
|------|--------|
| `BudahADE/App/BudahADEApp.swift` | Replace focus shortcuts; add `Shift+Cmd+B`; add new notification names |
| `BudahADE/Task/TaskState.swift` | Add `PaneArrow` enum + `focusPane(arrow:)`; remove `moveFocus` |
| `BudahADE/Workspace/SplitPaneState.swift` | Add `PaneArrow` enum (or put in TaskState — same file is fine) |
| `BudahADE/Workspace/WorkspaceView.swift` | Add pane scrim overlay; wire new notifications; add `.newBrowserTab` handler |
| `BudahADE/FileTree/FileTreeNode.swift` | Tilde-expand path in `scan()` |
| `BudahADE/FileTree/FileWatcher.swift` | Tilde-expand path in `start()` |

Total: 6 files. All changes are self-contained with no new dependencies.
