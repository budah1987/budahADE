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

## Phase 1 — Close the Spec > Builder Loop

### 1.1 Fix SpecParser.findSpecFiles()
Scan `.budahade/spec.md` in addition to root-level patterns. Without this, the entire pipeline is broken — approved specs are invisible to the UI.

### 1.2 Approve & Build transition (inline, no extra confirmation)
The Approve button IS the confirmation. Flow:
1. User clicks "Approve & send to Build" in Spec Author tab
2. Inline confirmation line appears in chat: "→ spec.md written — 7 items"
3. ~2 second overlay appears with three status lines:
   - "Writing spec.md…" → "Launching builder agent…" → "Switching to Build mode…"
4. Mode auto-switches to Build, builder agent launches with spec path
5. Overlay auto-dismisses

No modal, no extra confirmation step.

### 1.3 Block graph component (new, in SpecPanelView)
Standalone `SpecBlockGraphView` component, placed between panel header and checklist:
- Horizontal row of 8×14px fixed-width blocks, 2px gaps
- One block per spec item
- Colors: dim (pending), pulsing accent (active via existing `PulsingModifier`), green (done), red (blocked)
- Hover tooltip: phase ID + item text (e.g. "1.1 — Stream event parsing")
- Click: no-op (read-only, state driven by build-status.json + spec.md polling)
- Percentage label to the right (e.g. "42%")
- **Collapse behavior**: panel collapse toggle hides checklist + status line but keeps block strip always visible as the at-a-glance view

### 1.4 Elapsed time in status line
Track `startedAt` timestamp in BuildStatusState. Display "Working on {task}... 2m 34s" in the spec strip status row.

---

## Phase 2 — In-App Browser

### Current State
`BrowserTileView.swift` is a full WKWebView with URL bar, back/forward/reload — but only available as a canvas tile (unused in current chat-based Plan mode).

### 2.1 Browser as a Build mode tab type
Allow creating browser tabs alongside terminal tabs. Useful for localhost preview, docs, PR reviews.

### 2.2 URL interception from chat/terminal
When Claude returns URLs or terminal prints `localhost:XXXX`, offer to open in-app.

### 2.3 Page content sharing
"Show this page to Claude" — extract text or screenshot, inject into conversation.

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

### 5.4 Test coverage
DiffModalView, CommitHistoryView, and the spec-builder integration have no tests.

---

## Design Tokens (from spec)

- **Background**: `#0c0c0e`
- **Surface**: `#111115`
- **Accent**: `#7c6cf0`
- **Design language**: Linear/Vercel-influenced dark theme. Tight density, no decorative chrome.

*Font migration (Geist Sans/Mono, Gelasio) is a separate concern — keep system fonts for now.*
