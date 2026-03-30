# Plan Mode V2 — "The Planning Loop"

**Date:** 2026-03-30
**Status:** Design approved, pending implementation plan

## Problem

Amir uses Claude Desktop (CD) for planning/ideation and Claude Code (CC) for building. Once building starts, the planning context dies — CD doesn't know about decisions made in CC, specs drift, and returning to planning mid-build means starting from scratch. BudahADE's Plan mode should eliminate CD from the workflow entirely by providing a planning environment that stays alive and aware throughout the entire development lifecycle.

## Design

### 1. Entry & Default State

Plan mode opens with a **role selection modal** — the same modal used when creating a new tab. No plain empty state. The user must choose a role to begin.

- Modal shows all available roles with numbered shortcuts (1-5+) for keyboard-only selection
- Same modal appears when:
  - Plan mode opens with no existing conversations
  - User creates a new tab via "+" button or keyboard shortcut
- After role selection, a new conversation tab opens with that role's system prompt and configuration

### 2. Conversation Roles

Roles are specialized lenses that shape the conversation's system prompt, default model, and allowed tools.

**Built-in roles:**

| Role | Purpose | Tools | Default Model |
|------|---------|-------|---------------|
| **Researcher** | Deep dives, web search, API docs, codebase patterns | WebSearch, WebFetch, Read, Glob, Grep | Sonnet |
| **Ideator** | Strategic thinking, trade-off analysis, approach exploration | Read, Glob, Grep | Opus |
| **Designer** | UI/UX decisions, component structure, interaction patterns | Read, Glob, Grep | Opus |
| **Developer** | Architecture, feasibility, code-level design | Read, Glob, Grep, Edit, Write, Bash | Sonnet |
| **Spec Author** | Synthesizes findings from other tabs into a unified spec | Read, Glob, Grep, Write | Opus |

**Role characteristics:**
- Each role produces **insights through its lens** — not specs. Research findings, design opinions, architectural proposals, feasibility assessments.
- Only the **Spec Author** produces the actual spec document.
- Each tab displays its role as a badge/label in the tab bar for at-a-glance identification.

**Configuration:**
- Ships with hardcoded defaults (extending existing `AgentMode.swift` pattern)
- Future: user-configurable via settings (role name, system prompt definition, tools, default model)

### 3. Cross-Tab Context Awareness

Every conversation knows what's happening in sibling tabs. When a new tab opens, it receives the full conversation history from all existing tabs as context.

**Implementation:**
- Each tab's conversation auto-persists to `.budahade/conversations/{tabId}.json` as messages accumulate (debounced writes)
- When a new tab launches, `AgentPrompts` reads sibling conversation files and generates a **"Sibling Context" section** in the system prompt file
- Sibling histories are labeled by role: `"From Researcher (Tab 2): ..."`, `"From Ideator (Tab 3): ..."`
- Context reflects sibling state at **tab creation time**, not live-updating mid-conversation

**Performance strategy:**
- Start with **full conversation injection** into the system prompt
- If performance becomes a problem, the known fallback is: auto-summaries for baseline awareness + explicit "Send to" button for targeted heavy context
- The "Send to" mechanism is designed but deferred until testing reveals the need

### 4. Spec Assembly & Action Buttons

Conductor-style action buttons positioned **above the text input** on each tab:

| Button | Action | When to use |
|--------|--------|-------------|
| **Approve** | Finalizes output and writes spec to disk | Spec Author tab has a complete spec ready to commit |
| **Hand off** | Sends output to another tab as weighted context | Role tab produced findings the Spec Author should incorporate |
| **Edit** | Opens conversational editing flow ("What would you like to change?") | Refining any output before Approve or Hand off |

**Spec Author workflow:**

The Spec Author follows a **section-by-section collaborative process** — presenting each part of the spec individually for user review before moving to the next. This mirrors how a human architect would walk a stakeholder through a design:

1. Open a Spec Author tab (arrives with full sibling context)
2. Direct the synthesis: "Weight the Researcher's API findings, go with Ideator's option B, ignore the dark mode suggestion"
3. Spec Author presents the spec **one section at a time** — e.g., "Here's the architecture section. Does this look right?"
4. User approves, requests changes, or asks to expand — per section
5. Once all sections are approved, the Spec Author assembles the full document
6. Final review of the complete spec
7. **Approve** → spec written to disk, ready for Build mode

This incremental validation prevents the "big reveal" problem where a full spec draft misses the mark and requires wholesale revision. Each section is a checkpoint.

