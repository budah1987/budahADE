# Geist Font Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SF Pro with Geist as the app-wide UI font, establishing a two-font system (Geist for UI, Menlo for terminal content).

**Architecture:** Bundle 4 Geist TTF weights into the app via `ATSApplicationFontsPath`. Rework `Theme.swift` typography to resolve Geist by name. Rename `mono()` → `code()` for terminal content using Menlo. Migrate ~94 call sites across 23 files.

**Tech Stack:** SwiftUI, AppKit (NSFont), XcodeGen, CoreText font registration

**Spec:** `docs/superpowers/specs/2026-03-30-geist-font-migration.md`

---

### Task 1: Bundle Geist Font Files

**Files:**
- Create: `BudahADE/Resources/Fonts/Geist-Regular.ttf` (copy)
- Create: `BudahADE/Resources/Fonts/Geist-Medium.ttf` (copy)
- Create: `BudahADE/Resources/Fonts/Geist-Bold.ttf` (copy)
- Create: `BudahADE/Resources/Fonts/Geist-Black.ttf` (copy)
- Modify: `BudahADE/Info.plist`
- Modify: `project.yml`

- [ ] **Step 1: Create Resources/Fonts directory and copy TTFs**

```bash
mkdir -p BudahADE/Resources/Fonts
cp ~/node_modules/geist/dist/fonts/geist-sans/Geist-Regular.ttf BudahADE/Resources/Fonts/
cp ~/node_modules/geist/dist/fonts/geist-sans/Geist-Medium.ttf BudahADE/Resources/Fonts/
cp ~/node_modules/geist/dist/fonts/geist-sans/Geist-Bold.ttf BudahADE/Resources/Fonts/
cp ~/node_modules/geist/dist/fonts/geist-sans/Geist-Black.ttf BudahADE/Resources/Fonts/
```

- [ ] **Step 2: Add ATSApplicationFontsPath to Info.plist**

Add before the closing `</dict>`:

```xml
<key>ATSApplicationFontsPath</key>
<string>Resources/Fonts</string>
```

- [ ] **Step 3: Add font resources to project.yml**

Under `BudahADE` target, add a `resources` key alongside `sources`:

```yaml
    resources:
      - path: BudahADE/Resources/Fonts
        buildPhase: resources
```

- [ ] **Step 4: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Resources/Fonts/ BudahADE/Info.plist project.yml
git commit -m "feat: bundle Geist font (Regular, Medium, Bold, Black)"
```

---

### Task 2: Rework Theme.swift Typography

**Files:**
- Modify: `BudahADE/Shared/Theme.swift:73-105`

- [ ] **Step 1: Replace the entire Typography section in Theme.swift**

Replace lines 72–105 (the `// MARK: - Typography` section through `uiFont`) with:

```swift
    // MARK: - Typography (Geist for UI, Menlo for terminal content)

    private static let geistName = "Geist"

    static func display(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Black", size: size)
    }

    static func headline(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Bold", size: size)
    }

    static func label(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Medium", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Regular", size: size)
    }

    static func caption(_ size: CGFloat) -> Font {
        .custom("\(geistName)-Regular", size: size)
    }

    /// Terminal content only — diffs, code blocks, file preview
    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Menlo", size: size).weight(weight)
    }

    /// NSFont for AppKit contexts — canvas text measurement, attributed strings
    static func geistFont(size: CGFloat, name: String = "Geist-Regular") -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// NSFont for terminal content in AppKit contexts
    static func codeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
```

This removes `mono()`, `monoFont()`, and `uiFont()`.

- [ ] **Step 2: Build to confirm Theme compiles (expect errors from callers)**

```bash
xcodebuild build -scheme BudahADE 2>&1 | grep "error:" | head -20
```

