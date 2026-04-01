# BudahADE — Tab Plan Roadmap

_Last updated: 2026-04-01. Cross-referenced against codebase (122 Swift files)._

---

## Current State

122 Swift files across 14 modules. Two modes per task: **Plan** (multi-role AI chat tabs) and **Build** (terminal + git + spec tracking).

### What Works
- **5 plan roles** with distinct prompts, tool constraints, and model defaults
- **Multi-tab conversations** with persistence to `.budahade/conversations/`
- **Hand-off** between tabs (manual: click → pick target)
- **Spec Author** generates spec documents in chat
- **Approve & Build** — saves spec via `SpecVersionManager` → `.budahade/spec.md`, fires 3-step overlay, auto-switches to Build mode
- **Builder prompt** in `AgentPrompts.builderLaunchCommand()` — reads spec, works sequentially, reports to `build-status.json`
- **SpecWatcher** with adaptive polling (2s normal / 0.5s rapid)
- **BuildStatusWatcher** polls `build-status.json` with elapsed time tracking
- **SpecBlockGraphView** — per-item blocks with pulsing active state, hover tooltips, percentage label
- **SpecPanelView** — section-grouped checklist, progress header, build status row, block graph
- **Git sidebar** — branch header, changes list, AI commits, commit timeline, diff modal
- **Session persistence** via tmux + scrollback capture
- **Browser panel** — `BrowserPanelView`, `BrowserState`, `DevServerDetector`, `DevServerManager`, `PortAllocator`, `BrowserPopoutWindow`, `SplitPaneState` all exist and are wired into `TaskState` / `WorkspaceView`

---

## Phase 1 — Close the Spec > Builder Loop ✓ COMPLETE

### 1.1 Fix SpecParser.findSpecFiles() ✓
`findSpecFiles()` now scans `.budahade/spec.md` in addition to root-level patterns. (`SpecParser.swift:171-175`)

### 1.2 Approve & Build transition ✓
`handleApprove()` counts items, sends inline confirmation ("→ spec.md written — N items"), fires `onApproveToBuild`. `WorkspaceView.startBuildTransition()` runs 3-step overlay → `enterBuildMode()` → auto-dismiss. (`PlanChatView.swift:674-689`, `WorkspaceView.swift:274-289`)

### 1.3 Block graph component ✓
`SpecBlockGraphView` with 8×14px blocks, pulsing active state, hover tooltips, percentage label. Integrated into `SpecPanelView` between header and checklist. (`SpecBlockGraphView.swift`, `SpecPanelView.swift:40`)

### 1.4 Elapsed time in status line ✓
`BuildStatusState.taskStartedAt` + `elapsed` computed property. `BuildStatusWatcher` resets timestamp on task transitions. (`BuildStatusState.swift:22-26`, `BuildStatusWatcher.swift:82-83`)

---

## Phase 2 — In-App Browser

### 2.A — Browser Panel MVP — PARTIALLY DONE

**Done:**
- `BrowserState`, `BrowserPanelView`, `BrowserPanel`, `BrowserPopoutWindow` — all exist
- `DevServerDetector` — scans for vite/next/package.json/Django/Go/Rust configs
- `DevServerManager` — process lifecycle, stdout URL detection
- `PortAllocator` — port windowing with per-project ranges
- `SplitPaneState` — split pane state wired into `WorkspaceView` and `TaskState`
- `Cmd+Shift+B` toggle in WorkspaceView

**Still needed:**
- [ ] Verify browser tab is fully creatable from tab bar "+" menu
- [ ] Confirm port badge on task card in rail while server runs
- [ ] Confirm process cleanup on AppDelegate termination (orphan port sweep)
- [ ] Manual smoke test: open browser tab in Vite project → dev server starts, localhost loads

### 2.B — Intelligence Layer — NOT DONE

- [ ] `URLDetector` — parse dev server stdout for `localhost:\d+`, auto-navigate on first detection
- [ ] Detected URLs dropdown in browser chrome for multiple URLs
- [ ] `SmartReloader` — FSEvents file watcher + build-complete signal → `WKWebView.reload()`

### 2.C — Agent Control — NOT DONE

- [ ] `BrowserHTTPServer` on `NWListener` (default port `9222`), header-routed by `X-Task-Id`
- [ ] Endpoints: `/navigate`, `/screenshot`, `/click`, `/type`, `/dom`, `/evaluate`, `/console`, `/network`, `/url`, `/reload`, `/capabilities`
- [ ] Console + network capture via `WKScriptMessageHandler` — ring buffer in `BrowserState`
- [ ] Server lifecycle tied to task open/close

### 2.D — Element Picker — NOT DONE

- [ ] `ElementPicker` — JS overlay via `WKUserScript`, highlight on hover, capture on click (`Cmd+Shift+I`)
- [ ] Context bundle: CSS selector path + outer HTML + cropped screenshot + computed styles
- [ ] Chat injection — structured block with screenshot into active agent input
- [ ] Pop-out window — `NSPanel` with dock-back button (stub exists in `BrowserPopoutWindow.swift`)

---

## Phase 3 — Plan Mode Polish — NOT DONE

