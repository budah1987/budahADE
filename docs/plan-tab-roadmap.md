# BudahADE — Plan Tab Roadmap

## Current State (Conversation-Planner branch, ec9b800)

127 Swift files across 13 modules. Two modes per task: **Plan** (multi-role AI chat tabs) and **Build** (terminal + git + spec tracking).

### What Works
- **5 plan roles** with distinct prompts, tool constraints, and model defaults
- **Multi-tab conversations** with persistence to `.budahade/conversations/`
- **Hand-off** between tabs (manual: click → pick target)
- **Spec Author** can generate spec documents in chat
- **Approve button** saves spec via `SpecVersionManager` → `.budahade/spec.md` + versioned copies
- **Builder prompt** in `AgentPrompts.builderLaunchCommand()` — reads spec, works sequentially, reports to `build-status.json`
- **SpecWatcher** with adaptive polling (2s normal / 0.5s rapid)
- **BuildStatusWatcher** polls `build-status.json` for real-time progress
- **SpecStripView** with section-segmented progress bar (inline + compact layouts)
- **SpecPanelView** with section-grouped checklist, progress header, build status row
- **Git sidebar** with branch header, changes list, AI commits, commit timeline, diff modal
- **Session persistence** via tmux + scrollback capture

---

## Spec > Builder — Gap Analysis

### The One Critical Bug
`SpecParser.findSpecFiles()` only scans worktree root for `*-spec.md` patterns. But `SpecVersionManager.approve()` writes to `.budahade/spec.md`. **The spec panel never sees approved specs.** Fix: also scan `.budahade/spec.md`.

### Missing Connections (3 items)
1. **No mode transition on approve** — `handleApprove()` saves the spec and sends a chat message, but doesn't switch to Build mode
2. **No transition UX** — no visual feedback during the Plan → Build handoff
3. **No block graph visualization** — the spec describes per-item blocks with pulsing/color states and tooltips. Current SpecStripView has a flat segmented bar

### What the Spec Calls For (vs what exists)

| Spec Requirement | Status | Notes |
|-----------------|--------|-------|
| Approve writes to `.budahade/spec.md` | Done | `SpecVersionManager.approve()` |
| Builder prompt reads spec + reports JSON | Done | `AgentPrompts.builderPrompt()` |
| BuildStatusWatcher polls JSON | Done | Adaptive 2s/0.5s polling |
| SpecParser → SpecState | Done | Section-aware with progress |
| SpecPanelView consumes both signals | Done | Checklist + build status row |
| **Approve auto-switches to Build** | **Missing** | Approve IS the confirmation — no extra prompt |
| **Transition overlay** | **Missing** | ~2s overlay with status lines |
| **Block graph (per-item blocks)** | **Missing** | New component in SpecPanelView |
| **Pulsing active / red blocked states** | **Partial** | Exists in SpecPanelView task rows, not in block graph |
| **Hover tooltips on blocks** | **Missing** | — |
| **Elapsed time in status line** | **Missing** | BuildStatusState has no timestamp tracking |

---

## Phase 1 — Close the Spec > Builder Loop ✓

> **Completed.** All four items shipped on `tab-plan` branch.

### 1.1 Fix SpecParser.findSpecFiles() ✓
`findSpecFiles()` now scans `.budahade/spec.md` in addition to root-level patterns. (`SpecParser.swift:171-175`)

### 1.2 Approve & Build transition ✓
`handleApprove()` counts items, sends inline confirmation ("→ spec.md written — N items"), and fires `onApproveToBuild`. `WorkspaceView.startBuildTransition()` runs 3-step overlay → `enterBuildMode()` → auto-dismiss. (`PlanChatView.swift:674-689`, `WorkspaceView.swift:226-250`)

### 1.3 Block graph component ✓
`SpecBlockGraphView` with 8×14px blocks, pulsing active state, hover tooltips, percentage label. Integrated into `SpecPanelView` between header and checklist, stays visible when collapsed. (`SpecBlockGraphView.swift`, `SpecPanelView.swift:40`)

### 1.4 Elapsed time in status line ✓
`BuildStatusState.taskStartedAt` + `elapsed` computed property. `BuildStatusWatcher` resets timestamp on task transitions. (`BuildStatusState.swift:22-34`, `BuildStatusWatcher.swift:82-84`)

---

## Phase 2 — In-App Browser

> Full spec: `docs/specs/2026-03-23-browser-panel.md`

