# Phase 5: Native Git Panel

```
Risk:     MEDIUM
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  Phase 3 (Workspace Layout)
Blocks:   Nothing
```

---

## Objective
Native SwiftUI git UI in the left panel's Git tab. Replaces lazygit.

## Scope Discipline
**In scope**: status, stage/unstage, commit, branch switch, basic diff view.
**Out of scope**: merge conflicts, interactive rebase, stash, push/pull, remote management. Use terminal for these.

## Internal Roadmap

### Step 5.1 — GitRepository (Backend)
```
Duration: ~3 hrs
Risk:     LOW
```
- [ ] Create `GitPanel/GitRepository.swift`
- [ ] Shell out to `git` via `Process`
- [ ] Commands:
  - [ ] `git status --porcelain=v2` → parse file statuses
  - [ ] `git branch -a --sort=-committerdate` → branch list
  - [ ] `git log --oneline -10` → recent commits
  - [ ] `git diff [--cached] -- <file>` → file diffs
  - [ ] `git add <file>` → stage
  - [ ] `git reset HEAD <file>` → unstage
  - [ ] `git commit -m "message"` → commit
  - [ ] `git checkout <branch>` → switch branch
- [ ] Poll every 2-3 seconds for status updates
- [ ] Verify: all commands return correct data

### Step 5.2 — BranchPicker
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Create `GitPanel/BranchPicker.swift`
- [ ] Display current branch name with git icon
- [ ] Dropdown chevron → shows branch list
- [ ] Click branch → `git checkout`
- [ ] "New Branch" option at bottom
- [ ] Verify: switch branches, create new branch

### Step 5.3 — StagingView
```
Duration: ~3 hrs
Risk:     LOW
```
- [ ] Create `GitPanel/StagingView.swift`
- [ ] Summary stats: large number + "files changed" + `+N -N` in green/red
- [ ] **STAGED** section:
  - [ ] Green checkbox (filled) per file
  - [ ] File name + status badge (M/A/D)
  - [ ] "Unstage All" action
  - [ ] Click file → show diff
- [ ] **CHANGES** section:
  - [ ] Empty checkbox per file
  - [ ] File name + status badge
  - [ ] "Stage All" action
  - [ ] Click file → show diff
- [ ] Click checkbox → stage/unstage individual file
- [ ] Verify: stage/unstage files, see correct counts

### Step 5.4 — CommitBar
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Create `GitPanel/CommitBar.swift`
- [ ] Text field: commit message, glass surface
- [ ] Button: "Commit N Files" in terracotta
- [ ] Disabled when no staged files or empty message
- [ ] On commit → run `git commit`, clear field, refresh status
- [ ] Verify: type message, commit, see in recent commits

### Step 5.5 — DiffView
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Create `GitPanel/DiffView.swift`
- [ ] Unified diff display
- [ ] Green background for additions, red for deletions
- [ ] Line numbers on both sides
- [ ] Collapse unchanged regions (show "... N lines hidden")
- [ ] Shown inline when a file is selected in staging view
- [ ] Verify: click file → see correct diff

### Step 5.6 — GitPanelView (Composition)
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Create `GitPanel/GitPanelView.swift`
- [ ] Compose: BranchPicker → StagingView → CommitBar
- [ ] Recent commits section at bottom (hash + message)
- [ ] DiffView appears inline when file selected
- [ ] Integrate into left panel's Git tab
- [ ] Verify: full git workflow works end-to-end

---

## Verification Checklist
- [ ] Git panel shows in left panel's Git tab
- [ ] Branch picker shows current branch and allows switching
- [ ] Modified files appear in Changes section
- [ ] Stage individual files with checkbox click
- [ ] "Stage All" stages everything
- [ ] Staged files appear in Staged section with green checkbox
- [ ] Unstage works (click checkbox or "Unstage All")
- [ ] Commit bar enables when staged files + message exist
- [ ] Commit creates a real git commit
- [ ] Recent commits show latest history
- [ ] Clicking a file shows its diff
- [ ] Status auto-refreshes every 2-3 seconds
