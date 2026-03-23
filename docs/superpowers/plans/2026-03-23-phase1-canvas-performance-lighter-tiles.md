# Phase 1: Canvas Performance + Lighter Tiles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the 1,041-LOC god file `CanvasElementView.swift`, replace heavy text tiles with lightweight alternatives, add a unified markdown tile, improve viewport culling, enhance BrowserTileView, and add branch picker to NewTaskSheet.

**Architecture:** Extract gesture handlers and resize logic into focused files. Replace `RichTextEditor` + `DocumentTileView` + `SpecDocumentTileView` with three lightweight text tiers (sticky, textbox, markdown). The markdown tile is the unified replacement for both `document` and `specDocument` tile types — it detects spec features from file content. Tighten viewport culling to skip body evaluation for offscreen tiles.

**Tech Stack:** SwiftUI, AppKit (NSTextView for markdown editing), WKWebView, XCTest

**Spec:** `docs/superpowers/specs/2026-03-23-workflow-v2-overhaul-design.md` (Phase 1 sections)

---

## File Structure

### Files to Create

| File | Responsibility |
|------|---------------|
| `BudahADE/Plan/TileDragHandler.swift` | Drag gesture logic extracted from CanvasElementView |
| `BudahADE/Plan/TileResizeHandler.swift` | ResizeHandles, ResizeCorner, ResizeEdge, CornerHandle, EdgeHandle, FrameChildResizeHandle |
| `BudahADE/Plan/TileSelectionManager.swift` | Selection chrome, hover state, spec section badge |
| `BudahADE/Plan/FrameContainerView.swift` | FrameContentView, insertion indicator |
| `BudahADE/Plan/TileViews/StickyNoteView.swift` | Auto-sizing plain text tile |
| `BudahADE/Plan/TileViews/TextBoxView.swift` | User-sized plain text tile |
| `BudahADE/Plan/TileViews/MarkdownTileView.swift` | Refactored from SpecDocumentTileView — section-based editor with inline editing, source attribution, checkboxes |
| `BudahADE/Plan/TileViews/MermaidRenderer.swift` | HTML template helper for Mermaid diagrams |
| `BudahADETests/SpecParserTests.swift` | Unit tests for SpecParser |
| `BudahADETests/MarkdownSectionParserTests.swift` | Unit tests for heading-based section parsing |
| `BudahADETests/CanvasNodeTests.swift` | Unit tests for CanvasElement, FrameData, TextData |

### Files to Modify

| File | Changes |
|------|---------|
| `BudahADE/Plan/CanvasElementView.swift` | Reduce from 1,041 LOC to ~150 LOC shell that dispatches to extracted files |
| `BudahADE/Plan/TileType.swift` | Replace `document(path:)` and `specDocument(path:)` with `markdown(path:)`. Add `stickyNote` and `textBox` cases. |
| `BudahADE/Plan/CanvasNode.swift` | No changes needed — ElementKind.tile(TileType) handles new types automatically |
| `BudahADE/Plan/PlanCanvasView.swift` | Tighten viewport culling, add debounce |
| `BudahADE/Plan/PlanCanvasState.swift` | Update `addTile` for new types, update `TileContentView` dispatch, update `assembleSpec`/`detachSpecSection` to use `.markdown` |
| `BudahADE/Plan/AddTileMenu.swift` | Replace Document with Sticky Note, Text Box, Markdown entries |
| `BudahADE/Plan/TileViews/BrowserTileView.swift` | Add `loadHTMLString` path to WebViewStore |
| `BudahADE/Task/NewTaskSheet.swift` | Replace base branch text field with branch picker |
| `BudahADE/Spec/SpecParser.swift` | Change `slugify` from `private` to `static` (internal). Add `MarkdownSection` struct and `parseMarkdownSections` method. |
| `BudahADE.xcodeproj/project.pbxproj` | Add new files, remove deleted files |

### Files to Delete

| File | Reason |
|------|--------|
| `BudahADE/Plan/TileViews/RichTextEditor.swift` | 339 LOC — replaced by lightweight text tiers |
| `BudahADE/Plan/TileViews/DocumentTileView.swift` | 100 LOC — replaced by markdown tile |
| `BudahADE/Plan/TileViews/SpecDocumentTileView.swift` | 242 LOC — refactored into MarkdownTileView |

---

## Task 1: Set Up XCTest Target

**Files:**
- Modify: `BudahADE.xcodeproj/project.pbxproj`
- Create: `BudahADETests/SpecParserTests.swift`

- [ ] **Step 1: Create test directory and initial test file**

First create the directory:
```bash
mkdir -p BudahADETests
```

Then create the file:
```swift
// BudahADETests/SpecParserTests.swift
import XCTest
@testable import BudahADE

final class SpecParserTests: XCTestCase {
    func testParseEmptyFile() {
        // Will implement in Task 7
    }
}
```

- [ ] **Step 2: Add test target to Xcode project**

Use `xcodebuild` or manually add a test target named `BudahADETests` to the xcodeproj. The test target must:
- Link against the main `BudahADE` app target
- Include `BudahADETests/` as its source directory
- Use `@testable import BudahADE`