### Current State
`BrowserTileView.swift` is a full WKWebView with URL bar, back/forward/reload — but only available as a canvas tile (unused in current chat-based Plan mode). `WebViewStore` manages WKWebView lifecycle with KVO-based state tracking.

### 2.A — Browser Panel MVP
_Goal: User can see localhost preview alongside terminal._

- `BrowserState` + `BrowserPanelView` — reuse `WebViewStore` pattern, add port indicator
- Content toggle in `WorkspaceView` — `Cmd+Shift+B` opacity-switches terminal ↔ browser
- `DevServerDetector` — scan worktree for package.json/vite.config/next.config, return dev command + port strategy
- `DevServerManager` — per-task process lifecycle, port assignment (`3000 + taskIndex`), process group cleanup
- Wire into `TaskState` — auto-start dev server on task open, stop on close, port badge on task card
- Process safety — AppDelegate termination cleanup + orphan port sweep on launch

### 2.B — Intelligence Layer
_Goal: Browser auto-navigates and reloads on code changes._

- `URLDetector` — parse dev server stdout for `localhost:\d+` patterns, auto-navigate on first detection
- Detected URLs dropdown — when multiple URLs found, show picker in browser chrome
- `SmartReloader` — FSEvents file watcher + build-complete signal from stdout → `WKWebView.reload()`

### 2.C — Agent Control
_Goal: Agents can control the browser via HTTP REST API._

- `BrowserHTTPServer` on `NWListener` — single port (default `9222`), header-routed by `X-Task-Id`
- Endpoints: `/navigate`, `/screenshot`, `/click`, `/type`, `/dom`, `/evaluate`, `/console`, `/network`, `/url`, `/reload`, `/capabilities`
- Console + network capture via `WKScriptMessageHandler` — ring buffer in `BrowserState`
- Server lifecycle tied to task open/close

### 2.D — Interaction
_Goal: User points at element, AI gets full context._

- `ElementPicker` — JS overlay via `WKUserScript`, highlight on hover, capture on click (`Cmd+Shift+I`)
- Context bundle: CSS selector path + outer HTML + cropped screenshot + computed styles + parent context
- Chat injection — structured block with screenshot attached into active agent input
- Pop-out window — `NSPanel` with dock-back button

---

## Phase 3 — Plan Mode Polish

### 3.1 Approve/Edit state transitions
Should transition `PlanConversationState` from `.chatting` → `.specGenerated` → `.specEdited` and update UI affordances.

### 3.2 Guided workflow routing
After a role completes substantive output, suggest next step: "Hand off to {next role}?" Based on the natural flow: Researcher → Ideator → Designer → Developer → Spec Author.

### 3.3 Canvas integration (future)
The 56-file canvas system is powerful but disconnected. Could serve as a visual spec builder or architecture diagram surface.

---

## Phase 4 — Stability

### 4.1 ConnectionSummaryManager subprocess timeout (HIGH)
`process.waitUntilExit()` blocks forever if the Haiku subprocess hangs. The class caps concurrent summaries at 3 — three simultaneous hangs silently exhaust all slots and no new summaries can be generated until the app restarts.
**Fix:** 10-second timeout + `process.terminate()` on expiry.

### 4.2 Git operations silently discard errors (MEDIUM)
`stage()`, `commit()`, and `checkout()` in `GitRepository.swift` do not throw. A failed `git add` or `git commit` returns silently — the user sees success when the operation may have failed.
**Fix:** Convert to `throws`, check `process.terminationStatus != 0`, surface errors to the Git panel UI.

### 4.3 Worktree creation failure is console-only (MEDIUM)
If `git worktree add` fails (path conflict, disk full), the task is still created and proceeds as if the worktree exists. The failure is logged to console only.
**Fix:** Propagate worktree creation failure to the task creation flow and block task creation on failure.

### 4.4 Fragile error enum comparison in HarnessMiddleware (LOW-MEDIUM)
`session.status == .error("")` only matches empty-string errors. Any real error with an associated value (e.g. `.error("exit code 1")`) is silently missed.
**Fix:** `if case .error = session.status { ... }`

---

## Phase 5 — Hardening

### 5.1 Replace git polling with FSEvents
GitRepository polls every 1.5s (5 git subprocess calls each). Replace with file system events.

### 5.2 Claude CLI path detection
`AICommitService` hardcodes `/usr/local/bin/claude`. Use `which claude` or make configurable.

### 5.3 Conversation search
Search across plan tab histories.

### 5.4 Test Plan

#### Existing Coverage
- `SpecParserTests` — title, sections, progress, findSpecFiles (root patterns), nil/missing
- `SpecVersionManagerTests` — versioned spec creation, active spec read
- `PlanBuildBridgeTests` — build context block generation from spec + agent output

