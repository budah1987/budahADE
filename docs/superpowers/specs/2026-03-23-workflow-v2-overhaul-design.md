# BudahADE Workflow V2 Overhaul — Design Spec

## Overview

Overhaul BudahADE's Plan/Build workflow to support spec-driven development with agent orchestration, contextual connections, and live build tracking. Six phases with sequential dependencies: each phase builds on the previous (Phase 2 requires Phase 1, Phase 3 requires Phase 2, etc.), but each phase is independently shippable — you get value at every step.

**Current state:** 11,692 LOC across 62 files. Infinite canvas with 7 tile types, Ghostty terminal integration, git worktree management, spec tracking infrastructure. No CLI subprocess agents, no MCP server, no inter-tile connections.

**Target state:** A spatial thinking environment where agent conversations flow into specs, specs flow into builds, and progress tracks automatically — all within a performant canvas that serves as both a planning tool and a presentable artifact.

---

## Architecture Principles

- **Spec is a file on disk** — `spec.md` in the worktree, `SPEC.md` on main. Source of truth is always the file, never UI state alone.
- **Canvas is ephemeral per task** — fresh canvas per task. SPEC.md carries project memory forward, not the canvas.
- **Two agent modes** — chat tiles (CLI subprocess, lightweight, programmatic control) and terminal tiles (full CLI, skills, interactive). Both participate in the canvas connection graph.
- **MCP is the orchestration layer** — bridges the gap between terminal processes and programmatic control. Canvas-wide, not build-only.
- **Performance is non-negotiable** — 15 tiles at <16ms frame time. Viewport culling, lazy-loaded WKWebViews, lightweight text rendering.

---

## Phase 1: Canvas Performance + Lighter Tiles ✅ SHIPPED

### 1.1 Decompose CanvasElementView ✅

`CanvasElementView.swift` decomposed from 1,041 LOC → 167 LOC. Zero regressions.

| File | Responsibility | LOC |
|------|---------------|-----|
| `CanvasElementView.swift` | Shell: dispatches to content + chrome, hover X on text elements | 180 |
| `TileDragHandler.swift` | Drag gesture, frame intersection detection, smart guides | 128 |
| `TileResizeHandler.swift` | ResizeHandles, ResizeCorner/Edge, CornerHandle, EdgeHandle, FrameChildResizeHandle | 381 |
| `TileSelectionManager.swift` | Selection border, hover state, spec section badge | 55 |
| `FrameContainerView.swift` | Frame header, child layout, insertion indicator, empty state | 182 |
| `TextContentView.swift` | TextContentView (edit/display toggle) + TextStyleToolbar | ~170 |

### 1.2 Simplify Text Tile Types ✅

**Removed:** `RichTextEditor.swift` (339 LOC), `DocumentTileView.swift` (100 LOC), `SpecDocumentTileView.swift` (242 LOC), `TextBoxView.swift`. Removed `TileType.document`, `TileType.specDocument`, `TileType.textBox`. Removed double-click-to-create-terminal on canvas.

**Three text tiers (as shipped):**

| Tile | Element Type | Purpose | Behavior |
|------|-------------|---------|----------|
| **Text Box** | `ElementKind.text(TextData)` | Headlines, labels, callouts | Single-line, auto-width to text, Enter exits edit, TextStyleToolbar (B/I/size/weight/family), hover X to delete, auto-starts in edit mode |
| **Sticky Note** | `TileType.stickyNote` | Quick thoughts, longer notes | Multi-line TextEditor, click-to-edit/click-away-commit, TileChrome shell |
| **Markdown** | `TileType.markdown(path:)` | Specs, documents, structured content | Section-based editing, source attribution, interactive checkboxes, progress bar |

**Markdown Tile** (`MarkdownTileView.swift`, 279 LOC) — unified replacement for DocumentTileView + SpecDocumentTileView:
- Section-based inline editing: click `## heading` section → TextEditor, click away → renders styled text
- Source attribution: `<!-- source: tile-uuid -->` rendered as colored dot + "from {id}" label
- Interactive checkboxes: toggle writes to file via `SpecParser.toggleCheckbox()`, only counts within-section checkboxes
- Progress bar when checkboxes exist. Footer: filename + section count.
- Polling pauses during editing. Commit finds heading by text match (not stale lineRange).
- Duplicate heading IDs deduplicated with `-2`, `-3` suffix.
- Version dropdown, Finalize → Build button, and Duplicate action are **deferred to Phase 4** (spec tile features).

**Parser:** `SpecParser.swift` extended with `MarkdownSection` struct and `parseMarkdownSections(from:)`. Coexists alongside existing `SpecSection`/`SpecParseResult`. Also added `toggleCheckbox(in:at:)` and made `slugify` internal.

### 1.3 Viewport Culling ✅

- Debounced culling (100ms) using `cachedVisibleIds: Set<UUID>` — avoids CGRect math on every frame
- Triggers on `canvas.mutationCount` (incremented in `didMutate()`) — catches position, size, add, remove, reorder changes
- Browser tiles: `isVisible` parameter added with placeholder fallback. Actual culling at `ForEach(visibleElements)` level
- `CanvasInputMonitor`: spacebar/escape pass through to `NSTextView` focus, not just terminal focus

### 1.4 BrowserTileView Enhancements ✅

- `WebViewStore.loadHTML(_ html: String, baseURL: URL?)` method added
- `MermaidRenderer.htmlPage(diagramCode:theme:)` helper generates HTML template
- `mermaid.min.js` not yet bundled — **deferred to Phase 6**. Template renders raw markup until JS available.

### 1.5 Branch Picker in NewTaskSheet ✅

- `GitRepository.listBranches(at:)` static async method added
- Base branch `TextField` replaced with `Menu`-based dropdown picker
- Loads branches on appear, defaults to `main`

### 1.6 XCTest Target ✅ (not in original spec)

20 tests across 5 test classes: SpecParserTests (6), MarkdownSectionParserTests (6), TileTypeTests (3), FrameDataTests (3), TextDataTests (2).

### 1.7 Warnings Cleanup ✅ (not in original spec)

Zero Xcode warnings. Fixed Sendable captures in GitRepository, var→let for non-mutated variables.

### Performance Targets

- Canvas with 15 tiles: debounced culling implemented, needs manual frame-time verification
- Offscreen tiles: excluded from ForEach via viewport culling
- Gesture responsiveness: zero decomposition regressions confirmed by code audit

---

## Phase 2: CLI Subprocess Agent System + Chat UI Tile ✅ SHIPPED

**Shipped:** CLISubprocessManager (claude -p --output-format stream-json --verbose), AgentSession, ChatMessage with stream parsing, ChatTileView with full chat UI, 4 agent roles (Claude/Researcher/Ideator/Developer) with per-role tool restrictions and max-turns, Send To (stages content as primary subject), model switching (session fork), image paste (Cmd+V clipboard + file picker), token tracking, animated thinking dots, tool call accordion, Opt+P model selector in terminal tiles (Ghostty key translation fix), cursor state fixes (push/pop → set). 90 tests, 0 failures.

