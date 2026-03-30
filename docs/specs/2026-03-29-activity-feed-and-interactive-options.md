# Activity Feed & Interactive Options

**Date:** 2026-03-29
**Branch:** TBD
**Scope:** Rich activity feed for tool use visibility in Plan mode, interactive option buttons when Claude presents choices, and stream event parsing fixes.

---

## Problem

Plan mode's thinking indicator shows only "Connecting...", "Thinking...", and a collapsed tool count. The CLI gives far more context — what file Claude is reading, what command it's running, what search it's doing — all visible in real-time before the response. This gap makes the GUI feel opaque. You're staring at a spinner with no idea what's happening.

Second problem: when Claude presents options ("Would you like A or B?"), the user has to type a response. Cursor renders these as clickable buttons. budahADE should too.

---

## Goals

- Surface real-time tool activity as Claude works — what it's doing, what it found, how long it took
- Parse all stream-json event types the CLI emits (currently dropping 5 of 9)
- Render interactive option buttons when Claude presents choices
- Fix the `cost_usd` → `total_cost_usd` bug (cost always reads 0)

## Non-Goals

- Sub-agent tracking via `parent_tool_use_id` (deferred — requires agent teams UI)
- Tool approval/rejection buttons (using `--dangerously-skip-permissions`)
- File diff preview before applying changes (Builder mode concern, not Plan mode)
- Streaming `thinking` content in an expandable panel (deferred — just show "Reasoning..." indicator)

---

## Part 1: Stream Event Parsing Fixes

### Current State

`StreamEvent.parse()` in `ChatMessage.swift` handles 4 event types and drops the rest as `.unknown`:

| Parsed | Dropped |
|--------|---------|
| `system` (init only) | `system:hook_started`, `system:hook_response` |
| `assistant` (text + tool_use) | `assistant` thinking blocks |
| `content_block_delta` (text only) | `content_block_delta` thinking deltas |
| `result` | `user` (tool results), `rate_limit_event` |

### New StreamEvent Cases

```swift
enum StreamEvent: Equatable {
    // Existing
    case system(SystemInfo)
    case assistant(AssistantMessage)
    case contentDelta(String)
    case result(ResultInfo)

    // New
    case toolUse(ToolUseEvent)          // Extracted from assistant content blocks
    case toolResult(ToolResultEvent)    // From `user` events with tool_result content
    case thinking(String)               // From assistant thinking blocks + thinking deltas
    case rateLimitEvent(RateLimitInfo)  // From rate_limit_event
    case hookStarted(HookEvent)        // From system:hook_started (low priority, log only)
    case hookResponse(HookEvent)       // From system:hook_response (low priority, log only)

    case unknown
}
```

### New Event Structs

```swift
struct ToolUseEvent: Equatable {
    let id: String           // tool_use_id — links to the matching tool_result
    let name: String         // "Read", "Bash", "Grep", "Edit", "Write", "Glob", "Agent", etc.
    let inputJSON: String    // Raw JSON string of the input object — parse specific keys on demand
    // Decision: store as raw String instead of [String: AnyCodable] to avoid
    // Equatable/Codable issues with Any. Only 1-2 keys needed per tool for labels.
}

struct ToolResultEvent: Equatable {
    let toolUseId: String    // Matches ToolUseEvent.id
    let content: String      // The tool's output (file contents, stdout, search results)
    let isError: Bool        // Whether the tool errored
}

struct RateLimitInfo: Equatable {
    let status: String       // "allowed" or "throttled"
    let resetsAt: String?    // ISO timestamp when throttle lifts
    let rateLimitType: String?
}

struct HookEvent: Equatable {
    let hookId: String
    let hookName: String
    let hookEvent: String
}
```

### Parsing Changes

In `StreamEvent.parse()`:

1. **`system` events** — check `subtype` field:
   - `"init"` → `.system(SystemInfo)` (existing)
   - `"hook_started"` → `.hookStarted(HookEvent)`
   - `"hook_response"` → `.hookResponse(HookEvent)`

