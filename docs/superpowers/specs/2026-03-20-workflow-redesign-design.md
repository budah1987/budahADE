# BudahADE Workflow Redesign — Design Spec

**Date:** 2026-03-20
**Status:** Approved (brainstormed in Paper with visual mockups)

## Goal

Redesign BudahADE's workflow around three tiers: **Projects → Tasks → Conversations**, with agent role specialization, adaptive spec-driven progress tracking, and a unified hybrid UI that layers complexity on demand.

## Core Principles

1. **Every conversation lives in a task.** No orphan sessions.
2. **Not every task needs a spec.** The UI adapts — spec features appear only when a spec `.md` file exists in the worktree.
3. **Terminal-first.** Ghostty/libghostty stays the core experience. Agent roles are system prompts injected into Claude CLI sessions, not chat wrappers.
4. **Git for dummies.** Branch state, staging, commits visible at a glance without terminal commands.

## Hierarchy

```
Project (repo)
  └─ Task (git worktree + branch)
       └─ Conversation (terminal session with agent role)
```

## 1. Projects

Three entry points in the Project Picker:

- **Create** — New folder in user-chosen directory + `git init`
- **Clone** — Clone from GitHub URL or local path into user-chosen directory
- **Open** — Select existing repo on disk

Recent projects persist in ProjectStore. Opening a project creates a WorkspaceState.

## 2. Tasks

A task = a git worktree + branch + conversations. The "New Task" sheet:

- **Task name** — Free text (e.g. "Rate Limiter")
- **Base branch** — Picker showing all local + remote branches (default: `main`)
- **Branch name** — Auto-generated from task name via `slugify()`, editable
- **Source** — Three modes:
  - New branch from base (default): `git worktree add -b <branch> <path> <base>`
  - Fork existing local branch: pick source branch instead of base
  - (Future) Rebase mid-work: right-click task → "Rebase onto..."

### Task lifecycle

1. Created → worktree exists, first conversation opens
2. Active → work in progress, conversations running
3. Completed → user triggers completion → push + PR creation

### Task rail (left, 160px)

Shows all tasks with:
- Status dot (color = agent activity)
- Task name
- Branch name (monospaced, muted)
- Active task highlighted

Keyboard: Ctrl+1..9 switches tasks.

## 3. Conversations with Agent Roles

A conversation = a terminal tab running Claude CLI with a specific system prompt.

### 7 Default Roles

| Role | Purpose | System Prompt Focus |
|------|---------|-------------------|
| **Developer** | Sr. Developer & Architect | Code, architecture, implementation |
| **Assistant** | Simple tasks | One-off changes, quick fixes |
| **Manager** | Coordinates sub-agents | Delegates work, manages implementation |
| **Designer** | Front-end & UI expert | User outcomes, exceptional interfaces |
| **QA** | Quality assurance | Edge cases, workflow issues, code review |
| **Ideator** | Product thinking | Questions, frameworks, problem discovery |
| **Researcher** | Research expert | Investigation, analysis, synthesis |

### Role Picker

When user clicks `+` to add a conversation, a popover shows available roles. Each role has:
- Icon/indicator
- Name
- One-line description
- Default system prompt (editable per-project in future)

### Technical Implementation

Each role maps to a system prompt file stored at `~/.budahade/agents/<role>.md`. When launching a conversation:

1. Write the system prompt to a temp file in the worktree (`.budahade-agent-<role>.md`)
2. Launch Claude CLI with: `claude --system-prompt .budahade-agent-<role>.md`
3. Terminal tab shows role name + status dot

Users can also choose "Shell" for a plain terminal (no Claude).

### Conversation tab bar

Shows conversation tabs for the active task:
- Role-colored status dot
- Role name (or custom name if renamed)
- Close button on hover

Keyboard: Cmd+1..9 switches conversations within active task.

## 4. Spec-Driven Progress Tracking (Hybrid)

The spec system is **opt-in and automatic**. No configuration needed.

### Detection

BudahADE watches the active task's worktree for files matching: `*-spec.md`, `*-plan.md`, `*.spec.md`. When found, it parses the file for task blocks.

### Spec Format (parsed by BudahADE)

```markdown
## Tasks

- [x] Define rate limit config schema
- [x] Implement sliding window counter
- [ ] Write unit tests ← currently active (determined by git signals)
- [ ] Integration tests
- [ ] Documentation
```

Standard GitHub-flavored markdown checkboxes. Claude already writes specs this way.

### Hybrid Progress Tracking

**Claude-driven:** The agent updates the `.md` file as it works — checking off items, adding notes.

**App-driven overlay:** BudahADE watches git activity and correlates:
- New commits → checks if they relate to unchecked spec items (keyword matching)
- File changes → tracks which spec items have associated modifications
- Progress count → `completed / total` from checkbox parsing

### UI Adaptation

**When NO spec exists:**
- Left panel shows: Changes + Conversations
- Terminal area: Tab bar + terminal. Clean and minimal.
- No spec strip, no Plan/Build toggle.

**When spec IS detected:**
- Left panel gains: Spec section (progress bar, current task, 5/8 count)
- Terminal area gains: Spec strip below tab bar (SPEC 5/8 — "Writing unit tests")
- Tab bar gains: Plan/Build pill toggle on the left

### Plan/Build Mode Toggle

- **Build mode** (default): Terminal visible, spec strip shows compact progress
- **Plan mode**: Terminal replaced by full spec view with rich task cards (descriptions, commit counts, agent status sidebar)

Toggle via: Plan/Build pill in tab bar, "View" link in left panel spec section, or keyboard shortcut (Cmd+P).

## 5. Left Panel — Unified Task Dashboard

The left panel (280px, resizable 200-400px) is a task dashboard with collapsible sections that adapt to context:

### Always visible:
- **Header**: Task name + branch badge
- **Changes**: Unstaged/staged files, commit UI
- **Conversations**: List of active conversations with status

### Visible when spec exists:
- **Spec**: Progress bar, current task label, count, "View" link

### Section ordering:
1. Spec (when present) — most important context
2. Changes — always relevant
3. Conversations — always relevant

## 6. Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+N | New Task |
| Cmd+T | New Conversation (opens role picker) |
| Cmd+W | Close Conversation |
| Cmd+1..9 | Switch conversation within task |
| Ctrl+1..9 | Switch task |
| Cmd+B | Toggle left panel |
| Cmd+P | Toggle Plan/Build mode (when spec exists) |
| Cmd+R | Rename conversation |
| Cmd+Shift+R | Rename task |

## Visual References

Paper file "budahADE", artboards:
- **10. Approach 2 — Command Center**: Task dashboard layout
- **11. Approach 3 — Split Brain**: Plan/Build mode toggle
- **12. Approach 2+3 — Unified**: Hybrid approach (selected design)
- **13. Workflow — Spec vs No Spec**: Dual-path flow diagram