Expected: Many errors like `Type 'Theme' has no member 'mono'` — these get fixed in Tasks 3–6.

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Shared/Theme.swift
git commit -m "feat: rework Theme typography — Geist for UI, Menlo code() for terminal"
```

---

### Task 3: Migrate Git Panel (32 call sites)

**Files:**
- Modify: `BudahADE/GitPanel/BranchHeaderView.swift` (19 sites)
- Modify: `BudahADE/GitPanel/BranchPicker.swift` (1 site)
- Modify: `BudahADE/GitPanel/GitPanelView.swift` (1 site)
- Modify: `BudahADE/GitPanel/CommitBarView.swift` (1 site)
- Modify: `BudahADE/GitPanel/CommitHistoryView.swift` (3 sites)
- Modify: `BudahADE/GitPanel/ChangesListView.swift` (2 mono + 1 inline monospaced)
- Modify: `BudahADE/GitPanel/StagingView.swift` (1 mono + 1 inline monospaced)
- Modify: `BudahADE/GitPanel/DiffModalView.swift` (8 mono + 1 inline monospaced)
- Modify: `BudahADE/GitPanel/DiffView.swift` (1 inline monospaced)

- [ ] **Step 1: Migrate BranchHeaderView.swift — all 19 `Theme.mono` → Geist tiers**

All branch names, inputs, status badges, and search fields become Geist:

| Line | Old | New |
|------|-----|-----|
| 51 | `Theme.mono(11)` | `Theme.body(11)` |
| 57 | `Theme.mono(12, weight: .semibold)` | `Theme.label(12)` |
| 88 | `Theme.mono(9)` | `Theme.caption(9)` |
| 98 | `Theme.mono(9)` | `Theme.caption(9)` |
| 121 | `Theme.mono(11)` | `Theme.body(11)` |
| 143 | `Theme.mono(11)` | `Theme.body(11)` |
| 149 | `Theme.mono(11)` | `Theme.body(11)` |
| 204 | `Theme.mono(9)` | `Theme.caption(9)` |
| 227 | `Theme.mono(11)` | `Theme.body(11)` |
| 249 | `Theme.mono(11)` | `Theme.body(11)` |
| 284 | `Theme.mono(11)` | `Theme.body(11)` |
| 319 | `Theme.mono(11)` | `Theme.body(11)` |
| 344 | `Theme.mono(11)` | `Theme.body(11)` |
| 366 | `Theme.mono(11)` | `Theme.body(11)` |
| 388 | `Theme.mono(10, weight: .medium)` | `Theme.label(10)` |

- [ ] **Step 2: Migrate BranchPicker.swift**

| Line | Old | New |
|------|-----|-----|
| 27 | `Theme.mono(12, weight: .medium)` | `Theme.label(12)` |

- [ ] **Step 3: Migrate GitPanelView.swift**

| Line | Old | New |
|------|-----|-----|
| 52 | `Theme.mono(11, weight: .medium)` | `Theme.label(11)` |

- [ ] **Step 4: Migrate CommitBarView.swift**

| Line | Old | New |
|------|-----|-----|
| 16 | `Theme.mono(11)` | `Theme.body(11)` |

- [ ] **Step 5: Migrate CommitHistoryView.swift**

| Line | Old | New |
|------|-----|-----|
| 31 | `Theme.mono(9)` | `Theme.caption(9)` |
| 130 | `Theme.mono(9)` | `Theme.caption(9)` |
| 163 | `Theme.mono(8)` | `Theme.caption(8)` |

- [ ] **Step 6: Migrate ChangesListView.swift**

| Line | Old | New |
|------|-----|-----|
| 87 | `Theme.mono(9)` | `Theme.caption(9)` |
| 106 | `Theme.mono(11)` | `Theme.body(11)` |
| 136 | `.system(size: 10, weight: .bold, design: .monospaced)` | `Theme.label(10)` |

- [ ] **Step 7: Migrate StagingView.swift**

| Line | Old | New |
|------|-----|-----|
| 67 | `Theme.mono(10)` | `Theme.caption(10)` |
| 142 | `.system(size: 10, weight: .bold, design: .monospaced)` | `Theme.label(10)` |

- [ ] **Step 8: Migrate DiffModalView.swift — split Geist / Menlo**

App chrome (file names, stats, metadata) → Geist:

| Line | Old | New |
|------|-----|-----|
| 45 | `Theme.mono(13, weight: .semibold)` | `Theme.label(13)` |
| 49 | `Theme.mono(11)` | `Theme.caption(11)` |
| 61 | `Theme.mono(11)` | `Theme.body(11)` |
| 64 | `Theme.mono(11)` | `Theme.body(11)` |
| 170 | `Theme.mono(10)` | `Theme.caption(10)` |
| 176 | `Theme.mono(11)` | `Theme.body(11)` |
| 301 | `Theme.mono(10)` | `Theme.caption(10)` |
| 307 | `Theme.mono(11)` | `Theme.body(11)` |
| 318 | `.system(size: 10, weight: .bold, design: .monospaced)` | `Theme.label(10)` |

Diff line content (terminal) → Menlo:

| Function `unifiedDiffView` line | Old | New |
|------|-----|-----|
| 170 (inside unifiedDiffView) | `Theme.mono(10)` | `Theme.code(10)` |
| 176 (inside unifiedDiffView) | `Theme.mono(11)` | `Theme.code(11)` |

**Important disambiguation:** Lines 170 and 176 appear twice in DiffModalView — once in the file list section (app chrome) and once in `unifiedDiffView` (terminal content). The file list instances at lines 170/176 → Geist. The `diffLineView` instances at lines 301/307 → Menlo. Check the function context for each.

Correction — the actual diff content is in `diffLineView()` at lines 301 and 307:

| Line | Old | New |
|------|-----|-----|
| 301 | `Theme.mono(10)` (line number in diffLineView) | `Theme.code(10)` |
| 307 | `Theme.mono(11)` (line text in diffLineView) | `Theme.code(11)` |

- [ ] **Step 9: Migrate DiffView.swift**

| Line | Old | New |
|------|-----|-----|
| 11 | `.system(size: 11, weight: .regular, design: .monospaced)` | `Theme.code(11)` |

- [ ] **Step 10: Build check**

```bash
xcodebuild build -scheme BudahADE 2>&1 | grep "error:" | grep -i "git\|branch\|diff\|commit\|changes\|staging" | head -10
```

Expected: No git panel errors.

- [ ] **Step 11: Commit**

```bash
git add BudahADE/GitPanel/
git commit -m "feat: migrate git panel fonts — Geist for chrome, Menlo for diff content"
```

---

### Task 4: Migrate Plan/Chat/Markdown Views (35 call sites)

**Files:**
- Modify: `BudahADE/Plan/SlashCommandPopover.swift` (2 sites)
- Modify: `BudahADE/Plan/RoleSelectionModal.swift` (1 site)
- Modify: `BudahADE/Plan/PlanCanvasView.swift` (1 site)
- Modify: `BudahADE/Plan/ActivityFeedView.swift` (2 mono + 2 inline monospaced)
- Modify: `BudahADE/Plan/PlanChatView.swift` (10 sites)
- Modify: `BudahADE/Plan/TileViews/ChatTileView.swift` (6 sites)
- Modify: `BudahADE/Plan/TileViews/MarkdownTileView.swift` (3 sites)
- Modify: `BudahADE/Plan/TileViews/TextContentView.swift` (3 sites)
- Modify: `BudahADE/Plan/TileViews/BrowserTileView.swift` (1 inline monospaced)
- Modify: `BudahADE/Plan/Markdown/CodeBlockView.swift` (3 sites)
- Modify: `BudahADE/Plan/Markdown/EditableMarkdownRenderer.swift` (1 site)
- Modify: `BudahADE/Plan/Markdown/InlineNodesView.swift` (1 site)

- [ ] **Step 1: Migrate SlashCommandPopover.swift**

| Line | Old | New |
|------|-----|-----|
| 115 | `Theme.mono(12)` | `Theme.label(12)` |
| 153 | `Theme.mono(9)` | `Theme.caption(9)` |

- [ ] **Step 2: Migrate RoleSelectionModal.swift**

| Line | Old | New |
|------|-----|-----|
| 87 | `Theme.mono(11)` | `Theme.label(11)` |

- [ ] **Step 3: Migrate PlanCanvasView.swift**

| Line | Old | New |
|------|-----|-----|
| 421 | `Theme.mono(11)` | `Theme.caption(11)` |

- [ ] **Step 4: Migrate ActivityFeedView.swift**

| Line | Old | New |
|------|-----|-----|
| 32 | `.system(size: 14, design: .monospaced)` | `Theme.body(14)` |
| 40 | `.system(size: 12, design: .monospaced)` | `Theme.caption(12)` |
| 72 | `Theme.mono(12)` | `Theme.body(12)` |
| 80 | `Theme.mono(10)` | `Theme.caption(10)` |

- [ ] **Step 5: Migrate PlanChatView.swift (10 sites)**

All are app UI context — model names, token counts, tool metadata:

| Line | Old | New |
|------|-----|-----|
| 397 | `Theme.mono(14)` | `Theme.label(14)` |
| 411 | `Theme.mono(10)` | `Theme.caption(10)` |
| 786 | `Theme.mono(10)` | `Theme.caption(10)` |
| 1078 | `Theme.mono(11)` | `Theme.label(11)` |
| 1082 | `Theme.mono(11)` | `Theme.body(11)` |
| 1086 | `Theme.mono(11)` | `Theme.body(11)` |
| 1158 | `Theme.mono(11, weight: .semibold)` | `Theme.label(11)` |
| 1223 | `Theme.mono(11, weight: .semibold)` | `Theme.label(11)` |
| 1379 | `Theme.mono(13)` | `Theme.body(13)` |

- [ ] **Step 6: Migrate ChatTileView.swift (6 sites)**

| Line | Old | New |
|------|-----|-----|
| 94 | `Theme.mono(13)` | `Theme.label(13)` |
| 102 | `Theme.mono(13)` | `Theme.body(13)` |
| 393 | `Theme.mono(14)` | `Theme.label(14)` |
| 407 | `Theme.mono(10)` | `Theme.caption(10)` |
| 749 | `Theme.mono(10)` | `Theme.caption(10)` |
| 842 | `Theme.mono(13)` | `Theme.body(13)` |

- [ ] **Step 7: Migrate MarkdownTileView.swift (3 sites)**

| Line | Old | New |
|------|-----|-----|
| 63 | `Theme.mono(12)` | `Theme.label(12)` |
| 104 | `Theme.mono(11)` | `Theme.caption(11)` |
| 263 | `Theme.mono(11)` | `Theme.body(11)` |

- [ ] **Step 8: Migrate TextContentView.swift (3 sites)**

| Line | Old | New |
|------|-----|-----|
| 115 | `Theme.mono(10)` | `Theme.caption(10)` |
| 132 | `Theme.mono(10)` | `Theme.caption(10)` |
| 149 | `Theme.mono(10)` | `Theme.caption(10)` |

- [ ] **Step 9: Migrate BrowserTileView.swift**

| Line | Old | New |
|------|-----|-----|
| 55 | `.system(size: 11, design: .monospaced)` | `Theme.body(11)` |

- [ ] **Step 10: Migrate CodeBlockView.swift — split Geist / Menlo**

Header labels (app chrome) → Geist:

| Line | Old | New |
|------|-----|-----|
| 22 | `Theme.mono(11)` (language label) | `Theme.caption(11)` |
| 32 | `Theme.mono(11)` (copy button) | `Theme.caption(11)` |

Code content (terminal) → Menlo:

| Line | Old | New |
|------|-----|-----|
| 51 | `Theme.mono(13)` (syntax-highlighted code) | `Theme.code(13)` |

- [ ] **Step 11: Migrate EditableMarkdownRenderer.swift**

Terminal content → Menlo:

| Line | Old | New |
|------|-----|-----|
| 75 | `Theme.mono(13)` | `Theme.code(13)` |

- [ ] **Step 12: Migrate InlineNodesView.swift**

Inline code in markdown → Menlo (terminal content):

| Line | Old | New |
|------|-----|-----|
| 26 | `Theme.mono(13)` | `Theme.code(13)` |

- [ ] **Step 13: Build check**

```bash
xcodebuild build -scheme BudahADE 2>&1 | grep "error:" | head -10
```

Expected: Remaining errors only in Spec, Task, Terminal, Workspace, FileTree files.

- [ ] **Step 14: Commit**

```bash
git add BudahADE/Plan/
git commit -m "feat: migrate plan/chat/markdown fonts — Geist UI, Menlo for code blocks"
```

---

### Task 5: Migrate Task, Spec, Terminal, Workspace, FileTree (remaining ~20 sites)

**Files:**
- Modify: `BudahADE/Task/NewTaskSheet.swift` (2 sites)
- Modify: `BudahADE/Task/TaskCompletionSheet.swift` (1 site)
- Modify: `BudahADE/Task/TaskRailView.swift` (3 inline monospaced)
- Modify: `BudahADE/Task/TaskArchiveView.swift` (1 inline monospaced)
- Modify: `BudahADE/Spec/SpecPanelView.swift` (4 sites)
- Modify: `BudahADE/Spec/SpecStripView.swift` (3 inline monospaced)
- Modify: `BudahADE/Terminal/TerminalTabBar.swift` (1 site)
- Modify: `BudahADE/Terminal/RestoredTerminalView.swift` (1 inline monospaced)
- Modify: `BudahADE/Workspace/WorkspaceView.swift` (1 site)
- Modify: `BudahADE/FileTree/FilePreviewView.swift` (1 inline monospaced)

- [ ] **Step 1: Migrate NewTaskSheet.swift**

| Line | Old | New |
|------|-----|-----|
| 72 | `Theme.mono(14)` | `Theme.body(14)` |
| 101 | `Theme.mono(11)` | `Theme.body(11)` |

- [ ] **Step 2: Migrate TaskCompletionSheet.swift**

| Line | Old | New |
|------|-----|-----|
| 28 | `Theme.mono(11)` | `Theme.body(11)` |

- [ ] **Step 3: Migrate TaskRailView.swift**

| Line | Old | New |
|------|-----|-----|
| 40 | `.system(size: 9, weight: .medium, design: .monospaced)` | `Theme.label(9)` |
| 163 | `.system(size: 9, weight: .regular, design: .monospaced)` | `Theme.caption(9)` |
| 242 | `.system(size: 9, design: .monospaced)` | `Theme.caption(9)` |

- [ ] **Step 4: Migrate TaskArchiveView.swift**

| Line | Old | New |
|------|-----|-----|
| 83 | `.system(size: 10, design: .monospaced)` | `Theme.caption(10)` |

- [ ] **Step 5: Migrate SpecPanelView.swift**

| Line | Old | New |
|------|-----|-----|
| 116 | `Theme.mono(9)` | `Theme.caption(9)` |
| 184 | `Theme.mono(9)` | `Theme.caption(9)` |
| 212 | `Theme.mono(11)` | `Theme.body(11)` |
| 311 | `Theme.mono(9)` | `Theme.caption(9)` |

- [ ] **Step 6: Migrate SpecStripView.swift**

| Line | Old | New |
|------|-----|-----|
| 38 | `.system(size: 9, weight: .medium, design: .monospaced)` | `Theme.label(9)` |
| 72 | `.system(size: 9, weight: .bold, design: .monospaced)` | `Theme.headline(9)` |
| 80 | `.system(size: 10, weight: .medium, design: .monospaced)` | `Theme.label(10)` |

- [ ] **Step 7: Migrate TerminalTabBar.swift**

| Line | Old | New |
|------|-----|-----|
| 116 | `Theme.mono(9)` | `Theme.caption(9)` |

- [ ] **Step 8: Migrate RestoredTerminalView.swift — terminal content → Menlo**

| Line | Old | New |
|------|-----|-----|
| 15 | `.system(size: 13, design: .monospaced)` | `Theme.code(13)` |

- [ ] **Step 9: Migrate WorkspaceView.swift**

| Line | Old | New |
|------|-----|-----|
| 325 | `Theme.mono(10)` | `Theme.caption(10)` |

- [ ] **Step 10: Migrate FilePreviewView.swift — terminal content → Menlo**

| Line | Old | New |
|------|-----|-----|
| 60 | `.system(size: 10.5, design: .monospaced)` | `Theme.code(10.5)` |

- [ ] **Step 11: Build**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED — zero errors.

- [ ] **Step 12: Commit**

```bash
git add BudahADE/Task/ BudahADE/Spec/ BudahADE/Terminal/TerminalTabBar.swift BudahADE/Terminal/RestoredTerminalView.swift BudahADE/Workspace/WorkspaceView.swift BudahADE/FileTree/FilePreviewView.swift
git commit -m "feat: migrate remaining views — Task, Spec, Terminal tabs, Workspace, FileTree"
```

---

### Task 6: Update Canvas TextFontFamily to Resolve Geist

**Files:**
- Modify: `BudahADE/Plan/CanvasNode.swift:182-207`

- [ ] **Step 1: Update TextData.font (SwiftUI) to use Geist for .system case**

Replace the `font` computed property (lines 182–191):

```swift
    var font: Font {
        let w: Font.Weight = isBold ? .bold : weight.fontWeight
        switch fontFamily {
        case .system:
            return .custom("Geist-Regular", size: fontSize).weight(w)
        case .monospace:
            return .system(size: fontSize, weight: w, design: .monospaced)
        case .serif:
            return .system(size: fontSize, weight: w, design: .serif)
        }
    }