#### Unit Tests (new)

**SpecParser — `.budahade/spec.md` discovery**
- [ ] `findSpecFiles` returns `.budahade/spec.md` when it exists
- [ ] `findSpecFiles` returns both root `*-spec.md` AND `.budahade/spec.md` without duplicates
- [ ] `findSpecFiles` ignores `.budahade/spec.md` when it doesn't exist

**BuildStatusState — elapsed time**
- [ ] `elapsed` returns nil when `taskStartedAt` is nil
- [ ] `elapsed` returns nil when status is not `.working`
- [ ] `elapsed` returns formatted string ("Xs", "Xm Ys") when working with a start time
- [ ] `taskStartedAt` resets when task title changes (via BuildStatusWatcher)
- [ ] `taskStartedAt` initializes on first `.working` status even without title change

**SpecBlockGraphView — block state logic**
- [ ] Completed task returns `.completed`
- [ ] First unchecked task with `buildStatus.working` returns `.active`
- [ ] First unchecked task with `buildStatus.blocked` returns `.blocked`
- [ ] Non-active unchecked task returns `.pending`
- [ ] `currentTaskIndex` from build-status.json overrides first-unchecked fallback

**SpecVersionManager — approve-to-discovery round trip**
- [ ] `approve()` writes to `.budahade/spec.md`, then `findSpecFiles()` discovers it
- [ ] `approve()` twice increments version, both versions listed, active spec is latest

#### Integration Tests (new)

**Approve & Build flow**
- [ ] `handleApprove()` calls `SpecVersionManager.approve()` and returns correct item count
- [ ] Item count matches number of `- [ ]` and `- [x]` lines in content
- [ ] `onApproveToBuild` callback fires with correct count

**Builder launch**
- [ ] `enterBuildMode()` creates `builderPanel` when spec exists and panel is nil
- [ ] `enterBuildMode()` does NOT create `builderPanel` when no spec exists
- [ ] `enterBuildMode()` creates a regular CLI tab when `tabs` is empty
- [ ] `stopBuilder()` nils out `builderPanel` and closes drawer
- [ ] `closeAllTerminals()` calls `stopBuilder()`

**SpecWatcher integration**
- [ ] SpecWatcher picks up `.budahade/spec.md` written by `SpecVersionManager.approve()`
- [ ] SpecState updates within one polling cycle (2s) after spec file write

#### Manual Smoke Tests

**Full spec-to-builder workflow**
- [ ] Create task → Plan mode → open Spec Author tab
- [ ] Have Spec Author generate a spec with `- [ ]` items
- [ ] Click "Approve & Build" → confirm inline message shows "→ spec.md written — N items"
- [ ] 3-step overlay appears and auto-dismisses (~2s)
- [ ] App switches to Build mode automatically
- [ ] Builder drawer is open, builder terminal is running Claude with builder prompt
- [ ] Spec strip shows builder toggle button with status dot
- [ ] Close drawer → CLI tabs are visible and untouched
- [ ] Reopen drawer → builder output is still there

**Block graph**
- [ ] Block graph appears in SpecPanelView between header and checklist
- [ ] One block per spec item, 8×14px, 2px gaps
- [ ] Completed items show green, pending show dim
- [ ] Active item pulses (opacity animation)
- [ ] Blocked item shows red (manually write `"status": "blocked"` to build-status.json)
- [ ] Hover tooltip shows section ID + task title
- [ ] Percentage label updates as items complete
- [ ] Collapse toggle hides checklist but keeps block strip visible

**Builder drawer UX**
- [ ] Drawer overlays CLI terminals, does not push them down
- [ ] Drawer header shows status dot, "Builder", current task, elapsed time
- [ ] Close button (chevron-up) closes drawer
- [ ] Spec strip toggle button reopens drawer
- [ ] Toggle button dot color matches build status (accent/red/green/gray)
- [ ] Elapsed time ticks up while builder is working

**Edge cases**
- [ ] Approve with no assistant messages → no-op (no crash)
- [ ] Switch Plan → Build → Plan → Build → builder panel persists, not duplicated
- [ ] Spec with 0 checkbox items → block graph hidden, no crash
- [ ] Build-status.json missing → graceful idle state, no errors
- [ ] Kill builder mid-task → status dot goes gray, drawer still accessible

### Phase 2 — In-App Browser

#### Unit Tests (new)