2. **`assistant` events** — iterate content array and emit per-block:
   - `type: "text"` → continue accumulating into AssistantMessage as today
   - `type: "tool_use"` → emit `.toolUse(ToolUseEvent)` AND include in AssistantMessage.toolCalls
   - `type: "thinking"` → emit `.thinking(text)`

3. **`user` events** — NEW parsing:
   - Content array contains `tool_result` blocks
   - Each has `tool_use_id`, `content` (string or array), `is_error`
   - Emit `.toolResult(ToolResultEvent)`

4. **`content_block_delta`** — check `delta.type`:
   - `"text_delta"` → `.contentDelta(text)` (existing)
   - `"thinking_delta"` → `.thinking(text)` (new)

5. **`rate_limit_event`** → `.rateLimitEvent(RateLimitInfo)`

6. **`result`** — fix field name: read `total_cost_usd` instead of `cost_usd`. Also read `num_turns`, `duration_api_ms`, `stop_reason`.

### processStreamLine Changes

In `CLISubprocessManager.processStreamLine()`, handle new cases:

```swift
case .toolUse(let event):
    session.handleToolUse(event)
case .toolResult(let event):
    session.handleToolResult(event)
case .thinking(let text):
    session.handleThinking(text)
case .rateLimitEvent(let info):
    session.handleRateLimit(info)
case .hookStarted, .hookResponse:
    break  // Log only, no UI action
```

---

## Part 2: Activity Feed

### Data Model

Add to `AgentSession`:

```swift
/// Live activity entries — tool calls in progress and completed
@Published var activityFeed: [ActivityFeedEntry] = []

/// Current rate limit status
@Published var rateLimitStatus: RateLimitInfo?

/// Whether Claude is in extended thinking
@Published var isThinking: Bool = false
```

```swift
struct ActivityFeedEntry: Identifiable, Equatable {
    let id: String                    // Use tool_use_id for tool entries
    let kind: ActivityKind
    let label: String                 // Human-readable: "Reading Package.swift"
    let detail: String?               // Optional secondary line: "485 lines", "exit code 0"
    let timestamp: Date
    var status: ActivityStatus

    enum ActivityStatus: Equatable {
        case inProgress
        case completed
        case failed
    }
}

enum ActivityKind: Equatable {
    case thinking
    case toolRead(filePath: String)
    case toolGrep(pattern: String)
    case toolGlob(pattern: String)
    case toolBash(command: String)
    case toolEdit(filePath: String)
    case toolWrite(filePath: String)
    case toolAgent(description: String)
    case toolWebSearch(query: String)
    case toolWebFetch(url: String)
    case toolOther(name: String)
    case rateLimit
}
```

### Mapping Tool Events to Activity Labels

In `AgentSession.handleToolUse()`:

```swift
func handleToolUse(_ event: ToolUseEvent) {
    let (label, kind) = activityLabel(for: event)
    let entry = ActivityFeedEntry(
        id: event.id,
        kind: kind,
        label: label,
        detail: nil,
        timestamp: Date(),
        status: .inProgress
    )
    activityFeed.append(entry)
}
```

Label extraction rules — parse `event.input` to get human-readable context:

| Tool | Input key | Label format | Example |
|------|-----------|-------------|---------|
| `Read` | `file_path` | "Reading `{filename}`" | "Reading `Package.swift`" |
| `Grep` | `pattern` | "Searching for `{pattern}`" | "Searching for `handleAuth`" |
| `Glob` | `pattern` | "Finding files `{pattern}`" | "Finding files `**/*.swift`" |
| `Bash` | `command` | "Running `{command}`" | "Running `swift build`" |
| `Edit` | `file_path` | "Editing `{filename}`" | "Editing `App.swift`" |
| `Write` | `file_path` | "Writing `{filename}`" | "Writing `Config.swift`" |
| `Agent` | `prompt` | "Researching: {first 40 chars}" | "Researching: how auth middleware..." |
| `WebSearch` | `query` | "Searching web: {query}" | "Searching web: SwiftUI PTY" |
| `WebFetch` | `url` | "Fetching {domain}" | "Fetching github.com" |
| Other | — | "Using {tool name}" | "Using LSP" |

