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

## Phase 1: Canvas Performance + Lighter Tiles

### 1.1 Decompose CanvasElementView

`CanvasElementView.swift` is 1,041 LOC — a god file. Split into focused files:

| New File | Responsibility | ~LOC |
|----------|---------------|------|
| `CanvasElementView.swift` | Shell: dispatches to content + chrome | 150 |
| `TileDragHandler.swift` | Drag gesture, frame intersection detection | 120 |
| `TileResizeHandler.swift` | Resize handles + gesture | 80 |
| `TileSelectionManager.swift` | Focus, selection state, keyboard | 60 |
| `FrameContainerView.swift` | Frame-specific: child layout, insertion indicator | 150 |

### 1.2 Simplify Text Tile Types

**Remove:**
- `RichTextEditor.swift` (339 LOC) — NSTextView wrapper, heavy
- `DocumentTileView.swift` (100 LOC) — replaced by markdown tile

**New text tiers:**

**Sticky Note** — plain text, auto-sizes to content. SwiftUI `TextEditor` with dynamic height. ~30 LOC.

**Text Box** — multi-line plain text, user-sized. For longer notes that need explicit dimensions. ~40 LOC.

**Markdown Tile** — the spec/document tile. Features:
- Section-based inline editing: each `## heading` block is independently click-to-edit. Click a section → becomes `TextEditor`. Click away → renders as styled markdown via `AttributedString`.
- Source attribution per section: stored as `<!-- source: tile-uuid -->` HTML comments in the markdown. Rendered as colored dot + label ("from Ideator").
- Interactive checkboxes: `- [ ]` / `- [x]` toggle on click, writes back to file on disk.
- Header: title, source count, Draft/Finalized badge.
- Footer: file reference (`spec.md`), section/checkbox counts, Edit button, Finalize → Build button.
- Version dropdown in header: lists named snapshots from git history for this file. Select past version → read-only view. Select current → editable.
- Duplicate action: creates copy tile on canvas pointing to a branched variant file.

**Parser:** Extend existing `SpecParser.swift` to split by `## headings` into `[MarkdownSection]` structs: `{ heading, body, sourceId, isEditing, checkboxItems }`.

### 1.3 Viewport Culling

- `PlanCanvasView` already filters `visibleElements` — tighten to skip `body` evaluation for offscreen tiles.
- Browser tiles: replace WKWebView with static screenshot thumbnail when offscreen, restore on scroll-in.
- Debounce viewport calculations to 100ms during gestures.
- Target: zero WKWebView/NSTextView instances for offscreen tiles.

### 1.4 BrowserTileView Enhancements

- Add `loadHTMLString(_ html: String, baseURL: URL?)` path alongside existing URL loading.
- Bundle `mermaid.min.js` (~300KB) in app resources.
- `MermaidRenderer.htmlPage(diagramCode: String, theme: .dark) -> String` helper wraps diagram in HTML template.
- Supports: Mermaid diagrams, raw HTML/SVG from agents, Figma embed URLs.

### 1.5 Branch Picker in NewTaskSheet

- Replace text field with `Picker` backed by `GitRepository.branches()`.
- Default selection: `main`.
- Shows all local branches from current repo.

### Performance Targets

- Canvas with 15 tiles: <16ms frame time during pan/zoom
- Offscreen tiles: zero WKWebView instances, zero heavy text views
- Gesture responsiveness: no dropped frames during drag

### Phase 1 Verification (check before starting Phase 2)

1. **Performance** — measure frame time with 15 tiles during pan/zoom. Must hit <16ms. If not, fix before proceeding — every later phase adds more tiles.
2. **MarkdownTileView** — verify section-based inline editing works: click section → edit → click away → renders. Checkbox toggling writes back to file. Source attribution renders with colored dot + label. This is the spec tile foundation.
3. **BrowserTileView loadHTMLString** — render a Mermaid diagram via `loadHTMLString`. Verify dark theme, scaling, no blank flashes. Derisks Phase 6.
4. **Tile decomposition regressions** — test drag, resize, frame containment, selection, keyboard shortcuts. CanvasElementView split likely introduced subtle bugs.
5. **Text tile feel** — sticky notes auto-size correctly? Text boxes resize smoothly? Markdown render quality acceptable? If the UX nags, fix now — cheaper than after Phase 4 builds on it.
6. **Branch picker** — NewTaskSheet shows branch dropdown populated from repo. Default is main. Can select any branch.
7. **Deleted files** — confirm RichTextEditor.swift and DocumentTileView.swift are gone. No dead references.

---