### Required Reading (read before implementing)
- `Plan/AgentPrompts.swift` (212 LOC) — existing agent system prompts. Extend with role system. Contains `builderLaunchCommand()` pattern for constructing CLI commands.
- `Plan/TileType.swift` (78 LOC) — tile type enum. Add `.chatAgent` case here.
- `Plan/AddTileMenu.swift` (113 LOC) — tile creation menu. Add chat agent option.
- `Plan/CanvasNode.swift` (235 LOC) — canvas element model. Understand how tile content/type is stored.
- `Plan/PlanCanvasState.swift` (636 LOC) — canvas state. New chat tiles are added here via `addElement()`.
- `Task/TaskState.swift` (314 LOC) — task lifecycle. Understand `startTerminal()` pattern — subprocess manager follows similar lifecycle but returns structured output instead of PTY.
- `Terminal/TerminalSurface.swift` (198 LOC) — `send(command)` pattern. CLISubprocessManager replaces this with `Process` + stream-json parsing.
- `Plan/TileViews/` — all existing tile views for structural reference. ChatTileView follows same chrome pattern as other tiles.

### 2.1 CLISubprocessManager

New core infrastructure for managing `claude -p` subprocess agents.

```
CLISubprocessManager
  spawn(sessionId, model, systemPrompt, workingDir, allowedTools) → AgentSession
  send(sessionId, prompt) → AsyncStream<StreamEvent>
  resume(sessionId, prompt) → AsyncStream<StreamEvent>
  cancel(sessionId)
  sessions: [UUID: AgentSession]

AgentSession
  id: UUID
  sessionId: String              — claude's --session-id
  model: AgentModel              — .haiku / .sonnet / .opus
  status: .idle / .streaming / .done / .error
  messages: [ChatMessage]        — parsed from stream-json
  tokenUsage: TokenUsage         — tracked from API responses
  process: Process?              — underlying OS process
```

Under the hood: spawns `claude -p "{prompt}" --output-format stream-json --session-id {id} --model {model} --append-system-prompt "{role}"`. Parses newline-delimited JSON events into `ChatMessage` structs.

### 2.2 ChatMessage Model

```swift
struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role                // .user / .assistant / .system
    let content: String           // rendered text
    let toolCalls: [ToolCall]?    // collapsed in UI
    let timestamp: Date
    let tokenCount: Int?
}
```

### 2.3 ChatTileView

New canvas tile type for agent conversations.

**Header:**
- Agent name, status dot (green active, gray idle)
- Model picker dropdown — switchable per-turn (Haiku/Sonnet/Opus)
- Token count
- `...` menu: New Session, Summarize & Compact, Duplicate Tile

**Body:**
- `ScrollView` + `LazyVStack` of messages
- User messages: right-aligned, accent colored
- Agent messages: left-aligned, markdown rendered
- Tool calls: collapsed disclosure ("> Read 3 files")
- Context injections from connections: dashed-border card

**"Send to" button** on every assistant message:
- Dropdown: "Spec" (adds to spec tile as new section) | existing agents | "New Agent..."
- Send to Spec: content becomes a new section, user dropped into edit mode to refine
- Send to Agent: content becomes context for destination's next turn. Creates agent tile if it doesn't exist.

**Input area:**
- Text field + send button
- Image paste/drop support: saves to `.budahade/images/{uuid}.png`, references path in prompt
- Image thumbnail preview before sending

**Slash command equivalents (via `...` menu):**
| CLI | BudahADE |
|-----|----------|
| `/clear` | New Session |
| `/compact` | Summarize & Compact |
| `/model` | Model picker in header |
| `/cost` | Token counter in header |

Note: `/commands` and skills are NOT available in chat tiles. For skill access, use a terminal tile on the canvas instead.

### 2.4 Agent Role System

```swift
struct AgentRole {
    let name: String
    let systemPrompt: String
    let defaultModel: AgentModel
    let maxTurns: Int
    let allowedTools: [String]?   // nil = all tools allowed
    let color: Color
}
```

**Built-in roles (4 specialists + raw CLI):**

**Researcher** — Claude Desktop research mode equivalent. Deep dives, structured reports, multiple sources.
| Property | Value |
|----------|-------|
| Model | Sonnet |
| Max Turns | 10 |
| Allowed Tools | `WebSearch, WebFetch, Read, Glob, Grep` |

System prompt: "You are a Research Expert. Produce structured research reports with clear analysis, sources, and conclusions. Investigate thoroughly but present findings cleanly — use headings, bullet points, and citations. When fed files or data, synthesize into actionable insights. When asked to look at the codebase, use Read/Glob/Grep as needed."

Use cases: internet research, synthesizing interviews/transcriptions/notes, analyzing documents, occasionally referencing codebase.

---

**Ideator** — Business partner, co-founder, PM. Gets ideas out of your head.
| Property | Value |
|----------|-------|
| Model | Opus |
| Max Turns | 5 |
| Allowed Tools | `Read, Glob, Grep` |

System prompt: "You are an Ideation Partner and strategic thinker. Help the user get ideas out of their head. Ask incisive questions. Challenge assumptions. Propose 2-3 options with trade-offs. Read project files for context when relevant — understand the codebase and project state to give informed ideas. Focus on ideas and direction, not implementation details."

Use cases: brainstorming, product direction, project management, strategic thinking, getting ambiguous thoughts into structured form.

---

**Developer** — Senior architect & developer. Plans AND writes code.
| Property | Value |
|----------|-------|
| Model | Sonnet (switch to Opus for ambiguous architecture) |
| Max Turns | 10 |
| Allowed Tools | `Read, Glob, Grep, Edit, Write, Bash` |

System prompt: "You are a Senior Architect & Developer. Assess feasibility, suggest architecture, identify risks and dependencies. When asked, write code that is simple, efficient, and follows existing codebase patterns — code that would impress a human engineer. Reference file paths and line numbers. Think about performance, maintainability, and incremental delivery."

Use cases: technical feasibility, architecture consulting, code snippets, proof of concepts, data model design, implementation planning.

---

**Claude (Ad-hoc)** — Raw Claude CLI experience. No personality, no restrictions.
| Property | Value |
|----------|-------|
| Model | Sonnet (user switches via picker) |
| Max Turns | nil (unlimited) |
| Allowed Tools | nil (all) |

System prompt: Minimal — task name and branch context only. No role personality.

Use cases: anything that doesn't fit a specialist. General purpose.

---

**Reviewer** — removed as a built-in role. Reviewing is a task given to any agent ("review this code", "critique this spec"), not a standalone persona. If needed, create as a custom specialist.