Run: `xcodebuild -project BudahADE.xcodeproj -list` to verify the target appears.

- [ ] **Step 3: Verify test target builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADETests build-for-testing -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADETests/SpecParserTests.swift BudahADE.xcodeproj/project.pbxproj
git commit -m "chore: add XCTest target for unit tests"
```

---

## Task 2: Update TileType — Replace document/specDocument with Unified Types

**Files:**
- Modify: `BudahADE/Plan/TileType.swift`
- Test: `BudahADETests/CanvasNodeTests.swift`

- [ ] **Step 1: Write tests for new tile types**

```swift
// BudahADETests/CanvasNodeTests.swift
import XCTest
@testable import BudahADE

final class TileTypeTests: XCTestCase {
    func testMarkdownDisplayName() {
        let tile = TileType.markdown(path: "/tmp/spec.md")
        XCTAssertEqual(tile.displayName, "Markdown")
    }

    func testStickyNoteDisplayName() {
        let tile = TileType.stickyNote
        XCTAssertEqual(tile.displayName, "Sticky Note")
    }

    func testTextBoxDisplayName() {
        let tile = TileType.textBox
        XCTAssertEqual(tile.displayName, "Text Box")
    }

    func testMarkdownIconName() {
        let tile = TileType.markdown(path: "/tmp/test.md")
        XCTAssertEqual(tile.iconName, "doc.text")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test|FAIL|error'`
Expected: Compile error — `stickyNote`, `textBox`, `markdown` don't exist yet

- [ ] **Step 3: Update TileType enum**

Replace the `TileType` enum in `BudahADE/Plan/TileType.swift`:

```swift
enum TileType: Equatable {
    case terminal(panelId: UUID, agent: AgentMode)
    case stickyNote
    case textBox
    case markdown(path: String)
    case image(path: String)
    case browser(url: URL?)

    var displayName: String {
        switch self {
        case .terminal(_, let agent): return agent.displayName
        case .stickyNote:             return "Sticky Note"
        case .textBox:                return "Text Box"
        case .markdown:               return "Markdown"
        case .image:                  return "Image"
        case .browser:                return "Browser"
        }
    }

    var iconName: String {
        switch self {
        case .terminal(_, let agent): return agent.iconName
        case .stickyNote:             return "note.text"
        case .textBox:                return "text.alignleft"
        case .markdown:               return "doc.text"
        case .image:                  return "photo"
        case .browser:                return "globe"
        }
    }
}
```

- [ ] **Step 4: Fix all compilation errors from removed cases**

Search for `.document(` and `.specDocument(` across the codebase. Each reference must be updated:

- `CanvasElementView.swift` `TileContentView`: `.document` → remove case, `.specDocument` → replace with `.markdown`
- `PlanCanvasState.swift` `addTile`: remove `.document` handling, update `.specDocument` refs to `.markdown`
- `PlanCanvasState.swift` `assembleSpec`: `.specDocument` → `.markdown`
- `PlanCanvasState.swift` `detachSpecSection`: `.document` → `.markdown`
- `PlanCanvasState.swift` `mergeIntoSpec`: `.document` → `.markdown`
- `PlanCanvasView.swift` context menu: "Add Document" → creates `.markdown` tile
- `AddTileMenu.swift`: update menu entries
- `ContextManifest.swift`: update `.document` and `.specDocument` pattern matches to `.markdown(let path): documents.append(path)`
- `SpecAssembler.swift`: update tile type checks

Note: The TileContentView dispatch for `.stickyNote`, `.textBox`, and `.markdown` will initially use placeholder views (e.g., `Text("TODO")`) until Tasks 4-6 create the real views.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test|PASS|FAIL'`
Expected: All TileTypeTests PASS

- [ ] **Step 6: Verify the app still builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: replace document/specDocument tile types with stickyNote, textBox, markdown"
```

---

## Task 3: Extract CanvasElementView into Focused Files

This is a refactor — no new logic, just moving code. No TDD needed.

**Files:**
- Modify: `BudahADE/Plan/CanvasElementView.swift` (reduce from 1,041 → ~150 LOC)
- Create: `BudahADE/Plan/TileDragHandler.swift` (~120 LOC)
- Create: `BudahADE/Plan/TileResizeHandler.swift` (~280 LOC)
- Create: `BudahADE/Plan/TileSelectionManager.swift` (~60 LOC)
- Create: `BudahADE/Plan/FrameContainerView.swift` (~180 LOC)
- Modify: `BudahADE.xcodeproj/project.pbxproj`

### Extraction Map

**Important:** `GridSnap` and `CanvasGrid` are defined in `SmartGuides.swift` — do NOT move them.

**TileDragHandler.swift** — extract from CanvasElementView:
- `borderDragGesture` computed property (lines 174-290)
- Make it a standalone struct: `struct TileDragHandler` with a static method or ViewModifier
- Needs access to: `element`, `canvas`, `dragOffset` binding

**TileResizeHandler.swift** — extract:
- `ResizeCorner` enum (lines 668-756)
- `ResizeHandles` struct (lines 760-774)
- `FrameChildResizeHandle` struct (lines 778-828)
- `CornerHandle` struct (lines 830-913)
- `ResizeEdge` enum (lines 917-944)
- `EdgeHandle` struct (lines 948-1041)

**TileSelectionManager.swift** — extract:
- `specSectionBadge` computed property (lines 98-121)
- `elementBackground` computed property (lines 150-159)
- `selectionBorder` computed property (lines 161-170)

**FrameContainerView.swift** — extract:
- `FrameContentView` struct (lines 338-515)
- Already a separate struct, just needs to move to its own file

**TextContentView + TextStyleToolbar stay in CanvasElementView.swift** or move to a small `TextContentView.swift`. These are already reasonably sized (~100 LOC combined).

- [ ] **Step 1: Create TileResizeHandler.swift**

Move `ResizeCorner`, `ResizeEdge`, `ResizeHandles`, `FrameChildResizeHandle`, `CornerHandle`, `EdgeHandle` from `CanvasElementView.swift` to `BudahADE/Plan/TileResizeHandler.swift`. Keep all types as `internal` (no access change needed). Add `import SwiftUI` and `import AppKit` at top.

- [ ] **Step 2: Create FrameContainerView.swift**

Move `FrameContentView` struct to `BudahADE/Plan/FrameContainerView.swift`. Add `import SwiftUI` at top.

- [ ] **Step 3: Create TileDragHandler.swift**

Extract the `borderDragGesture` from `CanvasElementView` into a reusable struct:

```swift
// BudahADE/Plan/TileDragHandler.swift
import SwiftUI

struct TileDragHandler {
    static func dragGesture(
        element: CanvasElement,
        canvas: PlanCanvasState,
        dragOffset: Binding<CGSize>
    ) -> some Gesture {
        // ... (the existing borderDragGesture body, adapted to use parameters)
    }
}
```

- [ ] **Step 4: Create TileSelectionManager.swift**

Extract `specSectionBadge`, `elementBackground`, and `selectionBorder` into a helper:

```swift
// BudahADE/Plan/TileSelectionManager.swift
import SwiftUI

struct TileSelectionChrome {
    static func specSectionBadge(for element: CanvasElement) -> some View { ... }
    static func elementBackground(for kind: ElementKind) -> some View { ... }
    static func selectionBorder(isSelected: Bool, isHovered: Bool) -> some View { ... }
}
```

- [ ] **Step 5: Move TextContentView and TextStyleToolbar to their own file (optional)**

If CanvasElementView is still over 200 LOC after the above extractions, move `TextContentView` and `TextStyleToolbar` to `BudahADE/Plan/TileViews/TextContentView.swift`.

- [ ] **Step 6: Update CanvasElementView.swift to use extracted types**

The remaining `CanvasElementView.swift` should be ~150 LOC: the `body` property dispatching to content views, using `TileDragHandler.dragGesture()`, `ResizeHandles`, and `TileSelectionChrome` helpers.

- [ ] **Step 7: Update pbxproj with new files**

Add all new files to `PBXBuildFile`, `PBXFileReference`, and the appropriate `PBXGroup` sections in `project.pbxproj`.

- [ ] **Step 8: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: decompose CanvasElementView (1041 LOC) into focused files"
```

---

## Task 4: Create StickyNoteView

**Files:**
- Create: `BudahADE/Plan/TileViews/StickyNoteView.swift`
- Modify: `BudahADE/Plan/CanvasElementView.swift` (TileContentView dispatch)
- Modify: `BudahADE/Plan/PlanCanvasState.swift` (addTile support)
- Modify: `BudahADE.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create StickyNoteView**

```swift
// BudahADE/Plan/TileViews/StickyNoteView.swift
import SwiftUI

/// Plain text, auto-sizes to content. Lightweight sticky note.
struct StickyNoteView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TileChrome(
            title: "Sticky Note",
            icon: "note.text",
            onClose: onClose
        ) {
            TextEditor(text: $content)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)
        }
    }
}
```

- [ ] **Step 2: Wire into TileContentView dispatch**

In `CanvasElementView.swift`, add case to `TileContentView.body`:

```swift
case .stickyNote:
    StickyNoteView(elementId: elementId, canvas: canvas) {
        canvas.removeElement(elementId)
    }
