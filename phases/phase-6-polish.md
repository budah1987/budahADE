# Phase 6: Auto-Launch + Polish

```
Risk:     LOW
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  All prior phases
Blocks:   Nothing — this is the final phase
```

---

## Objective
Smart behaviors from workspace.sh + quality of life polish.

## Internal Roadmap

### Step 6.1 — Auto-Launch Behaviors
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Auto-`cd` terminal to project directory on open
- [ ] Auto-launch Claude Code in first terminal tab (configurable)
- [ ] `--continue` flag support: resume last Claude session
- [ ] Detect `package.json` with `dev` script → prompt to start dev server
- [ ] Auto-create `CLAUDE.md` for new projects (session continuity instructions)
- [ ] Verify: open project → Claude auto-launches → CLAUDE.md created

### Step 6.2 — Window Chrome
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Window title: "ProjectName — branch"
- [ ] Remember window position and size between launches
- [ ] Full-screen support
- [ ] Verify: title updates on branch switch, position persists

### Step 6.3 — Menu Bar
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] File menu: New Project, Open Project, Close Window
- [ ] Edit menu: standard text editing
- [ ] View menu: Toggle Left Panel (Cmd+B), Toggle Full Screen
- [ ] Terminal menu: New Tab (Cmd+T), Close Tab (Cmd+W), Split Right (Cmd+D), Split Down (Cmd+Shift+D)
- [ ] Navigate menu: Next Pane, Previous Pane, Next Tab, Previous Tab
- [ ] All shortcuts documented in menus
- [ ] Verify: every menu item works

### Step 6.4 — App Icon
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Design icon (or commission)
- [ ] Export at all required sizes (16-1024px)
- [ ] Add to Assets.xcassets
- [ ] Verify: icon shows in dock and Finder

---

## Verification Checklist (End-to-End)
- [ ] Launch BudahADE → see project picker
- [ ] Select project → workspace opens with correct layout
- [ ] Claude Code auto-launches in terminal tab
- [ ] Cmd+B toggles file tree
- [ ] Click Git tab → see branch, files, commit
- [ ] Cmd+D splits terminal
- [ ] Compose bar shows model/effort, sends text
- [ ] Cmd+T opens new terminal tab
- [ ] Window title shows "ProjectName — branch"
- [ ] Menu bar has all shortcuts
- [ ] Close and reopen → same window position, last project remembered