**CLI flags per role:** `CLISubprocessManager` constructs the command:
```bash
claude -p "{prompt}" \
  --output-format stream-json \
  --verbose \
  --model {role.defaultModel} \
  --max-turns {role.maxTurns} \
  --allowedTools "{role.allowedTools.joined}" \
  --system-prompt-file {promptFile} \
  --dangerously-skip-permissions
```

**Custom roles:** user-created via Phase 6 settings UI. User sets name, model, max turns, allowed tools, system prompt. Defaults to Ad-hoc parameters if not specified.

- Extend existing `AgentPrompts.swift` (212 LOC)
- When creating a chat tile: pick role from menu or start ad-hoc

### 2.5 Token Tracking

- `stream-json` output includes usage data — accumulate per-session and global totals
- Display in tile header: "2.4k tokens"
- Display in workspace status bar: "Today: 45k tokens · 3 sessions"

### Performance Considerations

- `Process` spawned on background queue, stream parsing on background, UI updates on main
- Messages stored as plain structs — single `@Published messages` array, not per-message observables
- `LazyVStack` ensures only visible messages render
- Idle sessions: process terminated, messages retained in memory for resume

### Phase 2 Verification (check before starting Phase 2.5)

1. **Subprocess lifecycle** — spawn a chat agent, send 3 messages, verify multi-turn works via `--session-id` + `--resume`. Cancel mid-stream, verify process kills cleanly.
2. **Stream-json parsing** — verify all message types parse correctly: text content, tool calls, errors. No dropped events, no malformed messages.
3. **ChatTileView rendering** — user messages right-aligned, agent messages left-aligned with markdown. Tool calls collapsed. Scrolls to bottom on new message. LazyVStack performs with 50+ messages.
4. **Model switching** — change model mid-conversation via header picker. Next message uses new model. Verify `--model` flag applies correctly.
5. **Send To** — test "Send to Spec" on an agent message: new section appears in markdown tile with content, user can edit. Test "Send to Agent": creates new agent tile if needed, content appears as context.
6. **Image paste** — paste image into input area, verify thumbnail preview, verify image path referenced in prompt, verify agent responds to the image.
7. **Token tracking** — verify token count in header updates after each turn. Values should be plausible (not zero, not absurdly high).
8. **Agent roles** — create Ideator (Opus), Developer (Sonnet). Verify system prompts apply and model defaults are correct.

---

## Phase 2.5: Canvas State Persistence ✅ SHIPPED

**Shipped:** CanvasPersistence (save/load to `.budahade/canvas.json`), debounced 1s save on mutation, immediate save on task switch and app quit, Codable conformance for all canvas types (CanvasElement, ElementKind, FrameData, TextData, TileType, AgentMode), chat message persistence, terminal tiles restore as empty shells. Graceful degradation on missing/corrupted files.

### Problem

Canvas state is in-memory only. Quitting BudahADE loses all tiles, positions, and content. This makes the app unusable as a daily driver and blocks Phase 3 (connections must persist).

### Required Reading (read before implementing)
- `Plan/PlanCanvasState.swift` — the state to serialize. Contains `elements: [CanvasElement]`, `zoom`, `panOffset`, and will contain `connections` in Phase 3.
- `Plan/CanvasNode.swift` — `CanvasElement` data model. Must be `Codable`.
- `Task/TaskState.swift` — task lifecycle. Canvas state saves/loads here on task switch and app quit.
- `Task/BuildStatusWatcher.swift` — reference for file-based state persistence pattern (polls `.budahade/build-status.json`).

### Design

**Storage:** Serialize `PlanCanvasState` to `.budahade/canvas.json` in the task's worktree directory.

**Save triggers:**
- On every meaningful mutation (tile add/remove/move/resize/edit) — debounced 1s
- On task switch (immediate)
- On app quit (immediate via `NSApplication.willTerminateNotification`)

**Load:** When a task is opened and `enterPlanMode()` is called, check for `.budahade/canvas.json` in the worktree. If exists, deserialize and restore. If not, start with empty canvas.