```

- [ ] **Step 3: Update PlanCanvasState for sticky note creation**

No special handling needed — `addTile(type: .stickyNote, at:)` works with existing generic path. Set default size to `CGSize(width: 200, height: 160)` for sticky notes.

- [ ] **Step 4: Verify app builds and sticky note renders**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add StickyNoteView — lightweight auto-sizing text tile"
```

---

## Task 5: Create TextBoxView

**Files:**
- Create: `BudahADE/Plan/TileViews/TextBoxView.swift`
- Modify: `BudahADE/Plan/CanvasElementView.swift` (TileContentView dispatch)
- Modify: `BudahADE.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create TextBoxView**

```swift
// BudahADE/Plan/TileViews/TextBoxView.swift
import SwiftUI

/// Multi-line plain text, user-sized. For longer notes that need explicit dimensions.
struct TextBoxView: View {
    let elementId: UUID
    @ObservedObject var canvas: PlanCanvasState
    let onClose: () -> Void

    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TileChrome(
            title: "Text Box",
            icon: "text.alignleft",
            onClose: onClose
        ) {
            TextEditor(text: $content)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)
        }
    }
}
```

- [ ] **Step 2: Wire into TileContentView dispatch**

```swift
case .textBox:
    TextBoxView(elementId: elementId, canvas: canvas) {
        canvas.removeElement(elementId)
    }