For file paths, show only the filename (last path component), not the full path. The full path goes in `detail` on hover.

Truncate all labels to 60 characters max.

### Completing Activity Entries

In `AgentSession.handleToolResult()`:

```swift
func handleToolResult(_ event: ToolResultEvent) {
    guard let index = activityFeed.firstIndex(where: { $0.id == event.toolUseId }) else { return }
    activityFeed[index].status = event.isError ? .failed : .completed
    activityFeed[index].detail = summarizeToolResult(event, kind: activityFeed[index].kind)
}
```

Result summary rules:

| Kind | Summary format | Example |
|------|---------------|---------|
| `toolRead` | "{lineCount} lines" | "485 lines" |
| `toolGrep` | "{matchCount} matches" (count newlines in content) | "12 matches" |
| `toolGlob` | "{fileCount} files" | "8 files" |
| `toolBash` | "exit {code}" or first 40 chars of stdout | "exit 0" |
| `toolEdit` | "done" | "done" |
| `toolWrite` | "done" | "done" |
| `toolAgent` | "done" | "done" |
| Error (any) | First 40 chars of error content | "File not found" |

### Rate Limit Handling

In `AgentSession.handleRateLimit()`:

```swift
func handleRateLimit(_ info: RateLimitInfo) {
    rateLimitStatus = info
    if info.status == "throttled" {
        let entry = ActivityFeedEntry(
            id: UUID().uuidString,
            kind: .rateLimit,
            label: "Rate limited — waiting...",
            detail: info.resetsAt,
            timestamp: Date(),
            status: .inProgress
        )
        activityFeed.append(entry)
    }
}
```

---

## Part 3: Activity Feed UI

### Replace ThinkingIndicator

The current `ThinkingIndicator` in `PlanChatView` (the braille spinner + activity carousel) is replaced with a richer `ActivityFeedView`.

### ActivityFeedView

Appears in the same position — below the last message, above the input — whenever Claude is working.

```
┌─────────────────────────────────────────────────┐
│  ✓ Reading CLISubprocessManager.swift   485 ln  │  ← completed, faded
│  ✓ Searching for "handleAuth"          12 hits  │  ← completed, faded
│  ◉ Running swift build                  3.2s ●  │  ← in progress, bright
│                                                  │
│  ⠋ 4.7s                                         │  ← braille spinner + timer
└─────────────────────────────────────────────────┘
```

**Layout per entry:**

```
[StatusIcon 12px] [Label — left aligned, mono 12] [Spacer] [Detail — right aligned, mono 10, muted]
```

**Status icons:**

| Status | Icon | Color |
|--------|------|-------|
| In progress | `circle.fill` 5px | `Theme.accent` with pulse animation |
| Completed | `checkmark` 8px | `Theme.textMuted` |
| Failed | `xmark` 8px | `.red.opacity(0.7)` |

**Visual rules:**

- Show last 4 entries maximum. Older entries scroll out.
- In-progress entries: `Theme.textPrimary`, full opacity
- Completed entries: `Theme.textMuted`, 0.5 opacity, no animation
- Failed entries: `.red.opacity(0.7)` for icon and label
- Entry height: 22px
- Left padding: 4px (aligns with message content)
- Transition: entries slide in from bottom with `.move(edge: .bottom).combined(with: .opacity)`
- Rate limit entry: amber/warning color, shows countdown if `resetsAt` is available

**Elapsed timer:** still shown at the bottom, same braille spinner pattern as current ThinkingIndicator. Timer starts from `session.status == .connecting` and runs until response begins streaming.

**Thinking indicator:** When `session.isThinking == true` and no tool calls are active, show "Reasoning..." as a standalone entry with a subtle pulse.

### Hiding the Feed

The activity feed disappears when:
- `session.status == .done` or `.idle`
- A text content delta arrives (response is streaming — feed collapses, streaming text takes over)

Collapse animation: feed shrinks to 0 height over 0.2s with `.easeOut`.

---

## Part 4: Interactive Options

### Detection