**What to serialize:**
- All `CanvasElement` structs (position, size, type, content, title)
- Viewport state (zoom level, pan offset)
- Frame data (children, axis, gap, padding)
- Text content for sticky notes, text boxes, markdown tiles
- Agent chat tile state: session ID, messages, role, model (so conversations can resume)
- NOT: terminal tile state (Ghostty sessions can't be serialized — terminal tiles restore as empty shells)

**Codable conformance:** Add `Codable` to `CanvasElement`, `FrameData`, `TextData`, and all `TileType` cases. Use `JSONEncoder`/`JSONDecoder` with `.prettyPrinted` for debuggability.

**File size:** canvas.json will be small (typically <100KB even with chat messages) — no compression needed.

### Phase 2.5 Verification (check before starting Phase 3)

1. **Save on mutation** — add tiles, move them, edit text. Verify `.budahade/canvas.json` exists in worktree and contains current state.
2. **Restore on relaunch** — quit app, reopen, open same task. Canvas should restore: tile positions, sizes, text content, zoom level, pan offset.
3. **Task switching** — switch between tasks. Each task's canvas restores independently.
4. **Chat tile persistence** — create a chat agent, have a conversation. Quit app, reopen. Chat messages should be there. Session should resume on next send.
5. **Terminal tiles** — terminal tiles restore as empty shells with scrollback snapshot (see Phase 2.75). Claude relaunches with `--resume`.
6. **Empty canvas** — new task with no canvas.json starts with blank canvas. No errors.
7. **Corrupted file** — delete or corrupt canvas.json. App should start with empty canvas, not crash.

---

## Phase 2.75: Session Persistence (Build Mode + Terminal Tiles) ✅ SHIPPED

**Shipped:** tmux-backed terminal sessions (conversations survive app quit — Claude keeps running in tmux daemon). App state persistence (`~/.budahade/app-state.json`) restores projects/tasks on relaunch. Tab metadata + tmux session names saved to `.budahade/sessions/tabs.json`. Canvas chat tile `claudeSessionId` persisted for `--resume`. Tab names protected from shell title overwrites. Surface creation retries on Ghostty init timing. Keyboard: Opt+P model selector fixed (translation_mods + unshifted_codepoint), cursor states fixed (push/pop → set). **In progress:** Shift+Enter linebreaks through tmux (send-keys approach), Cmd+V paste surface timing.

### Problem

Quitting BudahADE loses all terminal sessions — Build mode tabs and canvas terminal tiles. PTY processes can't survive app quit (this is a terminal limitation, not a BudahADE issue). But the user expects to pick up where they left off. BudahADE should feel like coming back to your desk, not starting fresh.

### Required Reading (read before implementing)
- `Task/TaskState.swift` — tab management, terminal lifecycle. Persist tab list + session IDs here.
- `Terminal/TerminalSurface.swift` — Ghostty surface wrapper. Need to extract scrollback text before quit.
- `Terminal/TerminalPanel.swift` — terminal container. Add scrollback snapshot capture.
- `Terminal/TerminalSurfaceView.swift` — NSView host. Scrollback snapshot view inserts above the new terminal.
- `Agent/CLISubprocessManager.swift` — `claudeSessionId` persistence for `--resume` on chat tiles.
- `GhosttyAppManager.swift` — check if Ghostty exposes API to read terminal text content from surface.

### Design

**What to persist per terminal tab (saved to `.budahade/sessions/`):**
- Tab name and agent role
- Working directory
- Claude `--session-id` (for `--resume`)
- Scrollback text snapshot (raw text from terminal surface)
- Tab order and which tab was active

**Scrollback snapshot capture:**
On app quit (`NSApplication.willTerminateNotification`) and task switch:
1. For each open terminal tab, read the current text content from Ghostty's surface
2. Save as `.budahade/sessions/{tabId}-scrollback.txt`
3. Save tab metadata to `.budahade/sessions/tabs.json`

**On relaunch:**
1. Read `tabs.json` — recreate tab bar with the same tabs in the same order
2. For each tab, display scrollback snapshot as a **read-only static text view** (monospace, terminal-styled, slightly faded) above the terminal area
3. Launch fresh Ghostty terminal below the snapshot
4. Relaunch Claude with `--resume {sessionId}` so Claude has full conversation context
5. Show a "Session resumed" divider between snapshot and live terminal

**Visual layout on restore:**
```
┌─ Builder ──────────────────────────────────┐
│                                            │
│  [Previous session - read only, faded]     │
│  > Implement the auth spec...              │
│  ✓ mark_spec_item("read-token")            │
│  Working on Keychain manager...            │
│                                            │
│  ──── Session resumed ────                 │
│                                            │
│  [Live terminal - Ghostty, interactive]    │
│  > █                                       │
│                                            │
└────────────────────────────────────────────┘
```

**Chat tile `claudeSessionId` persistence:**
- Persist `claudeSessionId` in `canvas.json` per chat agent tile
- On restore, `--resume {sessionId}` continues the server-side conversation
- Chat messages display from `canvas.json`, Claude has full context via resume

**Ghostty scrollback extraction:**
- Check if `ghostty_surface_*` API exposes text content. If so, read it directly.
- If not, alternative: capture the terminal's `NSView` as a rendered image (screenshot) instead of raw text. Less ideal (not searchable, larger file) but guaranteed to work.
- Fallback: if neither works, skip scrollback snapshot — just relaunch with `--resume` and no visual history. Still valuable.

### Phase 2.75 Verification

1. **Build mode tabs persist** — open 3 builder tabs. Quit app, reopen. All 3 tabs recreate with correct names and order.
2. **Scrollback snapshot** — previous terminal output visible as read-only text above the fresh terminal. Scroll up to see it.
3. **Session resumed divider** — clear visual separator between old snapshot and new live terminal.
4. **Claude --resume works** — send a follow-up message after relaunch. Claude remembers the prior conversation context.
5. **Chat tile claudeSessionId** — quit with a chat agent on canvas, reopen. Send a message — Claude resumes, doesn't start fresh.
6. **Canvas terminal tiles** — same scrollback + resume behavior as Build mode tabs.
7. **Tab order** — tabs restore in the same order. Active tab is re-selected.
8. **No scrollback available** — if Ghostty doesn't expose text content, gracefully skip snapshot. Terminal relaunches with just `--resume`, no crash.

---

## Phase 3: Contextual Connections

### Required Reading (read before implementing)
- `Plan/PlanCanvasState.swift` — add `connections: [TileConnection]` array here. Understand `elements` array pattern for persistence/mutation.
- `Plan/PlanCanvasView.swift` — the main canvas render. `ConnectionsLayer` inserts between grid background and tile ForEach. Study the existing `Canvas` draw API usage for the dot grid — same API draws arrows.
- `Plan/SmartGuides.swift` (172 LOC) — alignment guide rendering pattern. Connection arrows follow a similar "overlay drawn during interaction" pattern.
- `Plan/CanvasElementView.swift` (post-Phase 1 decomposition) — connection ports attach to tile edges. Understand tile geometry/bounds.
- `Agent/CLISubprocessManager.swift` (Phase 2) — summary generation spawns Haiku subprocesses through this manager.
- `Agent/ChatTileView.swift` (Phase 2) — context injection prepends to prompts sent via this tile's input.
- `Plan/ContextManifest.swift` (75 LOC) — existing canvas context serialization. `TileOutputProvider` protocol extends this idea per-tile.

### 3.1 Connection Data Model

```swift
struct TileConnection: Identifiable {
    let id: UUID
    let sourceId: UUID
    let destinationId: UUID
    var cachedSummary: String?
    var summaryTimestamp: Date?
    var sourceVersion: Int         // invalidates cache when source changes
}
```

Stored in `PlanCanvasState.connections: [TileConnection]`. Persisted with canvas state.

### 3.2 Creating Connections

- Connection ports appear on tile edges on hover (right edge = output, left edge = input)
- Drag from port → bezier curve follows cursor → drop on destination tile
- Right-click connection line → delete
- Visual feedback: destination tile highlights on hover during drag

### 3.3 Arrow Rendering

- Dedicated `ConnectionsLayer` between grid and tiles in view hierarchy
- SwiftUI `Canvas` draw API — single draw pass for all connections, zero view overhead
- Bezier curves follow tile positions (recomputed on tile position change)
- Gradient from source color to destination color
- Dashed stroke when summary is stale

### 3.4 Content-Type Aware Output

```swift
protocol TileOutputProvider {
    func currentOutput() -> TileOutput
}

enum TileOutput {
    case text(String)                    // sticky, text box, markdown
    case conversation([ChatMessage])     // chat agent
    case image(URL)                      // image tile
    case url(URL)                        // browser tile
    case terminalOutput(String)          // terminal (last N lines)
}
```

Each tile type conforms to `TileOutputProvider`.

### 3.5 Summary Generation + Caching

When a destination agent needs context from connected tiles:

1. Check each incoming connection: is `cachedSummary` fresh? (compare `sourceVersion`)
2. If stale: spawn `claude -p --model haiku "Summarize concisely for a developer: {output}"` — ~500 tokens per summary
3. Cache result in `TileConnection.cachedSummary`
4. If fresh: use cache, zero tokens
5. Assemble all summaries into context block

**Concurrency:** summary generation runs max 3 parallel subprocesses. Additional requests queue. Prevents CPU/token spikes when many connections go stale simultaneously.

### 3.6 Context Injection

**Chat tiles (automatic):** When user sends a message, BudahADE prepends connected context:
```
Context from connected tiles:
---
[Ideator] OAuth2 via existing CLI credentials...
---
[Note] Must handle token expiry gracefully...
---

{user's actual message}
```

**Terminal tiles (explicit):** Agent calls `get_connected_context()` MCP tool to pull the same summaries on demand.

### 3.7 "Send to" Integration

"Send to" on a message creates a one-shot content transfer. Connections define ongoing context flow. Both coexist:
- **Connections** = "every turn, pull upstream context"
- **Send to** = "this specific message goes there now"

### Performance

- Arrow rendering: single Canvas draw call
- Summary generation: background process, non-blocking
- Cache hit rate expected high — sources don't change frequently
- Realistic connection count: 5-15 per canvas

### Revision Note

This phase will likely need significant UX iteration once in use. The data model and rendering are intentionally decoupled from summary generation and context injection to allow independent revision.

### Phase 3 Verification (check before starting Phase 4)

1. **Connection creation** — drag from output port to input port creates a connection. Arrow renders as bezier curve. Delete via right-click.
2. **Arrow rendering performance** — add 10+ connections. Pan/zoom should remain smooth. Arrows must follow tile positions when tiles are dragged.
3. **Content-type outputs** — verify each tile type returns correct output: sticky → text, markdown → text, chat agent → conversation, image → URL, browser → URL, terminal → recent output.
4. **Summary generation** — connect two tiles. Verify Haiku subprocess spawns, generates summary, caches it. Reconnect — verify cache is served (no new subprocess). Modify source — verify cache invalidates and regenerates.
5. **Context injection into chat tiles** — connect Ideator → Developer. Send a message in Developer. Verify Ideator's summary appears as a dashed-border context card in Developer's chat. Verify the summary is prepended to the CLI subprocess prompt.
6. **Terminal tile MCP interop** — connect a tile to a terminal tile. In the terminal, call `get_connected_context()`. Verify it returns the same summaries that chat tiles get automatically.
7. **Concurrency** — stale 5 connections simultaneously. Verify max 3 parallel Haiku subprocesses, others queue.
8. **Canvas state** — connections persist when switching tasks and returning. Connections survive plan/build mode toggle.

---

## Phase 4: Spec Tile + Versioning

### Required Reading (read before implementing)
- `Plan/TileViews/MarkdownTileView.swift` (Phase 1) — the base markdown tile this phase extends. Already has section-based editing, checkboxes, source attribution rendering.
- `Spec/SpecParser.swift` (179 LOC) — existing checkbox parser. Phase 1 extends it with heading-based section splitting. Phase 4 adds source attribution parsing (`<!-- source: tile-uuid -->`).
- `Spec/SpecState.swift` (73 LOC) — spec state holder. Add versioning state (current version, version list) here.
- `Spec/SpecWatcher.swift` (99 LOC) — file polling. Understand adaptive polling pattern (2s normal, 0.5s during active changes).
- `Task/TaskState.swift` (314 LOC) — `enterPlanMode()` / `enterBuildMode()` methods. Finalize → Build triggers `enterBuildMode()` after exporting spec.
- `GitPanel/GitRepository.swift` (385 LOC) — git CLI wrapper. Use for `git log --oneline -- spec.md` (version listing) and `git show {hash}:spec.md` (viewing past versions).
- `Task/GitWorktreeManager.swift` (145 LOC) — `runGit()` async pattern. Reuse for spec version commits.
- `Agent/ChatTileView.swift` (Phase 2) — "Send to" dropdown. Send to Spec creates new section in MarkdownTileView.

### 4.1 Spec Tile

The markdown tile (Phase 1) with spec-specific features:

- All markdown tile features (section-based editing, source attribution, checkboxes)
- **Auto-assembly from connections:** when a tile is connected to the spec tile AND the user clicks "Send to → Spec" on a message, content proposes a new section. User approves/edits before it saves. Connections define ongoing flow, Send to is the curation action.
- **Finalize → Build button:** exports to spec.md, switches to Build mode

### 4.2 Named Snapshots

Every meaningful spec edit auto-commits (debounced 2s after last keystroke):
```
git add spec.md
git commit -m "spec: v{n} — {what changed}"
```

**Commit noise:** spec version commits accumulate on the feature branch. On merge, these can be squashed into a single "spec: finalized" commit if desired. BudahADE does not auto-squash — user controls merge strategy.

Version name auto-generated by diffing:
- New sections → "added {section name}"
- Edited sections → "revised {section name}"
- Checkboxes changed → "completed {item}"
- Multiple changes → "updated {n} sections"

Version dropdown reads `git log --oneline -- spec.md`.

### 4.3 Spec Branching

- Right-click spec tile → "Branch variant" → creates `spec-{name}.md` as copy
- New spec tile appears on canvas for the variant
- Both editable independently, each has own version history
- "Merge → spec.md": replaces main spec, creates version snapshot, deletes variant file

### 4.4 Two-Level Spec Architecture

**App-level: `SPEC.md` on main**
- Two zones: reference sections (architecture, decisions, patterns) + actionable sections (roadmap milestones with checkboxes)
- Grows over time as feature specs fold back in after merge
- Every agent has access via MCP `read_spec()` — system prompt mentions it exists

**Feature-level: `spec.md` in each worktree**
- Created on canvas during Plan mode
- Scoped to one task/branch
- After merge: architectural decisions fold into SPEC.md, feature spec discarded

### 4.5 Finalize → Build Handoff

1. Spec status changes to "Finalized" (badge updates)
2. Version snapshot: `git commit -m "spec: finalized for build"`
3. `TaskState.mode` switches to `.build`
4. WorkspaceView renders build layout (no layout shift — just main content area changes)
5. Builder terminal launches with spec context
6. MCP server activates for build tracking

### 4.6 Back to Plan

- `Cmd+Shift+P` or "Back to Plan" link returns to canvas
- Builder terminal keeps running in background
- Spec tile reflects current checkbox state (synced via SpecState)
- Edits on canvas write to spec.md — builder detects via `spec_updated_since()` MCP tool

### Phase 4 Verification (check before starting Phase 5)

1. **Spec tile assembly** — connect an agent tile to a spec tile. Use "Send to → Spec" on an agent message. Verify new section appears with source attribution ("from Ideator" with colored dot). Verify inline edit mode activates.
2. **Section editing** — click a section → edits as plain text. Click away → renders as markdown. Verify changes write to spec.md on disk.
3. **Checkbox interaction** — toggle `- [ ]` to `- [x]` by clicking. Verify file on disk updates. Verify toggling back works.
4. **Version snapshots** — edit the spec, wait 2s. Verify auto-commit with generated name. Check `git log --oneline -- spec.md` shows the version. Verify version dropdown lists it.
5. **Version viewing** — select a past version in dropdown. Verify tile shows read-only content from that commit. Select current → editable again.
6. **Spec branching** — right-click → Branch variant. Verify new file created (`spec-{name}.md`), new tile appears on canvas. Edit variant independently. Merge back → verify main spec.md updated, variant file deleted.
7. **Finalize → Build** — click button. Verify: spec.md committed as "finalized", mode switches to build, terminal launches. Verify Cmd+Shift+P toggles back to Plan.
8. **Back to Plan round-trip** — finalize, switch to build, switch back to plan. Verify canvas state preserved, spec tile reflects any changes.

---

## Phase 5: Build Mode + MCP Server

### Required Reading (read before implementing)
- `Task/BuildStatusWatcher.swift` (94 LOC) — existing build status polling via JSON file. MCP replaces this as primary, but file-watching stays as backup. Understand the adaptive polling pattern.
- `Task/BuildStatusState.swift` (22 LOC) — current build status observable. MCP tools update this same state.
- `Spec/SpecPanelView.swift` (358 LOC) — existing spec viewer in left panel. Upgrade with richer checklist UI (completed items show file names, in-progress pulse).
- `Spec/SpecStripView.swift` (169 LOC) — compact progress bar. Study for the build sidebar progress visualization.
- `Spec/SpecWatcher.swift` (99 LOC) — file-watching backup. Understand polling + SpecState integration.
- `Workspace/WorkspaceState.swift` (163 LOC) — task lifecycle. MCP server starts/stops here alongside task creation/deletion.
- `Workspace/WorkspaceView.swift` (346 LOC) — main layout. Build mode renders here. Understand how Plan/Build mode switch changes the main content area while keeping left panel + git sidebar.
- `Task/TaskState.swift` (314 LOC) — `enterBuildMode()` triggers MCP server start + builder launch. `mode` property drives WorkspaceView layout.
- MCP protocol reference: https://modelcontextprotocol.io/docs — stdio transport, JSON-RPC 2.0 messages.

### 5.1 MCP Server

Canvas-wide, not build-only. Available to ALL agents (chat tiles via injection, terminal tiles via tool calls).

**Tools:**
```
mark_spec_item(id, status)       — marks checkbox, instant UI update via socket
read_spec()                      — returns current spec.md content
spec_updated_since(timestamp)    — boolean + diff if changed
notify_status(message)           — agent reports current activity
get_connected_context()          — summaries from connected tiles
send_to_spec(content, section?)  — adds content as spec section
send_to_agent(agentId, content)  — sends to another agent's context
list_canvas_agents()             — lists agents on canvas with status
```

**Implementation:**
- Standalone Swift executable, separate Xcode target (`budahade-mcp`), bundled in app's Resources
- Speaks MCP protocol over stdio to Claude CLI
- Communicates to BudahADE main process via Unix domain socket (`/tmp/budahade-{taskId}.sock`)
- Auto-configured in worktree's `.claude/settings.local.json` on task creation
- One MCP server per task, shared by all agents in that task

### 5.2 Build Mode Layout

No new panels. Spec progress tracker lives in existing left panel as a tab (Files / Spec). Main content area switches from canvas to terminal.

**Spec tab upgrade:**
- Header: title, completion fraction, version dropdown
- Progress bar: visual fill
- Checklist items:
  - ✓ Completed: green check, strikethrough, file name + line count
  - ● In progress: indigo, pulsing dot, current file name
  - ○ Pending: gray, muted
- Agent status: "Builder working on item 3"
- Back to Plan link

**Main panel:** Full interactive CLI terminal (Builder agent). Always a terminal tile — needs skills, file editing, git operations.

### 5.3 Builder Auto-Launch

When "Finalize → Build" is clicked:
1. Spec exported to `spec.md` in worktree
2. MCP server started for this task
3. `.claude/settings.local.json` written with MCP config
4. Mode switches to `.build`
5. Builder launches: `claude --model opus` (full interactive CLI)
6. Task's CLAUDE.md instructs agent to read spec.md and use budahade MCP tools

### 5.4 File-Watching Backup

- `SpecWatcher` (existing, 99 LOC) continues polling spec.md for `- [x]` changes
- MCP `mark_spec_item` → instant UI update via socket
- Direct file edits → SpecWatcher catches within 1-2s
- Both update same `SpecState` observable — no conflict

### 5.5 Terminal ↔ Canvas Agent Interop

Terminal tiles participate in the connection graph via MCP:

| Capability | Chat Tile | Terminal Tile |
|-----------|-----------|---------------|
| Connection context | Automatic injection | `get_connected_context()` MCP tool |
| Send to Spec/Agent | UI button per message | `send_to_spec()` / `send_to_agent()` MCP tool |
| Skills / /commands | Not available | Full access |
| Model switching | Header dropdown, per-turn | `/model` command |
| Token tracking | Exact, in header | Not visible in UI |

### Performance

- MCP server: lightweight process, minimal memory
- Unix domain socket: near-zero latency
- Socket cleanup on task deletion / app quit

### Phase 5 Verification (check before starting Phase 6)

1. **MCP server starts** — create a task, verify MCP server process spawns. Check `.claude/settings.local.json` is written with correct config. Verify process listens on expected socket path.
2. **mark_spec_item** — in the builder terminal, call `mark_spec_item("item-1", "complete")`. Verify: spec sidebar checkbox updates instantly (not 1-2s polling delay), spec.md file updates on disk.
3. **read_spec** — call from terminal. Verify returns current spec.md content accurately.
4. **notify_status** — call with a status message. Verify sidebar shows "Builder working on: {message}" with live dot.
5. **File-watching fallback** — manually edit spec.md outside of MCP (e.g., edit in the markdown tile on canvas). Verify sidebar catches the change within 1-2s.
6. **Build mode layout** — verify spec sidebar sits in existing left panel as a tab (no new panels). Files tab still works. Git sidebar still works. Only main content area changed to terminal.
7. **Builder auto-launch** — Finalize → Build triggers builder terminal with Opus. Verify CLAUDE.md in worktree instructs agent to use MCP tools.
8. **Socket cleanup** — delete a task. Verify MCP server process terminates and socket file is removed. Quit app → verify no orphaned processes.
9. **get_connected_context from build mode** — if connections exist from Plan mode, verify terminal agent can still pull context via MCP even in Build mode.

---

## Phase 6: Visual Tiles + Polish

### Required Reading (read before implementing)
- `Plan/TileViews/BrowserTileView.swift` (Phase 1 modified) — already has `loadHTMLString` support from Phase 1. Mermaid rendering builds on this. Understand `WebViewStore` observable pattern.
- `Plan/TileViews/MermaidRenderer.swift` (Phase 1) — HTML template helper. Phase 6 adds dark theme, more diagram types.
- `Plan/TileViews/ImageTileView.swift` (65 LOC) — existing image tile. Extend with clipboard paste, file drop.
- `Plan/PlanCanvasView.swift` — canvas-level paste handling for Cmd+V → create image tile.
- `Spec/SpecVersioning.swift` (Phase 4) — version snapshot infrastructure. Phase 6 adds the UI: diff viewer, version comparison.
- `GitPanel/GitRepository.swift` (385 LOC) — `git diff` and `git show` for version comparison rendering.
- `Plan/TileViews/MarkdownTileView.swift` (Phase 1 + Phase 4) — version dropdown already exists from Phase 4. Phase 6 polishes the diff view UI.

### 6.1 Spec Versioning UI

- Version dropdown reads `git log --oneline -- spec.md`
- Past versions render read-only
- Right-click two versions → inline diff view

### 6.2 Browser Tile: Diagrams

- Mermaid.js bundled locally for offline rendering
- Agent generates Mermaid code → browser tile renders via `loadHTMLString`
- Supports: flowcharts, sequence diagrams, journey maps, decision matrices, architecture diagrams
- Also supports raw HTML/SVG from agents

### 6.3 Figma Embeds

- Browser tile loads Figma embed URLs (`figma.com/embed?...`)
- Lazy-load: WKWebView created only when tile is in viewport
- Thumbnail fallback when scrolling offscreen
- Max 2-3 active WKWebViews simultaneously

### 6.4 Image Tile Improvements

- Paste/drop from clipboard (Cmd+V on canvas → creates image tile)
- Paper exports dropped as files
- Supports PNG, JPG, SVG

### 6.5 Three Visual Approaches

1. **Paper export → image tile** — static PNG/SVG. Manual re-export on changes.
2. **Figma embed → browser tile** — live embed URL. Lazy-loaded. May require Figma auth first time.
3. **Agent-generated HTML/SVG → browser tile** — via `loadHTMLString`. Includes Mermaid diagrams.

### Phase 6 Verification (final checks)

1. **Mermaid rendering** — generate a flowchart, sequence diagram, and journey map via Mermaid in a browser tile. Verify dark theme, readability at different zoom levels, no JS errors.
2. **Figma embed** — load a Figma embed URL in a browser tile. Verify it renders (may need Figma login first time). Verify lazy-load: scroll tile offscreen → WKWebView should be replaced with thumbnail. Scroll back → restores.
3. **WKWebView limit** — open 4+ browser tiles. Verify only 2-3 have active WKWebViews. Others show thumbnails. No memory spike.
4. **Image tile paste** — Cmd+V with an image on clipboard while no tile is selected. Verify image tile creates at canvas center with the pasted image.
5. **Image tile drop** — drag a PNG from Finder onto the canvas. Verify image tile creates.
6. **Spec version diff** — right-click two versions in the dropdown → verify inline diff renders showing additions/removals between versions.
7. **End-to-end workflow** — run the full cycle: create task → plan mode → add agents → conversations → Send To Spec → edit spec → finalize → build mode → builder executes → checkboxes update → back to plan → verify everything. This is the acceptance test.

---

## Tile Type Summary

| Tile | Element Type | Rendering | Weight | Phase |
|------|-------------|-----------|--------|-------|
| Text Box | `ElementKind.text(TextData)` | Single-line TextField, auto-width, TextStyleToolbar | Light | 1 ✅ |
| Sticky Note | `TileType.stickyNote` | SwiftUI TextEditor, click-to-edit | Light | 1 ✅ |
| Markdown | `TileType.markdown(path:)` | Section-based editor, checkboxes, source attribution | Medium | 1 ✅ |
| Browser | `TileType.browser(url:)` | WKWebView (URL + loadHTMLString) | Heavy (lazy) | 1 ✅ |
| Image | `TileType.image(path:)` | SwiftUI Image | Light | 1 ✅ |
| Terminal | `TileType.terminal(panelId:agent:)` | Ghostty Metal surface | Heavy | Existing |
| Chat Agent | `TileType.chatAgent` (Phase 2) | ScrollView + LazyVStack, stream-json parsed | Medium | 2 |

---

## Token Optimization Strategy

- **Model tiering:** Haiku for summaries (~500 tokens each), Sonnet for review/research, Opus for planning/building. Switchable per-turn.
- **Summary caching:** source hasn't changed → serve cached, zero tokens. 3 agents reading same source = 1 generation.
- **Lazy context loading:** agents pull connected context when they need it, not automatically every turn.
- **Auth:** Max plan via existing CLI OAuth. No API keys.
- **Tracking:** exact token counts from stream-json responses, displayed per-tile and globally.

---

## Canvas UX

- **Empty state:** truly blank canvas. Right-click to add tiles. No templates.
- **Frames:** existing feature for grouping version explorations side-by-side.
- **Keyboard:** `Cmd+Shift+P` toggles Plan/Build. Existing shortcuts preserved.
- **SPEC.md access:** every agent's system prompt mentions SPEC.md exists. Available via MCP `read_spec()`.

---

## Files to Create

| File | Phase | Purpose | Status |
|------|-------|---------|--------|
| `Plan/TileDragHandler.swift` | 1 | Drag gesture extraction | ✅ |
| `Plan/TileResizeHandler.swift` | 1 | Resize gesture extraction | ✅ |
| `Plan/TileSelectionManager.swift` | 1 | Selection/focus extraction | ✅ |
| `Plan/FrameContainerView.swift` | 1 | Frame layout extraction | ✅ |
| `Plan/TileViews/StickyNoteView.swift` | 1 | Lightweight sticky note | ✅ |
| `Plan/TileViews/TextContentView.swift` | 1 | Text element view + TextStyleToolbar (replaced TextBoxView) | ✅ |
| `Plan/TileViews/MarkdownTileView.swift` | 1 | Section-based markdown editor | ✅ |
| `Plan/TileViews/MermaidRenderer.swift` | 1 | Mermaid HTML template helper | ✅ |
| `BudahADETests/SpecParserTests.swift` | 1 | SpecParser unit tests (6 tests) | ✅ |
| `BudahADETests/CanvasNodeTests.swift` | 1 | TileType, FrameData, TextData tests (8 tests) | ✅ |
| `BudahADETests/MarkdownSectionParserTests.swift` | 1 | MarkdownSection parser tests (6 tests) | ✅ |
| `Agent/CLISubprocessManager.swift` | 2 | CLI subprocess lifecycle | ✅ |
| `Agent/AgentSession.swift` | 2 | Session model + message parsing | ✅ |
| `Agent/ChatMessage.swift` | 2 | Message data model | ✅ |
| `Agent/AgentRole.swift` | 2 | Role definitions | ✅ |
| `Plan/TileViews/ChatTileView.swift` | 2 | Chat agent canvas tile | ✅ |
| `Plan/TileViews/SendToMenu.swift` | 2 | Send to dropdown component | ✅ |
| `Plan/CanvasPersistence.swift` | 2.5 | Canvas save/load to `.budahade/canvas.json` | ✅ |
| `Plan/ConnectionsLayer.swift` | 3 | Arrow rendering via Canvas API |
| `Plan/TileConnection.swift` | 3 | Connection data model |
| `Plan/TileOutputProvider.swift` | 3 | Protocol + TileOutput enum |
| `Plan/SummaryGenerator.swift` | 3 | Haiku summary via subprocess |
| `Plan/ContextAssembler.swift` | 3 | Assembles connected context |
| `Spec/SpecVersioning.swift` | 4 | Git-based version snapshots |
| `Spec/SpecBranching.swift` | 4 | Variant fork/merge |
| `Spec/MarkdownSectionParser.swift` | 4 | Heading-based section splitting (note: basic version shipped in Phase 1 inside SpecParser.swift) |
| `MCP/MCPServer.swift` | 5 | MCP protocol handler |
| `MCP/MCPSocket.swift` | 5 | Unix domain socket comms |
| `MCP/MCPTools.swift` | 5 | Tool implementations |
| `MCP/budahade-mcp` (executable) | 5 | Bundled MCP server binary |

## Files to Modify

| File | Phase | Changes | Status |
|------|-------|---------|--------|
| `Plan/CanvasElementView.swift` | 1 | Decompose from 1,041 → 180 LOC shell, hover X on text elements | ✅ |
| `Plan/PlanCanvasView.swift` | 1 | Debounced viewport culling, removed double-click terminal creation | ✅ |
| `Plan/TileViews/BrowserTileView.swift` | 1 | Add loadHTMLString, isVisible parameter | ✅ |
| `Plan/TileType.swift` | 1 | Remove document/specDocument/textBox, add stickyNote/markdown | ✅ |
| `Plan/AddTileMenu.swift` | 1 | Update callbacks (note: dead code, not instantiated) | ✅ |
| `Plan/PlanCanvasState.swift` | 1 | Tile sizes, mutationCount, min-size for text elements | ✅ |
| `Plan/ContextManifest.swift` | 1 | Update tile type switches | ✅ |
| `Spec/SpecParser.swift` | 1 | MarkdownSection, parseMarkdownSections, toggleCheckbox, slugify internal | ✅ |
| `Spec/SpecAssembler.swift` | 1 | Update tile type switches | ✅ |
| `Task/NewTaskSheet.swift` | 1 | Branch picker dropdown | ✅ |
| `GitPanel/GitRepository.swift` | 1 | listBranches static method, Sendable fixes | ✅ |
| `Terminal/TerminalSurfaceView.swift` | 1 | var→let warning fix | ✅ |
| `Plan/ScrollWheelMonitor.swift` | 1 | textInputHasFocus check for spacebar/escape passthrough | ✅ |
| `Plan/AgentPrompts.swift` | 2 | Extend with role system | ✅ |
| `Plan/TileType.swift` | 2 | Add `.chatAgent`, `AgentMode` tools/turns, Codable | ✅ |
| `Plan/CanvasNode.swift` | 2.5 | Codable for CanvasElement, ElementKind, FrameData, TextData | ✅ |
| `Plan/CanvasElementView.swift` | 2 | Chat agent dispatch, cursor fix (push/pop → set) | ✅ |
| `Plan/PlanCanvasState.swift` | 2-2.5 | Chat sessions, persistence (save/load/restore) | ✅ |
| `Plan/PlanCanvasView.swift` | 2 | Add Chat Agent context menu | ✅ |
| `Plan/AddTileMenu.swift` | 2 | Chat agent section | ✅ |
| `Plan/TileResizeHandler.swift` | 2 | Cursor fix (push/pop → set) | ✅ |
| `Plan/TileViews/TileChrome.swift` | 2 | Font bumps, cursor fix on X button | ✅ |
| `Plan/TileViews/MarkdownTileView.swift` | 2 | Font bumps | ✅ |
| `Plan/TileViews/StickyNoteView.swift` | 2 | Font bump | ✅ |
| `Terminal/TerminalSurfaceView.swift` | 2 | Opt+P fix (translation_mods, unshifted_codepoint) | ✅ |
| `Terminal/TerminalSurface.swift` | 2 | Matching key event fixes | ✅ |
| `Terminal/GhosttyAppManager.swift` | 2 | macos-option-as-alt config override | ✅ |
| `Task/TaskState.swift` | 2-5 | Canvas persistence on task switch, MCP lifecycle | ✅ (Phase 2) |
| `App/BudahADEApp.swift` | 2.5 | Save canvases on app quit | ✅ |
| `Task/GitWorktreeManager.swift` | 2 | Prune stale refs, force-add, remove stale .git/worktrees | ✅ |
| `Workspace/WorkspaceState.swift` | 5 | MCP server lifecycle per task | |
| `Spec/SpecPanelView.swift` | 5 | Upgrade checklist UI for build mode | |
| `Spec/SpecState.swift` | 4-5 | Versioning, MCP integration | |

## Files to Delete

| File | Phase | Reason | Status |
|------|-------|--------|--------|
| `Plan/TileViews/RichTextEditor.swift` | 1 | Replaced by lightweight text tiers (339 LOC) | ✅ Deleted |
| `Plan/TileViews/DocumentTileView.swift` | 1 | Replaced by MarkdownTileView (100 LOC) | ✅ Deleted |
| `Plan/TileViews/SpecDocumentTileView.swift` | 1 | Refactored into MarkdownTileView (242 LOC) | ✅ Deleted |
| `Plan/TileViews/TextBoxView.swift` | 1 | Merged into TextContentView (text element) | ✅ Deleted |

---

## Testing Strategy

Each phase has its own test targets:

**Phase 1:** Canvas performance benchmarks (15 tiles, measure frame time during pan/zoom). Viewport culling verification (offscreen tiles have no WKWebView instances). Markdown section parser unit tests.

**Phase 2:** CLISubprocessManager integration tests (spawn, send, resume, cancel). Stream-json parsing unit tests. Token counting accuracy.

**Phase 3:** Connection data model unit tests. Summary caching logic (stale detection, cache invalidation). Context assembly output format.

**Phase 4:** Spec versioning (auto-commit messages, version listing). Spec branching (fork, merge, cleanup). Section parser round-trip (parse → edit → serialize).

**Phase 5:** MCP server protocol compliance. Socket communication reliability. mark_spec_item → UI update latency. File-watching fallback verification.

**Phase 6:** Mermaid rendering in browser tile. Figma embed loading. Image paste/drop handling.

---

## Out of Scope (V2)

- Synthesis agent for conflict resolution between parallel features
- Bidirectional canvas ↔ spec file sync (currently one-directional: canvas → file)
- Connection labels/types (depends-on, informs, conflicts-with)
- Export canvas as PDF/shareable link
- Collaborative multi-user canvas
- Hybrid AppKit canvas layer (deferred — evaluate after Phase 1 performance fixes; if SwiftUI viewport culling achieves targets, AppKit rewrite may not be needed)