```

- [ ] **Step 3: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add TextBoxView — user-sized plain text tile"
```

---

## Task 6: Refactor SpecDocumentTileView → MarkdownTileView

**Files:**
- Create: `BudahADE/Plan/TileViews/MarkdownTileView.swift` (refactored from SpecDocumentTileView)
- Delete: `BudahADE/Plan/TileViews/SpecDocumentTileView.swift`
- Modify: `BudahADE/Spec/SpecParser.swift` (extend with MarkdownSection)
- Modify: `BudahADE/Plan/CanvasElementView.swift` (TileContentView dispatch)
- Test: `BudahADETests/MarkdownSectionParserTests.swift`
- Modify: `BudahADE.xcodeproj/project.pbxproj`

**Architecture note:** `MarkdownSection` is a NEW struct that coexists alongside the existing `SpecSection`. `SpecSection` is used by `SpecParser.parse(fileAt:)` for the existing spec tracking system (SpecState, SpecPanelView, etc.). `MarkdownSection` is used by the new `parseMarkdownSections(from:)` method for the tile's section-based inline editing UI. Both structs represent sections of a markdown file, but serve different systems. Do NOT merge them.

### Sub-step 6a: Extend SpecParser with MarkdownSection

- [ ] **Step 1: Change `slugify` access modifier**

In `BudahADE/Spec/SpecParser.swift`, change line 173:
```swift
// FROM:
private static func slugify(_ text: String) -> String {
// TO:
static func slugify(_ text: String) -> String {
```

This is needed because the new `parseMarkdownSections` extension method calls `slugify`, which must be accessible.

- [ ] **Step 2: Write tests for MarkdownSection parsing**

```swift
// BudahADETests/MarkdownSectionParserTests.swift
import XCTest
@testable import BudahADE

final class MarkdownSectionParserTests: XCTestCase {
    func testSplitByHeadings() {
        let md = """
        # Title
        Intro text.

        ## Section One
        Content one.

        ## Section Two
        Content two.
        - [ ] Task A
        - [x] Task B
        """
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].heading, "Section One")
        XCTAssertEqual(result[1].heading, "Section Two")
        XCTAssertEqual(result[1].checkboxItems.count, 2)
        XCTAssertFalse(result[1].checkboxItems[0].isCompleted)
        XCTAssertTrue(result[1].checkboxItems[1].isCompleted)
    }

    func testSourceAttribution() {
        let md = """
        ## Design
        <!-- source: abc-123 -->
        Design content here.
        """
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result[0].sourceId, "abc-123")
    }

    func testNoSections() {
        let md = "Just some text with no headings."
        let result = SpecParser.parseMarkdownSections(from: md)
        XCTAssertEqual(result.count, 0)
    }

    func testCheckboxToggleRewrite() {
        let original = "- [ ] unchecked task"
        let toggled = SpecParser.toggleCheckbox(in: original, at: 0)
        XCTAssertEqual(toggled, "- [x] unchecked task")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'FAIL|error'`
Expected: Compile errors — `parseMarkdownSections`, `MarkdownSection` don't exist

- [ ] **Step 4: Add MarkdownSection model and parser to SpecParser.swift**

Add to `BudahADE/Spec/SpecParser.swift`:

```swift
// MARK: - Markdown Section (for section-based editing in MarkdownTileView)

struct MarkdownSection: Identifiable, Equatable {
    let id: String          // slugified heading
    let heading: String
    let body: String
    var sourceId: String?   // from <!-- source: xxx --> comment
    let checkboxItems: [SpecTask]
    let lineRange: Range<Int>
}

extension SpecParser {
    /// Split markdown content by ## headings into editable sections.
    /// Used by MarkdownTileView for section-based inline editing.
    /// Separate from parse(fileAt:) which feeds the SpecState/SpecPanelView system.
    static func parseMarkdownSections(from content: String) -> [MarkdownSection] {
        let lines = content.components(separatedBy: .newlines)
        var sections: [MarkdownSection] = []
        var currentHeading: String?
        var currentStartLine: Int = 0
        var currentLines: [String] = []
        var currentSourceId: String?
        var currentTasks: [SpecTask] = []
        var taskIndex = 0

        func flush(endLine: Int) {
            guard let heading = currentHeading else { return }
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(MarkdownSection(
                id: slugify(heading),
                heading: heading,
                body: body,
                sourceId: currentSourceId,
                checkboxItems: currentTasks,
                lineRange: currentStartLine..<endLine
            ))
            currentHeading = nil
            currentLines = []
            currentSourceId = nil
            currentTasks = []
        }

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                flush(endLine: idx)
                currentHeading = String(trimmed.dropFirst(3))
                currentStartLine = idx
                continue
            }

            if currentHeading != nil {
                // Check for source attribution
                if trimmed.hasPrefix("<!-- source:"),
                   let end = trimmed.range(of: "-->") {
                    let start = trimmed.index(trimmed.startIndex, offsetBy: 13)
                    currentSourceId = String(trimmed[start..<end.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                }

                // Check for checkboxes
                let sectionSlug = currentHeading.map { slugify($0) }
                if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                    currentTasks.append(SpecTask(
                        id: taskIndex, title: String(trimmed.dropFirst(6)),
                        isCompleted: true, sectionId: sectionSlug
                    ))
                    taskIndex += 1
                } else if trimmed.hasPrefix("- [ ] ") {
                    currentTasks.append(SpecTask(
                        id: taskIndex, title: String(trimmed.dropFirst(6)),
                        isCompleted: false, sectionId: sectionSlug
                    ))
                    taskIndex += 1
                }

                currentLines.append(line)
            }
        }
        flush(endLine: lines.count)
        return sections
    }

    /// Toggle a checkbox at the given task index in the content string
    static func toggleCheckbox(in content: String, at taskIndex: Int) -> String {
        let lines = content.components(separatedBy: .newlines)
        var newLines = lines
        var counter = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") ||
               trimmed.hasPrefix("- [ ] ") {
                if counter == taskIndex {
                    if trimmed.hasPrefix("- [ ] ") {
                        newLines[i] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                    } else {
                        newLines[i] = line
                            .replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                            .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                    }
                    break
                }
                counter += 1
            }
        }
        return newLines.joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test|PASS|FAIL'`
Expected: All MarkdownSectionParserTests PASS

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Spec/SpecParser.swift BudahADETests/MarkdownSectionParserTests.swift
git commit -m "feat: add MarkdownSection parser with source attribution and checkbox toggle"
```

### Sub-step 6b: Create MarkdownTileView

- [ ] **Step 7: Create MarkdownTileView.swift**

Refactor from SpecDocumentTileView. Key additions:
- Section-based inline editing (click section → TextEditor, click away → rendered markdown)
- Source attribution display (colored dot + "from {source}" label) when `<!-- source: xxx -->` present
- Header: title, section count, Draft/Finalized badge
- Footer: file path, section/checkbox counts

```swift
// BudahADE/Plan/TileViews/MarkdownTileView.swift
import SwiftUI

/// Unified markdown tile — handles plain markdown files and spec files with checkboxes.
/// Section-based inline editing: click a ## section to edit, click away to render.
struct MarkdownTileView: View {
    let path: String
    @ObservedObject var canvas: PlanCanvasState
    let elementId: UUID
    let onClose: () -> Void

    @State private var spec: SpecParseResult?
    @State private var sections: [MarkdownSection] = []
    @State private var editingSectionId: String?
    @State private var editContent: String = ""
    @State private var pollTimer: Timer?

    private var filename: String {
        (path as NSString).lastPathComponent
    }

    private var hasCheckboxes: Bool {
        sections.contains { !$0.checkboxItems.isEmpty }
    }

    var body: some View {
        TileChrome(
            title: spec?.title ?? filename,
            icon: hasCheckboxes ? "doc.badge.gearshape" : "doc.text",
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                // Header with counts
                tileHeader

                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                // Progress bar (only if has checkboxes)
                if let spec, spec.totalCount > 0 {
                    progressBar(spec)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
                }

                // Sections
                if sections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                sectionView(section)
                            }
                        }
                    }
                }

                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                // Footer
                tileFooter
            }
        }
        .onAppear { reload(); startPolling() }
        .onDisappear { stopPolling() }
    }

    // ... (section rendering, editing, checkbox toggle — adapted from SpecDocumentTileView)
    // Key difference: each section has edit/display toggle based on editingSectionId
}
```

The full implementation should:
1. Keep all existing SpecDocumentTileView checkbox functionality
2. Add click-to-edit per section (set `editingSectionId`, show `TextEditor`)
3. On edit commit: write section back to file, reload
4. Display `sourceId` as colored dot when present
5. Show footer with file path and counts
6. Carry forward the detach-section button from SpecDocumentTileView
7. Use `SpecParser.parseMarkdownSections(from:)` for section data and `SpecParser.parse(fileAt:)` for overall progress

- [ ] **Step 8: Wire MarkdownTileView into TileContentView dispatch**

In `CanvasElementView.swift`:

```swift
case .markdown(let path):
    MarkdownTileView(
        path: path,
        canvas: canvas,
        elementId: elementId
    ) {
        canvas.removeElement(elementId)
    }