### 3.1 Approve/Edit state transitions
`handleApprove()` fires `onApproveToBuild` but `PlanConversationState` has no `.specGenerated` / `.specEdited` states. UI affordances don't reflect spec lifecycle.
- [ ] Add `.specGenerated` and `.specEdited` cases to `PlanConversationState`
- [ ] Update `handleApprove()` to transition state
- [ ] Update plan chat UI to reflect state (edit button, re-approve affordance)

### 3.2 Guided workflow routing
After a role completes substantive output, suggest the natural next step.
- [ ] Detect role completion heuristic (last message from assistant, not a question)
- [ ] Show "Hand off to {next role}?" suggestion: Researcher → Ideator → Designer → Developer → Spec Author
- [ ] Dismissable — don't re-show if dismissed

### 3.3 Canvas integration (future)
The 56-file canvas system is powerful but disconnected. Deferred.

---

## Phase 4 — Stability Bugs — NOT DONE

### 4.1 ConnectionSummaryManager subprocess timeout (HIGH)
`process.waitUntilExit()` at `ConnectionSummaryManager.swift:80` blocks forever if Haiku hangs. Three concurrent hangs exhaust all slots silently.
- [ ] Add 10-second timeout + `process.terminate()` on expiry

### 4.2 Git operations silently discard errors (MEDIUM)
`stage()`, `stageAll()`, `commit()`, `checkout()` at `GitRepository.swift:85-115` do not throw. A failed `git add` or `git commit` returns silently.
- [ ] Convert to `async throws`, check `terminationStatus != 0`, surface errors to Git panel UI

### 4.3 Worktree creation failure is console-only (MEDIUM)
`WorkspaceState.swift:94` starts terminal even if worktree failed — task proceeds as if worktree exists.
- [ ] Propagate worktree failure to task creation flow, block task creation on failure

### 4.4 HarnessMiddleware error enum comparison (LOW-MEDIUM)
`HarnessMiddleware.swift:669`: `session.status == .error("")` only matches empty-string errors. Any `.error("exit code 1")` is silently missed.
- [ ] Replace with `if case .error = session.status { ... }`

---

## Phase 5 — Hardening — NOT DONE

### 5.1 Replace git polling with FSEvents
`GitRepository` polls every 1.5s (5 git subprocess calls each). Replace with `FSEventStreamCreate`.
- [ ] Implement FSEvents watcher for worktree directory
- [ ] Debounce at 300ms, replace polling timer

### 5.2 Claude CLI path detection
`AICommitService.swift:32` hardcodes `/usr/local/bin/claude`.
- [ ] Use `which claude` at startup, cache result, make user-configurable in settings

### 5.3 Conversation search
- [ ] Search across plan tab histories (full-text across `.budahade/conversations/`)
- [ ] UI: search bar in plan sidebar, highlight matches in chat

### 5.4 Test Coverage

#### Existing
- `SpecParserTests` — title, sections, progress, findSpecFiles, nil/missing
- `SpecVersionManagerTests` — versioned spec creation, active spec read
- `PlanBuildBridgeTests` — build context block generation

#### Still needed (from Phase 1)
- [ ] `findSpecFiles` returns `.budahade/spec.md` when it exists
- [ ] `findSpecFiles` returns both root `*-spec.md` AND `.budahade/spec.md` without duplicates
- [ ] `elapsed` returns nil when `taskStartedAt` is nil / status is not `.working`
- [ ] `elapsed` returns formatted string when working with a start time
- [ ] `taskStartedAt` resets when task title changes
- [ ] Block graph block state logic (completed/active/blocked/pending)
- [ ] `approve()` → `findSpecFiles()` round trip
- [ ] `handleApprove()` fires `onApproveToBuild` with correct count
- [ ] `enterBuildMode()` creates `builderPanel` only when spec exists

#### Still needed (from Phase 2)
- [ ] `DevServerDetector` project detection (vite/next/npm/Django/Go/Rust)
- [ ] `PortAllocator` windowing + skip-in-use + release
- [ ] `SplitPaneState` split/merge/focus logic
- [ ] Browser tab session persistence round-trip
- [ ] `URLDetector` pattern matching (Phase 2.B)
- [ ] Page content extraction (Phase 2.D)

---

## What's Next

**Immediate (unblock Phase 2.A smoke test):**
1. Manually verify browser tab creation from "+" menu — confirm wiring is complete end-to-end
2. Fix Phase 4.4 (1-line fix): `HarnessMiddleware.swift:669` — `if case .error = session.status`
3. Fix Phase 4.1: add 10s timeout to `ConnectionSummaryManager` — high-severity silent failure

**Next sprint (Phase 2.B):**
- `URLDetector` + detected-URL dropdown in browser chrome
- `SmartReloader` FSEvents watcher

**Parallel (always-on hygiene):**
- Phase 4.2: make git operations throw
- Phase 5.2: dynamic Claude CLI path detection

---

## Design Tokens

- **Background**: `#0c0c0e`
- **Surface**: `#111115`
- **Accent**: `#7c6cf0`
- **Design language**: Linear/Vercel-influenced dark theme. Tight density, no decorative chrome.

_Font migration (Geist Sans/Mono, Gelasio) tracked separately — keep system fonts for now._
