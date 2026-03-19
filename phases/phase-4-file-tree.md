# Phase 4: Native File Tree

```
Risk:     LOW
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  Phase 3 (Workspace Layout)
Blocks:   Nothing
```

---

## Objective
SwiftUI file browser in the left panel's Files tab. Replaces yazi.

## Internal Roadmap

### Step 4.1 — FileTreeNode Model
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] Create `FileTree/FileTreeNode.swift`
- [ ] Recursive directory tree structure
- [ ] Properties: name, path, isDirectory, isExpanded, children, fileType
- [ ] File type → SF Symbol mapping:
  - [ ] `.swift` → `swift` (orange)
  - [ ] `.ts/.tsx` → `doc.text` (purple)
  - [ ] `.json` → `curlybraces` (yellow)
  - [ ] `.md` → `doc.richtext` (muted)
  - [ ] directories → folder icon (colored by depth)
- [ ] `.gitignore`-aware filtering:
  - [ ] Parse `.gitignore` file
  - [ ] Always hide: `.git/`, `node_modules/`, `.DS_Store`, `build/`, `.next/`
- [ ] Sort: directories first, then alphabetical
- [ ] Verify: model builds correct tree from a test directory

### Step 4.2 — FileWatcher
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Create `FileTree/FileWatcher.swift`
- [ ] Use `DispatchSource.makeFileSystemObjectSource` or FSEvents
- [ ] Watch project root recursively
- [ ] Debounce updates (100ms)
- [ ] Callback to refresh FileTreeNode on changes
- [ ] Verify: create/delete file → tree updates

### Step 4.3 — FileTreeView
```
Duration: ~3 hrs
Risk:     LOW
```
- [ ] Create `FileTree/FileTreeView.swift`
- [ ] SwiftUI `List` with `DisclosureGroup` for directories
- [ ] Row layout: indent + chevron (dirs) + icon + name + status badge
- [ ] No row highlights by default — clean, quiet
- [ ] Single click: expand/collapse directories
- [ ] Yellow "M" badge for git-modified files (read from `git status`)
- [ ] Right-click context menu:
  - [ ] Reveal in Finder
  - [ ] Copy Path
  - [ ] Open in Default Editor
- [ ] Verify: tree navigates correctly, context menu works

---

## Verification Checklist
- [ ] File tree shows project directory contents
- [ ] Directories expand and collapse
- [ ] File icons match file types
- [ ] `.gitignore`'d files are hidden
- [ ] Modified files show yellow "M" indicator
- [ ] Creating/deleting files updates the tree automatically
- [ ] Right-click context menu works
- [ ] Tree integrates into the left panel's Files tab