```

- [ ] **Step 9: Delete old files**

Remove `SpecDocumentTileView.swift`, `DocumentTileView.swift`, `RichTextEditor.swift`. Update pbxproj to remove these file references.

- [ ] **Step 10: Update PlanCanvasState references**

- `assembleSpec()`: change `.specDocument(path:)` to `.markdown(path:)`
- `detachSpecSection()`: change `.document(path:)` to `.markdown(path:)`
- `mergeIntoSpec()`: change `.document(path:)` to `.markdown(path:)`

- [ ] **Step 11: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "feat: unified MarkdownTileView replaces document and specDocument tiles"
```

---

## Task 7: Write SpecParser Unit Tests

**Files:**
- Modify: `BudahADETests/SpecParserTests.swift`

- [ ] **Step 1: Write comprehensive SpecParser tests**

```swift
// BudahADETests/SpecParserTests.swift
import XCTest
@testable import BudahADE

final class SpecParserTests: XCTestCase {
    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "specparser-tests-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    private func writeFile(_ name: String, content: String) -> String {
        let path = (tmpDir as NSString).appendingPathComponent(name)
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testParseTitle() {
        let path = writeFile("test-spec.md", content: "# My Spec\n\n## Tasks\n- [ ] Do thing")
        let result = SpecParser.parse(fileAt: path)
        XCTAssertEqual(result?.title, "My Spec")
    }

    func testParseSections() {
        let path = writeFile("test-spec.md", content: """
        # Spec
        ## Architecture
        Some text.
        ## Tasks
        - [ ] Item 1
        - [x] Item 2
        """)
        let result = SpecParser.parse(fileAt: path)!
        XCTAssertEqual(result.sections.count, 2)
        XCTAssertEqual(result.sections[0].title, "Architecture")
        XCTAssertEqual(result.sections[1].title, "Tasks")
        XCTAssertEqual(result.sections[1].tasks.count, 2)
    }

    func testProgressCalculation() {
        let path = writeFile("test-spec.md", content: """
        # S
        ## T
        - [x] Done
        - [ ] Not done
        - [x] Also done
        """)
        let result = SpecParser.parse(fileAt: path)!
        XCTAssertEqual(result.completedCount, 2)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    func testFindSpecFiles() {
        _ = writeFile("feature-spec.md", content: "# F")
        _ = writeFile("plan-plan.md", content: "# P")
        _ = writeFile("readme.md", content: "# R") // should NOT match
        let found = SpecParser.findSpecFiles(in: tmpDir)
        XCTAssertEqual(found.count, 2)
    }

    func testParseReturnsNilForEmptyFile() {
        let path = writeFile("empty-spec.md", content: "Just text, no sections or tasks.")
        let result = SpecParser.parse(fileAt: path)
        XCTAssertNil(result)
    }

    func testParseMissingFile() {
        let result = SpecParser.parse(fileAt: "/nonexistent/path.md")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test|PASS|FAIL'`
Expected: All SpecParserTests PASS (tests verify existing functionality)

- [ ] **Step 3: Commit**

```bash
git add BudahADETests/SpecParserTests.swift
git commit -m "test: add comprehensive SpecParser unit tests"
```

---

## Task 8: Update AddTileMenu

**Files:**
- Modify: `BudahADE/Plan/AddTileMenu.swift`
- Modify: `BudahADE/Plan/PlanCanvasView.swift` (context menu)

- [ ] **Step 1: Update AddTileMenu callbacks and entries**

Replace `onAddDocument: () -> Void` with:
- `onAddStickyNote: () -> Void`
- `onAddTextBox: () -> Void`
- `onAddMarkdown: () -> Void`

Update the menu body to show three text tier options instead of one "Document" entry:

```swift
utilityRow(icon: "note.text", name: "Sticky Note", description: "Quick note, auto-sizes", key: "sticky") {
    onAddStickyNote()
    dismiss()
}
utilityRow(icon: "text.alignleft", name: "Text Box", description: "Multi-line text, user-sized", key: "textbox") {
    onAddTextBox()
    dismiss()
}
utilityRow(icon: "doc.text", name: "Markdown", description: "Section-based document", key: "markdown") {
    onAddMarkdown()
    dismiss()
}
```

- [ ] **Step 2: Update PlanCanvasView context menu**

Replace "Add Document" with three entries:
- "Add Sticky Note" → `canvas.addTile(type: .stickyNote, at: position)` with size `(200, 160)`
- "Add Text Box" → `canvas.addTile(type: .textBox, at: position)` with default size
- "Add Markdown" → creates file, `canvas.addTile(type: .markdown(path:), at: position)`

- [ ] **Step 3: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/AddTileMenu.swift BudahADE/Plan/PlanCanvasView.swift
git commit -m "feat: update tile menu with sticky note, text box, and markdown options"
```

---

## Task 9: Tighten Viewport Culling

**Files:**
- Modify: `BudahADE/Plan/PlanCanvasView.swift`
- Modify: `BudahADE/Plan/TileViews/BrowserTileView.swift`

- [ ] **Step 1: Add debounced viewport culling**

The viewport culling already exists in `PlanCanvasView.visibleElements` as a computed property. To improve performance, follow the existing debounce pattern already used in `commitViewportToCanvas()` (which debounces `@Published` updates via `DispatchWorkItem`).

Add `.onChange` triggers for `localZoom` and `localPanOffset` that call a debounced method:

```swift
// Add state:
@State private var cachedVisibleIds: Set<UUID> = []
@State private var cullingDebounce: DispatchWorkItem?

