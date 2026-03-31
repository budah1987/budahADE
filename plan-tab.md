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
`SpecParser.findSpecFiles()` only scans worktree root for `*-spec.md`, `*-plan.md`, `*.spec.md`. But `SpecVersionManager.approve()` writes to `.budahade/spec.md`. **The spec panel never sees approved specs.** Fix: also scan `.budahade/spec.md`.

### Missing Connections (3 items)
1. **No mode transition on approve** — `handleApprove()` saves the spec and sends a chat message, but doesn't offer to switch to Build mode
2. **No "Launch Builder" prompt** — switching to Build mode auto-launches Claude with builder prompt if spec exists, but there's no guided UX
3. **No block graph visualization** — the spec describes per-item blocks with pulsing/color states. Current SpecStripView has a flat segmented bar but no interactive block graph with tooltips

### What the Spec Calls For (vs what exists)

| Spec Requirement | Status | Notes |
|-----------------|--------|-------|
| Approve writes to `.budahade/spec.md` | Done | `SpecVersionManager.approve()` |
| Builder prompt reads spec + reports JSON | Done | `AgentPrompts.builderPrompt()` |
| BuildStatusWatcher polls JSON | Done | Adaptive 2s/0.5s polling |
| SpecParser → SpecState | Done | Section-aware with progress |
| SpecPanelView consumes both signals | Done | Checklist + build status row |
| **Approve triggers mode switch** | **Missing** | Need transition UX |
| **Block graph (per-item blocks)** | **Missing** | Only segmented bar exists |
| **Pulsing active / red blocked states** | **Partial** | Exists in SpecPanelView task rows, not in strip |
| **Hover tooltips on blocks** | **Missing** | — |
| **Elapsed time in status line** | **Missing** | BuildStatusState has no timestamp tracking |

---

## Phase 1 — Close the Spec > Builder Loop

### 1.1 Fix SpecParser.findSpecFiles() 
Scan `.budahade/spec.md` in addition to root-level patterns. Without this, the entire pipeline is broken — approved specs are invisible to the UI.

### 1.2 Add "Approve & Build" transition
After `handleApprove()` saves the spec, show a confirmation sheet: "Spec saved as v{N}. Switch to Build mode?" with two options:
- **Start Build** → calls `task.enterBuildMode()`, which auto-launches Claude with builder prompt
- **Stay in Plan** → dismiss, user can continue editing

### 1.3 Block graph component for SpecStripView
Replace the flat segmented bar with the designed block graph:
- One small rectangle per spec item
- Colors: dim (pending), pulsing accent (active), green (done), red (blocked)
- Hover tooltip showing item text
- Collapse/expand toggle

### 1.4 Wire elapsed time into status line
Track `startedAt` timestamp in BuildStatusState. Display "Working on {task}... 2m 34s" in the spec strip.

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
Currently Approve just sends a message. Should transition `PlanConversationState` from `.chatting` → `.specGenerated` → `.specEdited` and update UI affordances.

### 3.2 Guided workflow routing
After a role completes substantive output, suggest next step: "Hand off to {next role}?" Based on the natural flow: Researcher → Ideator → Designer → Developer → Spec Author.

### 3.3 Canvas integration (future)
The 56-file canvas system is powerful but disconnected. Could serve as a visual spec builder or architecture diagram surface.

---

## Phase 4 — Hardening

### 4.1 Replace git polling with FSEvents
GitRepository polls every 1.5s (5 git subprocess calls each). Replace with file system events.

### 4.2 Claude CLI path detection
`AICommitService` hardcodes `/usr/local/bin/claude`. Use `which claude` or make configurable.

### 4.3 Conversation search
Search across plan tab histories.

### 4.4 Test coverage
DiffModalView, CommitHistoryView, and the spec-builder integration have no tests.

---

## Design Tokens (from spec)

- **Fonts**: Geist Sans (UI), Geist Mono (terminal/code), Gelasio (display/serif)
- **Background**: `#0c0c0e`
- **Surface**: `#111115`  
- **Accent**: `#7c6cf0`
- **Design language**: Linear/Vercel-influenced dark theme. Tight density, no decorative chrome.

*Note: Current Theme.swift uses system fonts. Font migration is a separate task.*
