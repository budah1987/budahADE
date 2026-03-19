# BudahADE Development Dashboard

```
 ____            _       _        _    ____  _____
| __ ) _   _  __| | __ _| |__    / \  |  _ \| ____|
|  _ \| | | |/ _` |/ _` | '_ \  / _ \ | | | |  _|
| |_) | |_| | (_| | (_| | | | |/ ___ \| |_| | |___
|____/ \__,_|\__,_|\__,_|_| |_/_/   \_\____/|_____|

 Agentic Development Environment
 Native macOS | Swift + SwiftUI | libghostty
```

---

## Overall Progress

```
Phase 0: Scaffold + libghostty  [....................] 0%   << CURRENT
Phase 1: Compose Bar + Tabs     [....................] 0%
Phase 2: Project Picker         [....................] 0%
Phase 3: Workspace Layout       [....................] 0%
Phase 4: File Tree              [....................] 0%
Phase 5: Git Panel              [....................] 0%
Phase 6: Auto-Launch + Polish   [....................] 0%

Total                           [....................] 0%
```

---

## Phase Roadmaps

| Phase | Roadmap | Risk | Depends On | Status |
|-------|---------|------|-----------|--------|
| 0 | [phases/phase-0-scaffold.md](phases/phase-0-scaffold.md) | HIGH | — | Not Started |
| 1 | [phases/phase-1-compose-tabs.md](phases/phase-1-compose-tabs.md) | LOW | Phase 0 | Not Started |
| 2 | [phases/phase-2-project-picker.md](phases/phase-2-project-picker.md) | LOW | Phase 0 | Not Started |
| 3 | [phases/phase-3-workspace.md](phases/phase-3-workspace.md) | MEDIUM | Phase 0 | Not Started |
| 4 | [phases/phase-4-file-tree.md](phases/phase-4-file-tree.md) | LOW | Phase 3 | Not Started |
| 5 | [phases/phase-5-git-panel.md](phases/phase-5-git-panel.md) | MEDIUM | Phase 3 | Not Started |
| 6 | [phases/phase-6-polish.md](phases/phase-6-polish.md) | LOW | All | Not Started |

### Dependency Graph
```
Phase 0 (scaffold) ──┬──> Phase 1 (compose + tabs)
                      ├──> Phase 2 (project picker)
                      └──> Phase 3 (workspace) ──┬──> Phase 4 (file tree)
                                                  └──> Phase 5 (git panel)
                                                           │
                      All phases ─────────────────────────> Phase 6 (polish)
```

### Parallelizable Work
After Phase 0 completes, these can run **in parallel**:
- Phase 1 (compose + tabs) — independent
- Phase 2 (project picker) — independent
- Phase 3 (workspace layout) — independent

After Phase 3 completes:
- Phase 4 (file tree) + Phase 5 (git panel) — in parallel

---

## File Manifest (26 files)

| File | Phase | Status |
|------|-------|--------|
| `BudahADE.xcodeproj` | 0 | [ ] |
| `App/BudahADEApp.swift` | 0 | [ ] |
| `App/AppDelegate.swift` | 0 | [ ] |
| `Shared/Theme.swift` | 0 | [ ] |
| `Terminal/GhosttyAppManager.swift` | 0 | [ ] |
| `Terminal/TerminalSurface.swift` | 0 | [ ] |
| `Terminal/TerminalSurfaceView.swift` | 0 | [ ] |
| `Terminal/TerminalPanelView.swift` | 0 | [ ] |
| `Terminal/GhosttyConfig.swift` | 0 | [ ] |
| `Terminal/ComposePanel.swift` | 1 | [ ] |
| `Terminal/TerminalTabBar.swift` | 1 | [ ] |
| `ProjectPicker/ProjectPickerView.swift` | 2 | [ ] |
| `ProjectPicker/ProjectStore.swift` | 2 | [ ] |
| `Workspace/WorkspaceView.swift` | 3 | [ ] |
| `Workspace/WorkspaceState.swift` | 3 | [ ] |
| `Workspace/LeftPanelView.swift` | 3 | [ ] |
| `Workspace/PaneLayout.swift` | 3 | [ ] |
| `FileTree/FileTreeView.swift` | 4 | [ ] |
| `FileTree/FileTreeNode.swift` | 4 | [ ] |
| `FileTree/FileWatcher.swift` | 4 | [ ] |
| `GitPanel/GitPanelView.swift` | 5 | [ ] |
| `GitPanel/GitRepository.swift` | 5 | [ ] |
| `GitPanel/BranchPicker.swift` | 5 | [ ] |
| `GitPanel/StagingView.swift` | 5 | [ ] |
| `GitPanel/CommitBar.swift` | 5 | [ ] |
| `GitPanel/DiffView.swift` | 5 | [ ] |
| `Shared/KeyboardShortcuts.swift` | 6 | [ ] |

---

## Decision Log

| # | Decision | Why | Date |
|---|----------|-----|------|
| 1 | Native macOS (Swift/SwiftUI), not web/Tauri | Ghostty-quality terminal rendering, native feel | 2026-03-18 |
| 2 | Build from scratch, not fork cmux | Full control over architecture | 2026-03-18 |
| 3 | libghostty for terminal rendering | GPU-accelerated Metal text | 2026-03-18 |
| 4 | Midnight purple palette | Depth between panels, not flat | 2026-03-18 |
| 5 | Liquid glass design language | No borders — surfaces speak through transparency | 2026-03-18 |
| 6 | Model selector: accordion in compose bar | Apple Intelligence pattern | 2026-03-18 |
| 7 | Effort: bar graph (ascending bars) | Signal strength metaphor | 2026-03-18 |
| 8 | Terminal tabs | Parallel agent sessions | 2026-03-18 |
| 9 | Git panel: scope-limited native SwiftUI | No rebase/stash/push — terminal for advanced | 2026-03-18 |
| 10 | `.glassEffect()` for liquid glass | Matches Figma GLASS effect; `.ultraThinMaterial` fallback | 2026-03-18 |

---

## Design References

- **Paper file**: "budahADE" — 7+ artboards (project picker, workspace variants, git panel, model picker, refined workspace)
- **Figma file**: "Dealio V2" — TextInput component at node `335:4414` (GLASS effect, radius 89)
- **workspace.sh**: `~/workspace.sh` — the shell script being replaced
- **Budah repo**: `/Users/amir/Documents/Cursor Projects/Budah` — libghostty reference (read-only)

---

## Open Questions

- [ ] macOS 14 minimum or 15 for better materials?
- [ ] Should project picker remember window position?
- [ ] Draggable tab reordering?
- [ ] Behavior when all tabs closed?

---

## Session Log

| Date | Summary |
|------|---------|
| 2026-03-18 | Initial session. PRD + workspace.sh reviewed. Budah/cmux explored. UI designed in Paper (7 artboards). TextInput extracted from Figma (GLASS effect). Liquid glass design language established. Phase roadmaps written. |