// Add to body, inside the GeometryReader:
.onChange(of: localZoom) { _, _ in debounceCulling() }
.onChange(of: localPanOffset) { _, _ in debounceCulling() }
.onChange(of: canvas.elements.count) { _, _ in debounceCulling() }

// Method:
private func debounceCulling() {
    cullingDebounce?.cancel()
    let zoom = localZoom
    let offset = localPanOffset
    let vpSize = viewportSize
    let elements = canvas.elements
    let task = DispatchWorkItem {
        let margin: CGFloat = 100
        let viewport = CGRect(
            x: -margin, y: -margin,
            width: vpSize.width + margin * 2,
            height: vpSize.height + margin * 2
        )
        let ids = Set(elements.filter { el in
            let screenRect = CGRect(
                x: el.position.x * zoom + offset.width,
                y: el.position.y * zoom + offset.height,
                width: el.size.width * zoom,
                height: el.size.height * zoom
            )
            return viewport.intersects(screenRect)
        }.map(\.id))
        cachedVisibleIds = ids
    }
    cullingDebounce = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: task)
}

// Update canvasContent to use cachedVisibleIds:
private var visibleElements: [CanvasElement] {
    if cachedVisibleIds.isEmpty {
        return canvas.elements // first render before debounce fires
    }
    return canvas.elements.filter { cachedVisibleIds.contains($0.id) }
}
```

- [ ] **Step 2: Add offscreen WKWebView teardown in BrowserTileView**

Add `isVisible` parameter to `BrowserTileView`. When `isVisible` is false, show a static placeholder (globe icon + URL text) instead of the WebView. The `canvasContent` in `PlanCanvasView` passes visibility info based on `cachedVisibleIds`.

```swift
// BrowserTileView changes:
struct BrowserTileView: View {
    let initialURL: URL?
    let onClose: () -> Void
    var isVisible: Bool = true  // NEW

    // In body, wrap WebView content:
    if isVisible {
        WebViewRepresentable(store: webViewStore)
    } else {
        // Lightweight placeholder
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted)
            if let url = initialURL {
                Text(url.host ?? url.absoluteString)
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/PlanCanvasView.swift BudahADE/Plan/TileViews/BrowserTileView.swift
git commit -m "perf: debounced viewport culling and offscreen WKWebView teardown"
```

---

## Task 10: Enhance BrowserTileView with loadHTMLString

**Files:**
- Modify: `BudahADE/Plan/TileViews/BrowserTileView.swift`
- Create: `BudahADE/Plan/TileViews/MermaidRenderer.swift`
- Modify: `BudahADE.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add loadHTMLString to WebViewStore**

```swift
// In WebViewStore:
func loadHTML(_ html: String, baseURL: URL? = nil) {
    ensureWebView()
    webView?.loadHTMLString(html, baseURL: baseURL)
}
```

- [ ] **Step 2: Create MermaidRenderer**

```swift
// BudahADE/Plan/TileViews/MermaidRenderer.swift
import Foundation

enum MermaidRenderer {
    /// Wraps Mermaid diagram code in an HTML page ready for WKWebView
    static func htmlPage(diagramCode: String, theme: MermaidTheme = .dark) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    background: \(theme.backgroundColor);
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    padding: 16px;
                }
            </style>
        </head>
        <body>
            <pre class="mermaid">
            \(diagramCode)
            </pre>
            <script src="mermaid.min.js"></script>
            <script>
                mermaid.initialize({
                    startOnLoad: true,
                    theme: '\(theme.mermaidTheme)',
                    themeVariables: { fontSize: '14px' }
                });
            </script>
        </body>
        </html>
        """
    }

    enum MermaidTheme {
        case dark, light

        var backgroundColor: String {
            switch self {
            case .dark: return "#141416"
            case .light: return "#ffffff"
            }
        }

        var mermaidTheme: String {
            switch self {
            case .dark: return "dark"
            case .light: return "default"
            }
        }
    }
}
```

Note: The actual `mermaid.min.js` bundle will be added in Phase 6 (Visual Tiles). For now, this helper generates the HTML template. When the JS file is bundled, it will be referenced via `baseURL` pointing to the app's resources.

- [ ] **Step 3: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add loadHTMLString to BrowserTileView and MermaidRenderer helper"
```

---

## Task 11: Branch Picker in NewTaskSheet

**Files:**
- Modify: `BudahADE/Task/NewTaskSheet.swift`
- Modify: `BudahADE/GitPanel/GitRepository.swift`

- [ ] **Step 1: Add static branch listing method to GitRepository**

`GitRepository` currently only has instance-based `branches: [String]` (populated by polling). Add a static async method for one-shot branch listing:

```swift
// In GitRepository.swift, add:
static func listBranches(at repoPath: String) async -> [String] {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["branch", "--format=%(refname:short)"]
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let branches = output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: branches)
            } catch {
                continuation.resume(returning: ["main"])
            }
        }
    }
}
```

- [ ] **Step 2: Replace base branch text field with Picker**

In `NewTaskSheet.swift`, replace the base branch `TextField` with a `Menu`-based picker:

```swift
// Add state:
@State private var availableBranches: [String] = ["main"]