**Hand off flow:**
- Role tab produces valuable output → user clicks **Hand off** → selects target tab (typically Spec Author) → output injected into target as weighted context with source attribution

### 5. The Plan↔Build Bridge

**Plan → Build:**
- On Approve, the spec file is written to disk (`.budahade/spec.md` or task's spec path)
- Builder agents launch with the spec embedded in their system prompt (existing `builderPrompt()` pattern)
- Planning conversation histories persist in `.budahade/conversations/` — they don't disappear

**Build → Plan (mid-build return):**
- Plan tabs are still there, conversations intact
- A new plan tab gets **build context injected**: git diffs since build started, completed spec items, agent output from `.budahade/agent-output/`
- User can reason about what happened, revise the spec, and push changes back to Build

**Spec divergence awareness:**
- On return to Plan mode, context injection includes a delta: completed spec items, skipped items, changes not in the spec
- User decides: update spec to match reality, or flag for correction in Build

### 6. Plan Versioning

Multiple spec versions can coexist within a task, supporting both evolutionary iteration and parallel exploration.

**Version management:**
- Each **Approve** saves a numbered version: `spec-v1.md`, `spec-v2.md`, etc. in `.budahade/specs/`
- The latest approved version is the active spec — the one Build mode reads
- Previous versions retained for reference

**Parallel approaches:**
- Two Spec Author tabs can draft different approaches simultaneously
- Approving one doesn't delete the other — it remains as a draft
- If the chosen approach fails during Build, return to Plan and Approve the alternative

**Version context:**
- Spec Author knows which versions exist and what changed between them
- User can request cross-version operations: "go back to v1's auth approach but keep v2's data model"

### 7. Task Lifecycle & Archive

**On task completion, everything persists:**
- Plan conversations in `.budahade/conversations/`
- Spec versions in `.budahade/specs/`
- Build history (agent output, build status, git diffs) in `.budahade/agent-output/`
- Task state snapshot in `.budahade/sessions/`

**Task Archive:**
- **"Task Archive"** button in the side panel, positioned above "+ New Task"
- Completed tasks move to the archive, keeping the active task list clean
- Archive supports:
  - **Decision archaeology**: Browse plan tabs, read spec versions, trace the reasoning chain
  - **Resume/extend**: Reopen a task, switch to Plan mode, start new tabs with full prior context
  - **Template/reference**: Reference a completed task's spec as a starting point for new work

## Data Model

### File Structure
```
.budahade/
├── conversations/
│   ├── {tabId-1}.json          # Persisted chat messages per tab
│   ├── {tabId-2}.json
│   └── ...
├── specs/
│   ├── spec-v1.md              # Version history
│   ├── spec-v2.md
│   └── ...
├── spec.md                     # Active spec (latest approved)
├── chat-{sessionId}-prompt.md  # Generated system prompts
├── agent-output/
│   └── {panelId}.md            # Structured findings from build agents
├── build-status.json           # Builder execution status
└── sessions/
    └── tabs.json               # Tab/task state snapshots
```

### Role Definition (initial hardcoded, future configurable)
```swift
struct PlanRole {
    let name: String            // "Researcher", "Ideator", etc.
    let systemPrompt: String    // Role-specific instructions
    let allowedTools: [String]  // Tool restrictions
    let defaultModel: Model     // Haiku, Sonnet, Opus
    let maxTurns: Int?          // Optional turn limit
    let keyboardShortcut: Int   // 1-5 for modal selection
}
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Role requirement | Must choose a role to start | Roles provide focus; same modal for empty state and new tabs keeps UX consistent |
| Context injection | Full sibling history via system prompt | Simpler mental model; optimize to summaries + "Send to" only if testing reveals performance issues |
| Spec assembly | Spec Author role + action buttons | Hybrid approach: AI drafts, user directs — balances automation with control |
| Versioning | Numbered files in `.budahade/specs/` | Lightweight, git-friendly, no database needed |
| Task archive | Dedicated button in side panel | Keeps active list clean while preserving full history one click away |
| Role config | Hardcoded defaults, future settings UI | Ship fast with sensible defaults, add customization later |

## Open Questions

- **"Send to" button**: Deferred. Will implement if full context injection proves too slow in practice.
- **Archive UI**: "Task Archive" button confirmed. Internal browsing/search UI to be designed when implementing.
- **Role customization settings UI**: Deferred to future iteration.
- **Build mode orchestrator pattern**: The multi-agent builder with verified parity (from build orchestration vision) is a separate design effort that builds on this spec's Plan↔Build bridge.