**WebViewStore — lifecycle & navigation**
- [ ] `ensureWebView()` creates WKWebView on first call, returns same instance on second
- [ ] `navigate(to:)` loads the given URL in the web view
- [ ] `navigate(to:)` auto-prepends `https://` when URL has no scheme
- [ ] `goBack()` / `goForward()` forward to WKWebView (no crash when history is empty)
- [ ] `title` updates via KVO when page finishes loading
- [ ] `canGoBack` / `canGoForward` update via KVO after navigation

**TabType — browser discrimination**
- [ ] TabInfo with `.browser` type round-trips through encode/decode
- [ ] TabInfo with `.terminal` type is unaffected by browser additions
- [ ] Creating a browser tab assigns a unique UUID distinct from terminal tabs
- [ ] `isTerminal` / `isBrowser` convenience properties return correct values
- [ ] TabInfo `Equatable` includes `tabType` in comparison

**DevServerDetector — project detection**
- [ ] Detects vite project (vite.config.ts → `npx vite --port N`)
- [ ] Detects next.js project (next.config.js → `npx next dev --port N`)
- [ ] Detects generic npm project (package.json with "dev" script → `npm run dev` with PORT env)
- [ ] Detects Django project (manage.py → `python manage.py runserver N`)
- [ ] Detects Go project with net/http (go.mod → `go run .` with stdout parsing)
- [ ] Detects Rust project with axum/actix (Cargo.toml → `cargo run` with stdout parsing)
- [ ] Returns nil for non-web project (empty directory, no config files)
- [ ] `shellCommand(port:)` correctly injects port for each injection type

**PortAllocator — port windowing**
- [ ] First project allocates ports in 3000-3010 range
- [ ] Second project allocates ports in 3012-3022 range (+2 gap)
- [ ] `allocate()` skips ports that are already in use (bind check)
- [ ] `release(port:)` frees port for reuse
- [ ] `releaseAll(projectIndex:)` frees all ports for a project
- [ ] Returns nil when window is exhausted (11 ports used)

**DevServerManager — process lifecycle**
- [ ] `start()` spawns process with correct shell command
- [ ] `isRunning` is true after start, false after stop
- [ ] `stop()` sends SIGTERM to process group
- [ ] URL detection regex matches `http://localhost:3001` in stdout
- [ ] URL detection regex matches `http://127.0.0.1:8080` in stdout
- [ ] `detectedURL` set immediately for non-stdout port injection types

**SplitPaneState — split logic**
- [ ] `splitTab` with `.right` zone puts dragged tab in secondary pane
- [ ] `splitTab` with `.left` zone puts dragged tab in primary pane, current in secondary
- [ ] `closeSplit()` merges panes, resets focusedPane to `.primary`
- [ ] Closing secondary tab's tab also closes the split
- [ ] `moveFocus(.next)` toggles between `.primary` and `.secondary`

**SessionPersistence — browser tabs**
- [ ] `TabSnapshot` with `isBrowser: true` and `browserURL` round-trips through JSON
- [ ] `TabSnapshot` with `isBrowser: nil` is backwards-compatible (treated as terminal)
- [ ] Restored browser tab navigates to saved URL

**URL detection — pattern matching** (Phase 2.B — not yet implemented)
- [ ] Detects `http://localhost:3000` in plain text
- [ ] Detects `https://example.com/path` in plain text
- [ ] Detects `localhost:XXXX` without scheme prefix
- [ ] Does not false-positive on non-URL text (e.g. "use port 3000 for this")
- [ ] Returns multiple URLs when text contains more than one
- [ ] Ignores duplicate URLs in same message

**Page content extraction** (Phase 2.D — not yet implemented)
- [ ] `extractPageText()` returns `document.body.innerText` via JS evaluation
- [ ] `extractPageText()` returns nil/empty for about:blank
- [ ] Extracted text is truncated to a sane limit (e.g. 20k chars)

#### Integration Tests (new)

**Browser tab creation**
- [ ] `createBrowserTab(url:)` adds a browser tab to `tabs` array
- [ ] `createBrowserTab(url:)` selects the new tab
- [ ] Browser tab appears in TerminalTabBar alongside terminal tabs
- [ ] Closing browser tab removes it and selects adjacent tab
- [ ] `closeAllTerminals()` also closes browser tabs and stops dev server

**Dev server integration**
- [ ] `createBrowserTab()` on web project detects config and starts dev server
- [ ] `createBrowserTab()` on non-web project opens blank browser (no crash)
- [ ] Second `createBrowserTab()` reuses existing dev server (no duplicate)
- [ ] `stopDevServer()` kills process group and releases port
- [ ] Browser navigates to `http://localhost:{port}` after server starts

