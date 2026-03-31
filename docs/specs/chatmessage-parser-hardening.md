# Spec: ChatMessage.swift JSON Parser Hardening

**Status:** Spec only — do not execute without separate approval
**File:** `BudahADE/Agent/ChatMessage.swift:234–404`
**Priority:** High — this parser is on the critical path for every plan conversation message

---

## Current State

The parser decodes Claude CLI `--output-format stream-json` output. It first decodes the entire JSON line into `[String: AnyCodable]`, then navigates the dictionary with string key subscripts and optional chaining (`.stringValue`, `.objectValue`, `.arrayValue`, etc.).

### String Keys Accessed and Their Expected Types

**Top-level (all events):**
| Key | Expected Type | Used As |
|-----|--------------|---------|
| `"type"` | String | Event discriminator |

**`"system"` event:**
| Key | Expected Type | Default if missing |
|-----|--------------|-------------------|
| `"subtype"` | String? | nil — determines hook vs init |
| `"hook_id"` | String | `""` |
| `"hook_name"` | String | `""` |
| `"hook_event"` | String | `""` |
| `"session_id"` | String | `""` |
| `"tools"` | [String]? | nil |
| `"model"` | String? | nil |
| `"slash_commands"` | [String]? | nil |

**`"assistant"` event (nested 2–3 levels deep):**
| Key Path | Expected Type | Default if missing |
|----------|--------------|-------------------|
| `message` | Object | → throws `.invalidData` |
| `message.content` | Array | → no tool calls, no text |
| `message.content[].type` | String | → block skipped |
| `message.content[].text` | String | → text block skipped |
| `message.content[].id` | String | → tool_use block skipped |
| `message.content[].name` | String | → tool_use block skipped |
| `message.content[].input` | Object | → empty dict |
| `message.content[].thinking` | String | → thinking skipped |
| `message.usage.input_tokens` | Int | `0` |
| `message.usage.output_tokens` | Int | `0` |
| `message.role` | String | `"assistant"` |
| `message.model` | String? | nil |

**`"user"` event (tool results):**
| Key | Expected Type | Behavior |
|-----|--------------|---------|
| `content` | Array | → returns `.unknown` if no tool_result found |
| `content[].type` | String | must equal `"tool_result"` |
| `content[].tool_use_id` | String | `""` |
| `content[].is_error` | Bool | `false` |
| `content[].content` | **String OR Array** | polymorphic — handled inline |

**`"content_block_delta"` event:**
| Key | Expected Type | Default |
|-----|--------------|---------|
| `delta` | Object | → throws `.invalidData` |
| `delta.type` | String | `""` |
| `delta.thinking` | String | `""` |
| `delta.text` | String | `""` |

**`"rate_limit_event"`:**
| Key | Expected Type | Default |
|-----|--------------|---------|
| `status` | String | `""` |
| `resets_at` | String? | nil |
| `rate_limit_type` | String? | nil |

**`"result"` event:**
| Key | Expected Type | Notes |
|-----|--------------|-------|
| `total_cost_usd` OR `cost_usd` | Double | dual-key fallback pattern |
| `duration_ms` | Int? | nil |
| `duration_api_ms` | Int? | nil |
| `session_id` | String? | nil |
| `num_turns` | Int? | nil |
| `stop_reason` | String? | nil |
| `usage.input_tokens` | Int | `0` |
| `usage.output_tokens` | Int | `0` |

---

## What Breaks If the Schema Changes

The current implementation fails in the following ways when the Claude CLI output format changes:

| Scenario | Current behavior | Impact |
|----------|-----------------|--------|
| Field renamed (e.g., `session_id` → `sessionId`) | Returns `""` default silently | Session not resumed on next launch |
| Field type changed (e.g., `is_error` → String `"true"`) | `.boolValue` returns nil, defaults to `false` | Tool errors shown as successes |
| New content block type added | Block silently skipped | Features like extended thinking or new tool types silently dropped |
| `message.content` becomes an object instead of array | No tool calls or text extracted | Blank assistant messages in UI |
| `cost_usd` key removed without `total_cost_usd` | Cost shows as `0.0` | Incorrect cost tracking |
| `usage` block moves out of `message` | Token counts show as `0/0` | Usage stats broken |

