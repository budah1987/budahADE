# Git Panel Refinement — Design Spec

**Date:** 2026-03-30
**Branch:** git-refinement (from Conversation-Planner)
**Approach:** Clean rebuild of GitSidebarView with decomposed subviews

---

## Overview

Refine the existing git panel sidebar to feel more intuitive, reduce friction, and close the gap with professional git UIs (Cursor's git panel as reference). The sidebar form factor stays — internal sections are redesigned with better visual hierarchy, interactivity, and new capabilities.

## What Changes

1. **Interactive branch header** — click-to-edit branch name with prefix dropdown, changeable merge target, ahead/behind badges
2. **Refined changes list** — cleaner file rows with color-coded status badges, click to open diff modal
3. **Side-by-side diff modal** — full-width sheet with split view, file navigation, per-file staging
4. **AI commit messages** — sparkle button reads staged diff and suggests an editable commit message
5. **Collapsible commit history** — linear timeline with continuous line graph, branch color coding, default closed
6. **Streamlined action bar** — Push, PR, Merge as a horizontal button group

## What Stays

- Sidebar position and width constraints (280–420px with drag handle)
- GitRepository as the core state manager (polling, git shell commands)
- Stage/unstage individual files and bulk operations
- Push, merge, and PR creation functionality
- Error banner for git command failures

---

## 1. Interactive Branch Header

**Component:** `BranchHeaderView`

### Default State
- Branch icon (⑂) + prefix badge (color-coded, e.g. green "feat") + slash + branch name in bold blue
- Below: "→ into [target branch ▾]" with ahead/behind badges
- Ahead badge: green background, e.g. "3 ahead"
- Behind badge: red background, e.g. "2 behind" (shown when target has commits not in current branch)

### Edit Mode (click branch name to activate)
- Prefix becomes a dropdown selector (7 types, see below)
- Branch name becomes a text field with current name pre-filled
- Save button appears — click or press Enter to confirm
- Escape cancels, reverts to original name

### Prefix Dropdown
Floats as an overlay (ZStack/overlay modifier) — does NOT push content below. Types:

| Prefix | Color | Description |
|--------|-------|-------------|
| feat | green (#7ec77e) | feature |
| fix | red (#e06c75) | bug fix |
| ui | copper (#c4956a) | visual |
| refactor | purple (#8b8bff) | restructure |
| chore | gray (#888) | maintenance |
| docs | blue (#61afef) | specs |
| experiment | amber (#d19a66) | prototype |

### Branch Name Validation (applied live while typing)
- Space → hyphen
- Strip: `~ ^ : ? * [ \`
- Collapse `//` → `/` and `..` → `.`
- Trim leading/trailing `/` and `.`
- Strip trailing `.lock`
- No ASCII control characters

### Merge Target Dropdown
- Click target branch name → dropdown of all branches (same overlay behavior)
- Current target has checkmark
- Selecting a new target updates the merge target stored in task/workspace config

### Git Operations
- Rename: `git branch -m old-name new-name`
- Ahead count: `git rev-list --count target..HEAD`
- Behind count: `git rev-list --count HEAD..target`
- Auto-detect existing prefix: if branch contains `/`, split into prefix + name

---

## 2. Changes List

**Component:** `ChangesListView`

### Unstaged Section
- Header: "CHANGES" with count badge (copper)
- File rows: status badge (M/A/D/R/?) + filename + stage button (+)
- Status badge colors: M=green, A=blue, D=red, R=yellow, ?=gray
- "Stage All" button below the list
- Click file row → opens DiffModalView for that file

### Staged Section
- Header: "STAGED" with count badge (blue)
- File rows: checkmark + filename + unstage button (−)
- Subtle blue background tint on staged rows
- "Unstage All" button below the list
- Click file row → opens DiffModalView (showing cached/staged diff)

### Empty States
- Unstaged empty: "No changes yet" in muted text
- Staged empty: section collapses to just the header

---

## 3. Side-by-Side Diff Modal

**Component:** `DiffModalView`
**Presentation:** SwiftUI `.sheet` modifier, dismissible with Escape or ✕ button

### Header Bar
- File status badge (M/A/D) + filename (bold) + parent directory path (muted)
- Right side: +lines / −lines counts + "Stage File" or "Unstage File" button + close (✕)

### Diff Content
- Two-column split: "HEAD (before)" on left, "Working Tree (after)" on right
- Each side has its own line numbers
- Color coding: green background for added lines, red for removed lines, no background for context
- Synchronized scrolling between both panes
- Syntax highlighting reuses existing diff coloring

### Footer Bar
- Left: prev/next file navigation arrows + "2 of 4 files" counter
- Right: Unified / Split toggle (two buttons, active state highlighted)

### Behavior
- Opens for both unstaged files (`git diff`) and staged files (`git diff --cached`)
- Prev/Next arrows step through the changed file list without closing the modal
- Stage/Unstage button in header applies to the currently viewed file
- Clicking a commit in the history section opens this modal showing that commit's changes (`git show <hash>`)

---

## 4. AI Commit Messages

**Component:** Integration into `CommitBarView`

### UI
- Commit message text field (existing, auto-expands to 4 lines)
- Sparkle button (✨) next to the Commit button
- Commit button: blue, primary action

### Behavior
1. User clicks ✨ button
2. Button shows loading state (spinner or pulse animation)
3. System reads the staged diff via `git diff --cached`
4. Sends diff to Claude CLI (existing subprocess integration) with a prompt to generate a concise commit message
5. Response populates the commit message text field
6. User can edit the suggestion freely before committing
7. If no files are staged, button is disabled

### Prompt Template
System prompt instructs Claude to:
- Write a concise commit message (1-2 lines)
- Use conventional commit format if a prefix is detectable from the changes
- Focus on the "why" not the "what"
- Keep under 72 characters for the first line

---

## 5. Collapsible Commit History

**Component:** `CommitHistoryView`

### Section Header
- "▶ HISTORY" (collapsed by default) with total commit count badge
- Click to expand/collapse

### Expanded View — Linear Timeline
- Single continuous vertical line connecting all commit dots
- Line starts at the center of the HEAD dot (no bleed above)
- Line ends at the center of the last visible commit dot (no bleed below)
- Line color: blue (#4a9eff) for current branch commits, transitions to copper (#c4956a) at the fork point

### Commit Rows
- Dot on the line + commit message + hash (7 chars) + relative timestamp
- HEAD commit: larger dot (10px) with glow, plus HEAD badge and branch name badge
- Regular commits: smaller dot (8px)
- Base branch commits (below fork point): faded to 60% opacity, copper dots
- origin/main badge on the relevant commit

### Interactions
- Click a commit → opens DiffModalView showing that commit's file changes
- Hover a commit → tooltip with full commit message, author, full hash

### Data
- Loads last 20 commits via `git log --oneline -20`
- Fork point detected via `git merge-base HEAD target-branch`
- "Load more" button at bottom if more commits exist

---

## 6. Action Bar

**Component:** Bottom of `GitSidebarView`

### Layout
- Horizontal row of 3 buttons: Push (primary, copper), PR (secondary), Merge (secondary)
- Push button shows dynamic state:
  - Default: "Push"
  - With ahead count: "Push (3)"
  - Loading: "Pushing..."
  - Success: "Pushed ✓" (briefly, then revert)
- PR button: opens GitHub compare URL in browser (existing behavior)
- Merge button: merges target into current branch (existing behavior)

---

## Component Architecture

Clean rebuild with focused subviews:

```
GitSidebarView (container)
├── BranchHeaderView
│   ├── BranchNameEditor (inline edit + validation)
│   ├── PrefixDropdown (overlay)
│   └── MergeTargetPicker (overlay)
├── ChangesListView
│   ├── FileRow (reusable for both unstaged/staged)
│   └── BulkActions (Stage All / Unstage All)
├── CommitBarView
│   ├── CommitMessageField
│   └── AICommitButton
├── CommitHistoryView
│   ├── CommitTimelineView (the line + dots)
│   └── CommitRow
└── ActionBar
    ├── PushButton
    ├── PRButton
    └── MergeButton

DiffModalView (presented as .sheet)
├── DiffHeaderBar
├── SplitDiffView / UnifiedDiffView (togglable)
└── DiffFooterBar
```

## State Management

- `GitRepository` remains the single source of truth for git state
- Add new published properties:
  - `mergeTarget: String` — the branch to merge into (persisted per task/workspace)
  - `behindCount: Int` — commits behind target
  - `forkPointHash: String?` — merge-base between HEAD and target
- New `AICommitService` class handles diff→Claude→message pipeline
- Branch rename validation is a pure function, no state needed

## Testing Strategy

- Unit tests for branch name validation (all constraint rules)
- Unit tests for prefix detection from existing branch names
- Unit tests for fork point detection and commit categorization
- UI tests for edit mode transitions (default → editing → saved)
- Integration test for AI commit message flow (mock Claude response)