// Replace the TextField:
Menu {
    ForEach(availableBranches, id: \.self) { branch in
        Button(branch) {
            baseBranch = branch
        }
    }
} label: {
    HStack(spacing: 4) {
        Text(baseBranch)
            .font(Theme.mono(11))
            .foregroundColor(Theme.textSecondary)
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8))
            .foregroundColor(Theme.textMuted)
    }
}
.menuStyle(.borderlessButton)
.frame(maxWidth: 120)
```

Update `.onAppear` to load branches:
```swift
.onAppear {
    focusedField = .name
    Task {
        let branches = await GitRepository.listBranches(at: workspace.projectPath)
        availableBranches = branches.isEmpty ? ["main"] : branches
        if !availableBranches.contains(baseBranch) {
            baseBranch = availableBranches.first ?? "main"
        }
    }
}
```

- [ ] **Step 3: Verify app builds**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Task/NewTaskSheet.swift BudahADE/GitPanel/GitRepository.swift
git commit -m "feat: branch picker dropdown in NewTaskSheet replaces text field"
```

---

## Task 12: Write CanvasNode Unit Tests

**Files:**
- Modify: `BudahADETests/CanvasNodeTests.swift`

- [ ] **Step 1: Add FrameData and TextData tests**

```swift
// BudahADETests/CanvasNodeTests.swift (extend existing file from Task 2)

final class FrameDataTests: XCTestCase {
    func testEmptyFrameSize() {
        let frame = FrameData()
        XCTAssertEqual(frame.computedSize, CGSize(width: 240, height: 180))
    }

    func testHorizontalChildPositions() {
        var frame = FrameData(axis: .horizontal, gap: 10, padding: 20)
        frame.children = [
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
        ]
        let positions = frame.childPositions()
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].x, 20) // padding
        XCTAssertEqual(positions[1].x, 130) // padding + width + gap
    }

    func testVerticalChildPositions() {
        var frame = FrameData(axis: .vertical, gap: 10, padding: 20)
        frame.children = [
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
            CanvasElement(kind: .tile(.stickyNote), size: CGSize(width: 100, height: 80)),
        ]
        let positions = frame.childPositions()
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].y, frame.headerHeight + 20) // header + padding
        XCTAssertEqual(positions[1].y, frame.headerHeight + 20 + 80 + 10) // header + padding + height + gap
    }
}

final class TextDataTests: XCTestCase {
    func testDefaultColor() {
        let data = TextData()
        XCTAssertEqual(data.colorHex, 0xe5e5e5)
    }

    func testMeasuredSizeNonZero() {
        let data = TextData(content: "Hello world")
        let size = data.measuredSize(maxWidth: 200)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
```

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test Suite|Executed|PASS|FAIL'`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add BudahADETests/CanvasNodeTests.swift
git commit -m "test: add FrameData and TextData unit tests"
```

---

## Task 13: Final Integration Verification

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADETests -destination 'platform=macOS' 2>&1 | grep -E 'Test Suite|Executed|PASS|FAIL'`
Expected: All tests PASS

- [ ] **Step 2: Build release configuration**

Run: `xcodebuild -project BudahADE.xcodeproj -scheme BudahADE build -configuration Release -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify file count and LOC reduction**

Check that:
- `CanvasElementView.swift` is ~150 LOC (down from 1,041)
- `RichTextEditor.swift` deleted (339 LOC removed)
- `DocumentTileView.swift` deleted (100 LOC removed)
- `SpecDocumentTileView.swift` deleted (242 LOC removed)
- New files created: TileDragHandler, TileResizeHandler, TileSelectionManager, FrameContainerView, StickyNoteView, TextBoxView, MarkdownTileView, MermaidRenderer
- Net LOC change: roughly neutral (decomposed, not added)

Run: `wc -l BudahADE/Plan/CanvasElementView.swift`
Expected: ~150

- [ ] **Step 4: Commit if any final fixups were needed**

```bash
git add -A
git commit -m "chore: Phase 1 integration verification — all tests pass"
```

---

## Performance Verification (Manual)

After all tasks complete, manually verify in the running app:

1. **15-tile canvas:** Create 15 tiles (mix of sticky, text, markdown, browser, terminal). Pan and zoom. Target: no dropped frames, smooth 60fps.
2. **Offscreen tiles:** Zoom out so some browser tiles are offscreen. Verify WKWebView is torn down (check Activity Monitor for WebContent processes).
3. **Gesture responsiveness:** Drag tiles rapidly. No lag, no dropped frames during drag.
4. **Markdown tile:** Open a spec file. Click sections to edit. Toggle checkboxes. Verify writes to disk.
5. **Branch picker:** Create new task, verify branch dropdown shows all local branches.
