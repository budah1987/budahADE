# Geist Font Migration

## Summary

Replace the system font (SF Pro) with Geist as the app-wide UI font. Establish a clear two-font system: Geist for all app chrome and conversation content, Menlo exclusively for terminal-like content (diffs, code blocks, file preview, Ghostty).

## Font Strategy

| Zone | Font | Weights | Usage |
|---|---|---|---|
| App UI | Geist | Regular, Medium, Bold, Black | All chrome, labels, paths, branch names, hashes, conversation, markdown, chat |
| Terminal content | Menlo | Regular, Medium, Bold | Diff line content, code blocks, file preview, DiffView, Ghostty terminal |

## Changes

### 1. Bundle Geist Fonts

Copy from `~/node_modules/geist/dist/fonts/geist-sans/` into `BudahADE/Resources/Fonts/`:
- `Geist-Regular.ttf`
- `Geist-Medium.ttf`
- `Geist-Bold.ttf`
- `Geist-Black.ttf`

### 2. Font Registration

Add to `Info.plist`:
```xml
<key>ATSApplicationFontsPath</key>
<string>Resources/Fonts</string>
```

### 3. Update `project.yml`

Add resources entry so XcodeGen includes the fonts directory in the bundle:
```yaml
resources:
  - path: BudahADE/Resources/Fonts
```

### 4. Rework `Theme.swift` Typography

Current functions all use `.system()`. Replace with explicit Geist font resolution:

```swift
// App UI — Geist
static func display(_ size: CGFloat) -> Font {
    .custom("Geist-Black", size: size)
}
static func headline(_ size: CGFloat) -> Font {
    .custom("Geist-Bold", size: size)
}
static func label(_ size: CGFloat) -> Font {
    .custom("Geist-Medium", size: size)
}
static func body(_ size: CGFloat) -> Font {
    .custom("Geist-Regular", size: size)
}
static func caption(_ size: CGFloat) -> Font {
    .custom("Geist-Regular", size: size)
}

// Terminal content — Menlo
static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom("Menlo", size: size).weight(weight)
}

// NSFont equivalents for AppKit contexts
static func geistFont(size: CGFloat, weight: String = "Regular") -> NSFont {
    NSFont(name: "Geist-\(weight)", size: size)
        ?? NSFont.systemFont(ofSize: size)
}
static func codeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: "Menlo", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}
```

Remove:
- `mono()` — replaced by `code()`
- `monoFont()` — replaced by `codeFont()`
- `uiFont()` — legacy, unused

### 5. Migrate Call Sites

#### Theme.mono() → split by context (~60 sites)

**App chrome → Geist tier:**
- Branch names, commit hashes, file paths → `Theme.label(size)` or `Theme.body(size)`
- Slash command names → `Theme.label(size)`
- Timestamps, metadata → `Theme.caption(size)`
- Chat messages, markdown inline → `Theme.body(size)`

**Terminal content → Theme.code():**
- `DiffModalView` diff line content → `Theme.code(size)`
- `CodeBlockView` → `Theme.code(size)`
- `CommitBarView` commit message input → `Theme.code(size)`

#### Inline .monospaced → split by context (~18 sites)

**App chrome (convert to Geist):**
- `TaskRailView` — branch badges, hash displays → `Theme.caption(size)`
- `TaskArchiveView` — metadata → `Theme.caption(size)`
- `SpecStripView` — status labels → `Theme.label(size)` or `Theme.caption(size)`
- `ActivityFeedView` — feed items → `Theme.body(size)`
- `BrowserTileView` — URL display → `Theme.caption(size)`

**Terminal content (convert to Theme.code):**
- `DiffModalView` section headers → `Theme.code(size)`
- `DiffView` line content → `Theme.code(size)`
- `FilePreviewView` file content → `Theme.code(size)`
- `RestoredTerminalView` fallback text → `Theme.code(size)`
- `ChangesListView` section headers → `Theme.code(size)`
- `StagingView` section headers → `Theme.code(size)`

### 6. Canvas TextFontFamily

The `.system` case in `TextFontFamily` should resolve to Geist (via `NSFont(name: "Geist-Regular")`). The `.monospaced` case stays as `NSFont.monospacedSystemFont`. No change to `.serif`.

### 7. Ghostty Terminal

No changes. `GhosttyConfig.swift` defaults to Menlo 13pt and reads user config. Completely separate from app typography.

## Verification

- Build succeeds with `xcodebuild build -scheme BudahADE -quiet`
- Launch app from DerivedData — all text renders in Geist (not SF Pro)
- Diff modal shows Menlo for code lines
- Code blocks in markdown render in Menlo
- Terminal still uses configured font (Menlo default)
- Canvas text with `.system` family renders in Geist