**Split pane integration**
- [ ] Dragging tab to right drop zone creates horizontal split
- [ ] Dragging tab to bottom drop zone creates vertical split
- [ ] Split uses `PaneLayout` with drag-to-resize divider
- [ ] Closing either pane's tab closes the split
- [ ] `Cmd+Opt+Right/Left` moves focus between panes
- [ ] `Cmd+Opt+Return` closes the split
- [ ] Focused pane has accent border indicator

**Session persistence — browser**
- [ ] Browser tabs saved in `tabs.json` with `isBrowser: true` and `browserURL`
- [ ] Restored browser tabs reload their saved URL
- [ ] Terminal tabs still restore correctly (backwards compatible)
- [ ] Mixed terminal + browser tabs restore in correct order

**URL interception → browser tab** (Phase 2.B — not yet implemented)
- [ ] Detected URL in chat message shows "Open in-app" button
- [ ] Clicking "Open in-app" calls `createBrowserTab(url:)` with correct URL
- [ ] Detected `localhost:XXXX` in terminal scrollback shows affordance
- [ ] Opening URL that matches existing browser tab selects it instead of duplicating

**Page content → chat injection** (Phase 2.D — not yet implemented)
- [ ] "Show to Claude" extracts page text and sends as user message
- [ ] Injected message includes page URL as attribution
- [ ] "Show to Claude" with empty page content shows no-op / warning

#### Manual Smoke Tests

**Browser tab basics**
- [ ] Click "+" in tab bar → option to add Browser tab
- [ ] Browser tab shows URL bar, back/forward/reload buttons
- [ ] Type URL → page loads, title updates in tab
- [ ] Back/forward navigation works across page history
- [ ] Tab shows globe icon or favicon, not terminal icon
- [ ] Multiple browser tabs can coexist with terminal tabs
- [ ] Middle-click closes browser tab
- [ ] Switching between browser and terminal tabs preserves state in both

**Tab drag-to-split**
- [ ] Drag terminal tab to right edge → horizontal split with accent highlight on drop zone
- [ ] Drag browser tab to bottom edge → vertical split
- [ ] Drop zone highlight appears with subtle animation during drag hover
- [ ] Divider is draggable to resize panes (0.15–0.85 ratio)
- [ ] Cmd+Opt+Right/Left toggles focus between panes
- [ ] Focused pane has accent border, unfocused has no border
- [ ] Cmd+Opt+Return closes split, panes merge
- [ ] Dragging a tab when already split → no-op (overlay hidden)

**Dev server auto-start**
- [ ] Open browser tab in Vite project → dev server starts, page loads localhost
- [ ] Port badge (:3001) appears on task card in rail while server runs
- [ ] Close task → dev server stops, port badge disappears
- [ ] Open browser tab in non-web project → blank browser, no server, no crash
- [ ] Multiple tasks → each gets own port (3000, 3001, etc.)

**Pop-out window**
- [ ] Click pop-out button in browser chrome → NSPanel opens on same/secondary monitor
- [ ] Pop-out window shows same page (shared WKWebView state)
- [ ] Navigate in pop-out → URL updates in both pop-out and tab if docked back
- [ ] Close pop-out window → browser tab still works in main window
- [ ] Pop-out window floats above other windows (utility panel behavior)

**Keyboard shortcuts**
- [ ] Cmd+Shift+B creates browser tab if none exists
- [ ] Cmd+Shift+B focuses existing browser tab if one exists
- [ ] Cmd+Shift+B no-op in Plan mode

**Edge cases**
- [ ] Browser tab with no URL → shows blank state, no crash
- [ ] Navigate to invalid URL → error page shown in-app, no crash
- [ ] Rapid tab switching between browser and terminal → no flicker or layout break
- [ ] Session restore with browser tabs → URLs reload on reopen
- [ ] Browser tab during Build mode → does not interfere with builder drawer
- [ ] App termination with running dev servers → all servers killed (no orphans)
- [ ] Port conflict (port in use) → allocator skips to next available port
- [ ] Close all terminals → browser panels and dev server also cleaned up

---

## Design Tokens (from spec)

- **Background**: `#0c0c0e`
- **Surface**: `#111115`
- **Accent**: `#7c6cf0`
- **Design language**: Linear/Vercel-influenced dark theme. Tight density, no decorative chrome.

*Font migration (Geist Sans/Mono, Gelasio) is a separate concern — keep system fonts for now.*
