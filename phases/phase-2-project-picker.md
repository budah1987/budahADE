# Phase 2: Project Picker

```
Risk:     LOW
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  Phase 0
Blocks:   Nothing
```

---

## Objective
Welcome screen with project cards, search, and new project creation. Replaces workspace.sh's arrow-key menu.

## Internal Roadmap

### Step 2.1 — ProjectStore
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Create `ProjectPicker/ProjectStore.swift`
- [ ] Read projects dir from `~/.config/workspace/config` (workspace.sh compatibility)
- [ ] List subdirectories as projects
- [ ] For each project: name, path, last-modified date, git branch (if `.git` exists)
- [ ] Track last-used project in `~/.config/workspace/last_project`
- [ ] Sort: last-used first, then by last-modified
- [ ] Verify: prints correct project list to console

### Step 2.2 — ProjectPickerView
```
Duration: ~3 hrs
Risk:     LOW
```
- [ ] Create `ProjectPicker/ProjectPickerView.swift`
- [ ] Logo: "budah**ADE**" (ADE in terracotta)
- [ ] Subtitle: "Agentic Development Environment"
- [ ] Search bar: glass surface, magnifying glass icon, placeholder text
- [ ] "RECENT PROJECTS" section label (SF Pro 11px, uppercase, muted)
- [ ] 3-column card grid:
  - [ ] Card: glass surface, project name (SF Pro 15px semibold), path (12px muted)
  - [ ] Branch badge (SF Mono 11px, colored per branch type)
  - [ ] Last-opened time (11px muted)
  - [ ] Hover: terracotta border
- [ ] "New Project" card: dashed border, + icon
- [ ] Verify: cards render, search filters, hover works

### Step 2.3 — Window Management
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Show picker on app launch (default behavior)
- [ ] CLI arg: `BudahADE Ghost` → skip picker, open workspace directly
- [ ] On project select → animate transition to workspace view
- [ ] Cmd+Shift+O → re-open picker from workspace
- [ ] Verify: launch → pick → workspace → Cmd+Shift+O → picker

---

## Verification Checklist
- [ ] Launch app → see project picker
- [ ] Projects from `~/.config/workspace/config` directory appear
- [ ] Search filters projects in real-time
- [ ] Click project → workspace opens with terminal in project dir
- [ ] "New Project" creates directory and opens workspace
- [ ] Last-used project is pre-selected on next launch
- [ ] Cmd+Shift+O returns to picker from workspace