```

- [ ] **Step 2: Update TextData.nsFont (AppKit) to use Geist for .system case**

Replace the `nsFont` computed property (lines 194–207):

```swift
    var nsFont: NSFont {
        let w: NSFont.Weight = isBold ? .bold : weight.nsFontWeight
        switch fontFamily {
        case .system:
            let geistName: String
            switch w {
            case .black: geistName = "Geist-Black"
            case .bold:  geistName = "Geist-Bold"
            case .medium, .semibold: geistName = "Geist-Medium"
            default: geistName = "Geist-Regular"
            }
            return NSFont(name: geistName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: w)
        case .monospace:
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: w)
        case .serif:
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.serif) ?? NSFontDescriptor(name: "Georgia", size: fontSize)
            return NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: w)
        }
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/CanvasNode.swift
git commit -m "feat: canvas TextFontFamily .system case resolves to Geist"
```

---

### Task 7: Verify and Clean Up

- [ ] **Step 1: Grep for any remaining mono references**

```bash
grep -rn "Theme\.mono\b\|Theme\.monoFont\b\|Theme\.uiFont\b" BudahADE/
```

Expected: Zero results.

- [ ] **Step 2: Grep for any remaining inline .monospaced outside canvas/terminal**

```bash
grep -rn "design: \.monospaced" BudahADE/ | grep -v "CanvasNode\|GhosttyConfig\|Theme\.swift"
```

Expected: Zero results.

- [ ] **Step 3: Full clean build**

```bash
xcodebuild clean build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Launch app and verify visually**

```bash
open $(xcodebuild -scheme BudahADE -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}')/BudahADE.app
```

Check:
- All app chrome text renders in Geist (not SF Pro)
- Branch names, labels, chat — all Geist
- Diff modal code lines render in Menlo
- Code blocks in markdown render in Menlo
- Terminal still uses configured font
- Canvas text with `.system` family renders in Geist

- [ ] **Step 5: Commit any cleanup**

Only if Step 1 or 2 found stragglers:

```bash
git add -u
git commit -m "fix: clean up remaining mono font references"
```