## Phase 2: CLI Subprocess Agent System + Chat UI Tile

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
    let name: String           // "Ideator", "Developer", etc.
    let systemPrompt: String
    let defaultModel: AgentModel
    let color: Color
}
```

- Built-in roles: Ideator (Opus), Developer (Sonnet), Researcher (Sonnet), Reviewer (Sonnet)
- Custom roles: user-created via settings
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

### Phase 2 Verification (check before starting Phase 3)

1. **Subprocess lifecycle** — spawn a chat agent, send 3 messages, verify multi-turn works via `--session-id` + `--resume`. Cancel mid-stream, verify process kills cleanly.
2. **Stream-json parsing** — verify all message types parse correctly: text content, tool calls, errors. No dropped events, no malformed messages.
3. **ChatTileView rendering** — user messages right-aligned, agent messages left-aligned with markdown. Tool calls collapsed. Scrolls to bottom on new message. LazyVStack performs with 50+ messages.
4. **Model switching** — change model mid-conversation via header picker. Next message uses new model. Verify `--model` flag applies correctly.
5. **Send To** — test "Send to Spec" on an agent message: new section appears in markdown tile with content, user can edit. Test "Send to Agent": creates new agent tile if needed, content appears as context.
6. **Image paste** — paste image into input area, verify thumbnail preview, verify image path referenced in prompt, verify agent responds to the image.
7. **Token tracking** — verify token count in header updates after each turn. Values should be plausible (not zero, not absurdly high).
8. **Agent roles** — create Ideator (Opus), Developer (Sonnet). Verify system prompts apply and model defaults are correct.

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

---

## Tile Type Summary

| Tile | Rendering | Weight | Phase |
|------|-----------|--------|-------|
| Sticky Note | SwiftUI TextEditor, auto-sizing | Light | 1 |
| Text Box | SwiftUI TextEditor, user-sized | Light | 1 |
| Markdown | Section-based editor, AttributedString render | Medium | 1 |
| Browser | WKWebView (URL + loadHTMLString) | Heavy (lazy) | 1 |
| Image | SwiftUI Image | Light | 1 |
| Terminal | Ghostty Metal surface | Heavy | Existing |
| Chat Agent | ScrollView + LazyVStack, stream-json parsed | Medium | 2 |

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

| File | Phase | Purpose |
|------|-------|---------|
| `Plan/TileDragHandler.swift` | 1 | Drag gesture extraction |
| `Plan/TileResizeHandler.swift` | 1 | Resize gesture extraction |
| `Plan/TileSelectionManager.swift` | 1 | Selection/focus extraction |
| `Plan/FrameContainerView.swift` | 1 | Frame layout extraction |
| `Plan/TileViews/StickyNoteView.swift` | 1 | Lightweight sticky note |
| `Plan/TileViews/TextBoxView.swift` | 1 | Plain text box |
| `Plan/TileViews/MarkdownTileView.swift` | 1 | Section-based markdown editor |
| `Plan/TileViews/MermaidRenderer.swift` | 1 | Mermaid HTML template helper |
| `Agent/CLISubprocessManager.swift` | 2 | CLI subprocess lifecycle |
| `Agent/AgentSession.swift` | 2 | Session model + message parsing |
| `Agent/ChatMessage.swift` | 2 | Message data model |
| `Agent/AgentRole.swift` | 2 | Role definitions |
| `Plan/TileViews/ChatTileView.swift` | 2 | Chat agent canvas tile |
| `Plan/TileViews/SendToMenu.swift` | 2 | Send to dropdown component |
| `Plan/ConnectionsLayer.swift` | 3 | Arrow rendering via Canvas API |
| `Plan/TileConnection.swift` | 3 | Connection data model |
| `Plan/TileOutputProvider.swift` | 3 | Protocol + TileOutput enum |
| `Plan/SummaryGenerator.swift` | 3 | Haiku summary via subprocess |
| `Plan/ContextAssembler.swift` | 3 | Assembles connected context |
| `Spec/SpecVersioning.swift` | 4 | Git-based version snapshots |
| `Spec/SpecBranching.swift` | 4 | Variant fork/merge |
| `Spec/MarkdownSectionParser.swift` | 4 | Heading-based section splitting |
| `MCP/MCPServer.swift` | 5 | MCP protocol handler |
| `MCP/MCPSocket.swift` | 5 | Unix domain socket comms |
| `MCP/MCPTools.swift` | 5 | Tool implementations |
| `MCP/budahade-mcp` (executable) | 5 | Bundled MCP server binary |

## Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| `Plan/CanvasElementView.swift` | 1 | Decompose from 1,041 LOC to ~150 LOC shell |
| `Plan/PlanCanvasView.swift` | 1 | Tighten viewport culling |
| `Plan/TileViews/BrowserTileView.swift` | 1 | Add loadHTMLString, lazy-load |
| `Plan/CanvasNode.swift` | 1 | Add sticky/textbox/markdown tile types, remove document type |
| `Plan/TileType.swift` | 1-2 | Add chatAgent tile type, remove document |
| `Plan/AddTileMenu.swift` | 1-2 | Update tile type menu |
| `Plan/PlanCanvasState.swift` | 3 | Add connections array, persistence |
| `Plan/AgentPrompts.swift` | 2 | Extend with role system |
| `Task/NewTaskSheet.swift` | 1 | Branch picker dropdown |
| `Task/TaskState.swift` | 2-5 | CLI subprocess integration, MCP lifecycle |
| `Workspace/WorkspaceState.swift` | 5 | MCP server lifecycle per task |
| `Spec/SpecParser.swift` | 1 | Extend with heading-based section parsing |
| `Spec/SpecPanelView.swift` | 5 | Upgrade checklist UI for build mode |
| `Spec/SpecState.swift` | 4-5 | Versioning, MCP integration |
| `GitPanel/BranchPicker.swift` | 1 | Used in NewTaskSheet |

## Files to Delete

| File | Phase | Reason |
|------|-------|--------|
| `Plan/TileViews/RichTextEditor.swift` | 1 | Replaced by lightweight text tiers (339 LOC removed) |
| `Plan/TileViews/DocumentTileView.swift` | 1 | Replaced by markdown tile (100 LOC removed) |

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