**Most dangerous:** the `"assistant"` event has 3 levels of `?.objectValue`/`?.arrayValue` chaining. Any structural change mid-chain returns empty/default without any log entry. A schema change here produces blank messages in the UI with no indication of failure.

---

## Proposed Struct Definitions

```swift
// MARK: - Top-level event envelope
struct RawStreamEvent: Decodable {
    let type: String
}

// MARK: - "system" event
struct RawSystemEvent: Decodable {
    let subtype: String?
    let hookId: String?
    let hookName: String?
    let hookEvent: String?
    let sessionId: String?
    let tools: [String]?
    let model: String?
    let slashCommands: [String]?

    enum CodingKeys: String, CodingKey {
        case subtype, model
        case hookId = "hook_id"
        case hookName = "hook_name"
        case hookEvent = "hook_event"
        case sessionId = "session_id"
        case tools
        case slashCommands = "slash_commands"
    }
}

// MARK: - "assistant" event content blocks (polymorphic)
enum RawContentBlock: Decodable {
    case text(String)
    case toolUse(id: String, name: String, input: AnyCodable)
    case thinking(String)
    case unknown

    enum CodingKeys: String, CodingKey { case type, text, id, name, input, thinking }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            let id = try c.decode(String.self, forKey: .id)
            let name = try c.decode(String.self, forKey: .name)
            let input = try c.decodeIfPresent(AnyCodable.self, forKey: .input) ?? AnyCodable(value: [:] as [String: String])
            self = .toolUse(id: id, name: name, input: input)
        case "thinking":
            self = .thinking(try c.decodeIfPresent(String.self, forKey: .thinking) ?? "")
        default:
            self = .unknown
        }
    }
}

// MARK: - "user" event tool result content (polymorphic)
enum RawToolResultContent: Decodable {
    case text(String)
    case blocks([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else if let blocks = try? container.decode([[String: AnyCodable]].self) {
            self = .blocks(blocks.compactMap { $0["text"]?.stringValue })
        } else {
            self = .text("")
        }
    }

    var stringValue: String {
        switch self {
        case .text(let s): return s
        case .blocks(let arr): return arr.joined(separator: "\n")
        }
    }
}
```

---

## Migration Path

**This can be done incrementally, case by case.** The outer decoder (`[String: AnyCodable]`) stays in place until all cases are converted.

### Phase 1 — Leaf types (no risk)
- Add `Decodable` conformance to `SystemInfo`, `HookEvent`, `RateLimitInfo`, `ResultInfo`
- These are already Swift structs. Add `CodingKeys` and `init(from:)` or synthesized conformance
- Replace the AnyCodable navigation in the `"system"`, `"rate_limit_event"`, and `"result"` switch cases
- Each case becomes a `try decoder.decode(RawXxxEvent.self, from: data)` with a typed struct

### Phase 2 — Content blocks (medium risk — covers `"content_block_delta"` and thinking)
- Add `RawContentBlock` enum with Decodable
- Replace inline block-type checks in the `"assistant"` case

### Phase 3 — Tool result polymorphism (highest risk — `"user"` event)
- Add `RawToolResultContent` to handle String vs Array content
- Replace the dual `if let str / else if let arr` branch

### Phase 4 — Remove AnyCodable top-level decode
- Replace the initial `decoder.decode([String: AnyCodable].self, from: data)` with a two-pass decode:
  1. Decode just `RawStreamEvent` to get `type`
  2. Re-decode into the specific typed struct for that case

**All-or-nothing risk:** Phase 4 only. Phases 1–3 can be shipped independently. The AnyCodable fallback stays in place until Phase 4 is complete, so partial migration is safe.

---

## Recommendation

Start with Phase 1 (leaf types). It's zero-risk and covers the three simplest cases. Phase 2–3 require test coverage of the stream parser before execution — specifically, golden-file tests with real Claude CLI output samples for each event type.

Phase 4 should not be executed until the full event type inventory is confirmed against the current CLI version.
