# Phase 3: Workspace Layout

```
Risk:     MEDIUM
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  Phase 0
Blocks:   Phase 4 (File Tree), Phase 5 (Git Panel)
```

---

## Objective
Main workspace with toggleable left panel + split terminal panes. The core layout shell.

## Internal Roadmap

### Step 3.1 — WorkspaceState
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Create `Workspace/WorkspaceState.swift` (ObservableObject)
- [ ] Properties:
  - [ ] `projectPath: URL`
  - [ ] `projectName: String`
  - [ ] `gitBranch: String?`
  - [ ] `leftPanelVisible: Bool` (default true)
  - [ ] `activeLeftTab: LeftTab` (.files | .git)
  - [ ] `leftPanelWidth: CGFloat` (default 260, resizable)
- [ ] Verify: state object creates and updates

### Step 3.2 — WorkspaceView (Main Shell)
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Create `Workspace/WorkspaceView.swift`
- [ ] Layout:
  ```
  VStack(spacing: 0) {
    TitleBar
    HStack(spacing: 6) {
      if leftPanelVisible { LeftPanel }
      TerminalPanel
    }.padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
  }
  .background(Theme.appBg)
  ```
- [ ] Title bar: traffic lights + "ProjectName" + branch badge
- [ ] Verify: shell renders with correct bg and spacing

### Step 3.3 — LeftPanelView
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Create `Workspace/LeftPanelView.swift`
- [ ] Glass surface: `.ultraThinMaterial`, 12px radius, no border
- [ ] Tab bar: Files | Git tabs
  - [ ] Active: semibold white text
  - [ ] Inactive: muted text
  - [ ] Yellow dot on Git when changes pending
- [ ] Content area swaps based on active tab (placeholder for now)
- [ ] Verify: panel renders, tabs switch

### Step 3.4 — Panel Toggle + Resize
```
Duration: ~2 hrs
Risk:     MEDIUM — gesture handling
```
- [ ] Cmd+B toggles `leftPanelVisible` with animation
- [ ] Drag handle on right edge of left panel
- [ ] Drag to resize (min 200px, max 400px)
- [ ] Double-click handle → reset to default 260px
- [ ] Verify: toggle animates, resize works, constraints hold

### Step 3.5 — Split Pane System
```
Duration: ~3 hrs
Risk:     MEDIUM — focus management across panes
```
- [ ] Create `Workspace/PaneLayout.swift`
- [ ] Study `Budah/vendor/bonsplit/` for patterns
- [ ] Support horizontal split (Cmd+D) and vertical split (Cmd+Shift+D)
- [ ] Draggable dividers between panes
- [ ] Each pane hosts its own terminal (with tab bar + compose)
- [ ] Cmd+Option+Arrow to navigate between panes
- [ ] Cmd+W closes a pane (if last pane, show empty state)
- [ ] Verify: split, navigate, resize dividers, close panes

---

## Verification Checklist
- [ ] Workspace renders with left panel + terminal area
- [ ] Cmd+B toggles left panel smoothly
- [ ] Left panel resizable via drag handle
- [ ] Files/Git tabs switch (placeholder content for now)
- [ ] Cmd+D creates horizontal split
- [ ] Cmd+Shift+D creates vertical split
- [ ] Cmd+Option+Arrow navigates between panes
- [ ] Cmd+W closes a pane
- [ ] Window title shows "ProjectName — branch"