When an assistant message is finalized (added to `messages[]`), scan its content for option patterns. This runs as a post-processing step in `handleAssistantMessage()`.

**Pattern matching — detect numbered or lettered options:**

```swift
struct DetectedOption: Identifiable {
    let id: Int              // 0-indexed
    let label: String        // "A", "B", "1", "2", etc.
    let text: String         // The option description text
    let fullLine: String     // The complete line for sending back as response
}
```

**Regex patterns to match:**

```
// Numbered: "1. Do something" or "1) Do something"
^\s*(\d+)[.)]\s+(.+)$

// Lettered: "A. Do something" or "A) Do something" or "a. Do something"
^\s*([A-Za-z])[.)]\s+(.+)$

// Dash/bullet options after a question: "- Option one"
^\s*[-•]\s+\*?\*?(.+?)\*?\*?\s*$
```

**Qualifying conditions (ALL must be true):**

1. The message ends with a question mark on its last non-empty line, OR contains a line matching "which.*prefer|would you like|should I|do you want" (case insensitive)
2. At least 2 matching option lines found
3. No more than 6 option lines (beyond that, it's a list, not options)
4. Option lines appear after the question line, or in the final paragraph

**False positive guard:** If the options are inside a code block (between ``` fences), skip them. If the options are part of a numbered list that appears to be instructional steps (detected by having >6 items or not following a question), skip them.

### Data Model

**Decision: transient, not persisted.** `DetectedOption` is NOT stored on `ChatMessage` (which is `Codable`/persisted). Instead, options are computed on the fly for the last assistant message only, and a `@Published var optionsDismissed: Bool` on `AgentSession` tracks whether the user has interacted. This avoids unnecessary persistence overhead for a temporary UI element.

`detectOptions(in:)` lives on `AgentSession` and is called from the view layer when rendering the last assistant message.

### UI — Option Buttons

When `message.detectedOptions` is non-nil and non-empty, render a button row below the assistant message bubble:

```
┌──────────────────────────────────────────────────┐
│  Claude's message ending with "Which approach    │
│  would you prefer?"                              │
│                                                  │
│  1. Quick refactor    2. Full rewrite            │
│  ─────────────────    ───────────────            │
└──────────────────────────────────────────────────┘

  [ 1. Quick refactor ]  [ 2. Full rewrite ]        ← option buttons
```

**Button styling:**

- Layout: horizontal `LazyVGrid` with flexible columns, wrapping to next row if >3 options. 8px horizontal gap, 6px vertical gap.
- Each button: ghost style — `borderSubtle` border, `Theme.surface2` background, 8px vertical padding, 12px horizontal padding, 8px corner radius.
- Label: `Theme.mono(12)` for the option number/letter, `Theme.body(13)` for the text. Truncate text at 50 characters.
- Hover: background brightens to `Theme.hoverFill`, border to `borderActive`.
- Max button width: 240px. If text exceeds, truncate with ellipsis.

**On click:**

1. The option's `label` + `text` is sent as a user message via `state.sendMessage("Option \(label): \(text)")`. Or just the number/letter if the options are clearly labeled: `state.sendMessage(label)`.
2. The option buttons disappear (set `detectedOptions = nil` on the message or track a `@Published var optionsUsed: Set<UUID>` on the session).
3. The sent message appears as a normal user bubble.

**Only show on the LAST assistant message.** Once the user sends any message (whether by clicking an option or typing), option buttons on all previous messages are hidden.

---

## Part 5: Updated AgentSession Event Handlers

Summary of new methods on `AgentSession`:

```swift
// New handlers
func handleToolUse(_ event: ToolUseEvent)
func handleToolResult(_ event: ToolResultEvent)
func handleThinking(_ text: String)
func handleRateLimit(_ info: RateLimitInfo)

// New helpers
private func activityLabel(for event: ToolUseEvent) -> (String, ActivityKind)
private func summarizeToolResult(_ event: ToolResultEvent, kind: ActivityKind) -> String
private func detectOptions(in text: String) -> [DetectedOption]?
```

### Migration from pendingToolCalls + ActivityEntry

The existing `pendingToolCalls: [ToolCall]` array and `ActivityEntry` struct in `PlanChatView` are replaced by the `activityFeed: [ActivityFeedEntry]` on `AgentSession`. Remove:

- `@Published var pendingToolCalls: [ToolCall]` from AgentSession
- `@State private var activityLog: [ActivityEntry]` from PlanChatView
- `@State private var lastToolCallCount: Int` from PlanChatView
- The `ActivityEntry` struct from PlanChatView
- The `ThinkingIndicator` struct from PlanChatView
- The `.onChange(of: session?.pendingToolCalls.count)` handler

The tool call collapsing in assistant messages (the "3 tools" compact display) still uses `message.toolCalls` from `ChatMessage` — that stays. The activity feed is the live, during-turn view. The collapsed tool count is the after-the-fact, in-history view.

---

## Files Changed

| File | Change |
|------|--------|
| `BudahADE/Agent/ChatMessage.swift` | Add new StreamEvent cases, new event structs, update parse() for all event types, fix `total_cost_usd`, add `DetectedOption` to ChatMessage |
| `BudahADE/Agent/AgentSession.swift` | Add `activityFeed`, `rateLimitStatus`, `isThinking`. Add handler methods. Add `detectOptions()`. Remove `pendingToolCalls`. |
| `BudahADE/Agent/CLISubprocessManager.swift` | Update `processStreamLine()` to handle new event cases |
| `BudahADE/Plan/PlanChatView.swift` | Replace `ThinkingIndicator` with `ActivityFeedView`. Add option buttons below assistant messages. Remove `activityLog`, `lastToolCallCount`, `ActivityEntry`. |
| `BudahADE/Plan/ActivityFeedView.swift` | **NEW** — the activity feed component |

## Unchanged

`PlanChatState`, `AgentMode`, `AgentRole`, `AgentPrompts`, `Theme`, `CLISubprocessManager.buildInteractiveCommand()`, `PlanTabBar`

---

## Dependency

None — uses only existing frameworks (SwiftUI, Foundation). The `swift-markdown` dependency added by the markdown renderer spec is unrelated.

---

## Implementation Plan

### Phase 1: Stream Event Parsing (foundation — everything else depends on this)

- [ ] **1.1 Add new event structs** — `ToolUseEvent`, `ToolResultEvent`, `RateLimitInfo`, `HookEvent`, `DetectedOption` in `ChatMessage.swift`
- [ ] **1.2 Add new StreamEvent cases** — `.toolUse`, `.toolResult`, `.thinking`, `.rateLimitEvent`, `.hookStarted`, `.hookResponse`
- [ ] **1.3 Update `StreamEvent.parse()`** — handle `system` subtypes (`init` vs `hook_started` vs `hook_response`), parse `user` events with `tool_result` content, extract `thinking` blocks from `assistant` content array, parse `rate_limit_event`, parse `content_block_delta` thinking deltas
- [ ] **1.4 Fix `result` parsing** — read `total_cost_usd` instead of `cost_usd`. Also capture `num_turns`, `duration_api_ms`, `stop_reason`.
- [ ] **1.5 Update `processStreamLine()`** — add switch cases for all new event types, route to session handlers

**Verify:** Add a print/log statement in each new case. Launch app, send a message that triggers tool use (e.g. "Read the CLAUDE.md file"). Confirm timing log shows all event types being parsed — no `.unknown` entries for real events.

### Phase 2: Activity Feed Data Model

- [ ] **2.1 Add `ActivityFeedEntry` struct and `ActivityKind` enum** — new file or in `AgentSession.swift`
- [ ] **2.2 Add published properties to `AgentSession`** — `activityFeed: [ActivityFeedEntry]`, `rateLimitStatus: RateLimitInfo?`, `isThinking: Bool`
- [ ] **2.3 Implement `handleToolUse()`** — create `ActivityFeedEntry` with `.inProgress` status, extract label from tool input using the mapping table (Read → "Reading `{filename}`", Bash → "Running `{command}`", etc.)
- [ ] **2.4 Implement `handleToolResult()`** — find matching entry by `toolUseId`, update status to `.completed` or `.failed`, set detail string using summary rules (line count, match count, exit code, etc.)
- [ ] **2.5 Implement `handleThinking()`** — set `isThinking = true`, add thinking entry to feed. Reset `isThinking = false` when first tool_use or text content arrives.
- [ ] **2.6 Implement `handleRateLimit()`** — store status, append rate limit entry if throttled
- [ ] **2.7 Clear feed on turn completion** — when `handleResult()` fires, mark all in-progress entries as completed. Do NOT clear the array — the UI handles fade-out.

**Verify:** Set breakpoints or log in each handler. Send a multi-tool prompt. Confirm `activityFeed` array populates with correct labels and transitions from `.inProgress` → `.completed`.

### Phase 3: Activity Feed UI

- [ ] **3.1 Create `ActivityFeedView.swift`** — new file in `BudahADE/Plan/`. Takes `activityFeed: [ActivityFeedEntry]`, `isThinking: Bool`, `startDate: Date?` as inputs. Renders last 4 entries with status icons, labels, details. Braille spinner + timer at bottom.
- [ ] **3.2 Replace `ThinkingIndicator` in `PlanChatView`** — swap the existing `ThinkingIndicator(activityLog:startDate:)` call with `ActivityFeedView(...)` bound to `session.activityFeed`, `session.isThinking`, `thinkingStartDate`.
- [ ] **3.3 Remove old activity infrastructure** — delete `@State activityLog`, `@State lastToolCallCount`, the `ActivityEntry` struct, the `ThinkingIndicator` struct, and the `.onChange(of: session?.pendingToolCalls.count)` handler from `PlanChatView`.
- [ ] **3.4 Remove `pendingToolCalls` from `AgentSession`** — the activity feed replaces it for the live view. Keep `toolCalls` on `ChatMessage` for the collapsed history view.
- [ ] **3.5 Collapse animation** — activity feed shrinks to 0 height when streaming text begins or session goes idle/done. 0.2s `.easeOut`.

**Verify:** Launch app, send a prompt that triggers multiple tools. Confirm: entries appear one by one as tools fire, each shows "in progress" then flips to "completed" with a detail string. Feed collapses when response text starts streaming. Old ThinkingIndicator is gone.

### Phase 4: Interactive Options

- [ ] **4.1 Add `DetectedOption` struct and `detectOptions(in:)` on `AgentSession`** — regex-based scanner. Check qualifying conditions (question line present, 2-6 option lines, not inside code fence). Return nil if no match.
- [ ] **4.2 Add `@Published var optionsDismissed: Bool` to `AgentSession`** — reset to `false` when a new assistant message finalizes, set to `true` when user sends any message.
- [ ] **4.3 Render option buttons in `PlanChatView`** — compute `detectOptions()` on the last assistant message's content. Show below assistant bubble only when `!optionsDismissed`. `LazyVGrid` with ghost-style buttons. Hover brightens background.
- [ ] **4.4 Wire button tap** — sends the option label/text via `state.sendMessage()`. Sets `optionsDismissed = true`.

**Verify:** Send a prompt that elicits options (e.g. "Should I refactor this as a protocol or keep it as a concrete class? Give me options."). Confirm buttons appear. Click one. Confirm it sends the message and buttons disappear.

### Phase 5: Polish & Edge Cases

- [ ] **5.1 Long tool outputs** — ensure `summarizeToolResult` handles very large outputs gracefully (multi-MB file reads). Count lines without storing the full string.
- [ ] **5.2 Rapid tool calls** — if 10+ tools fire in quick succession, the feed should not jitter. Cap visible entries at 4, smooth transitions.
- [ ] **5.3 Rate limit UX** — if throttled, show countdown timer in the activity feed entry (parse `resetsAt` ISO timestamp, display seconds remaining).
- [ ] **5.4 Option detection edge cases** — test against: options inside code blocks (should skip), numbered steps in instructions (should skip), lettered sub-points in a long explanation (should skip), actual choices with a question (should detect).
- [ ] **5.5 Cost display** — verify `total_cost_usd` now reads correctly. Surface it in the token count area if desired.
