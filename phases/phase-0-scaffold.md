# Phase 0: Scaffold + libghostty Integration

```
Risk:     HIGH
Status:   NOT STARTED
Progress: [....................] 0%
Blocks:   ALL other phases
```

---

## Objective
Create a new Xcode project that renders a single working terminal using libghostty's Metal pipeline. This is the foundation everything else builds on.

## Internal Roadmap

### Step 0.1 — Xcode Project Setup
```
Duration: ~30 min
Risk:     LOW
```
- [ ] Create macOS App (Swift, SwiftUI lifecycle)
- [ ] Bundle ID: `com.budah.ade`, target macOS 14.0
- [ ] Set app name: "BudahADE"
- [ ] Set dark mode appearance as default

### Step 0.2 — Link libghostty
```
Duration: ~1 hr
Risk:     MEDIUM — framework linking can be finicky
```
- [ ] Copy `GhosttyKit.xcframework` from `/Users/amir/Documents/Cursor Projects/Budah/`
- [ ] Add as embedded framework in Xcode
- [ ] Create `BudahADE-Bridging-Header.h` importing `ghostty.h`
- [ ] Verify: project builds with no linker errors

### Step 0.3 — Theme Foundation
```
Duration: ~30 min
Risk:     LOW
```
- [ ] Create `Shared/Theme.swift`
- [ ] Define color palette (see tokens below)
- [ ] Set window background to `#13111a`
- [ ] Verify: app launches with correct dark background

### Step 0.4 — GhosttyAppManager (Singleton)
```
Duration: ~3-4 hrs
Risk:     HIGH — most complex extraction
```
**Reference**: `Budah/Sources/GhosttyTerminalView.swift` lines 631-1000

- [ ] Create `Terminal/GhosttyAppManager.swift`
- [ ] Call `ghostty_init()` on app launch
- [ ] Create `ghostty_config_t` and load user's Ghostty config files
- [ ] Set up `ghostty_runtime_config_s` with callbacks:
  - [ ] `wakeup` — schedule redraw on main thread
  - [ ] `action` — handle ghostty actions (clipboard, title changes)
  - [ ] `read_clipboard` / `write_clipboard` — NSPasteboard integration
  - [ ] `close_surface` — cleanup
- [ ] Create `ghostty_app_t` via `ghostty_app_new()`
- [ ] Set up CVDisplayLink tick loop calling `ghostty_app_tick()`
- [ ] Verify: no crashes on init, tick loop runs

### Step 0.5 — TerminalSurface
```
Duration: ~3-4 hrs
Risk:     HIGH — Metal/IOSurface pipeline
```
**Reference**: `Budah/Sources/GhosttyTerminalView.swift` lines 2002-2700

- [ ] Create `Terminal/TerminalSurface.swift`
- [ ] Create `ghostty_surface_t` from the app
- [ ] Set up IOSurface-backed CALayer for Metal rendering
- [ ] Handle resize via `ghostty_surface_set_size()`
- [ ] Handle focus via `ghostty_surface_set_focus()`
- [ ] Verify: surface creates without crash

### Step 0.6 — TerminalSurfaceView (NSView Host)
```
Duration: ~2-3 hrs
Risk:     HIGH — input forwarding + focus management
```
**Reference**: `GhosttySurfaceScrollView` in `GhosttyTerminalView.swift` line 4908+

- [ ] Create `Terminal/TerminalSurfaceView.swift` (NSView subclass)
- [ ] Host the surface's Metal CALayer
- [ ] Forward key events → `ghostty_surface_key()` / `ghostty_surface_text()`
- [ ] Forward mouse events → `ghostty_surface_mouse_*`
- [ ] Handle paste via `ghostty_surface_text()`
- [ ] Manage IOSurface lifecycle on resize
- [ ] Preserve `ensureFocus` retry pattern from cmux
- [ ] Verify: view renders terminal content

### Step 0.7 — SwiftUI Bridge
```
Duration: ~1 hr
Risk:     MEDIUM — SwiftUI/AppKit focus fights
```
- [ ] Create `Terminal/TerminalPanelView.swift` (NSViewRepresentable)
- [ ] Launch shell process on appear
- [ ] Wire up in `BudahADEApp.swift` as the main view
- [ ] Verify: full-window terminal, type commands, see output

### Step 0.8 — GhosttyConfig Reader
```
Duration: ~1 hr
Risk:     LOW — standalone file
```
**Reference**: `Budah/Sources/GhosttyConfig.swift` (entire file, ~480 lines)

- [ ] Create `Terminal/GhosttyConfig.swift`
- [ ] Read `~/.config/ghostty/config`
- [ ] Parse font family, font size, theme colors
- [ ] Apply to terminal surface
- [ ] Verify: terminal uses user's Ghostty font and colors

---

## Verification Checklist
Run these manually after all steps complete:

- [ ] App launches without crashes
- [ ] Terminal renders with correct Ghostty font
- [ ] Terminal colors match user's Ghostty theme
- [ ] Type `ls` → see output
- [ ] Type `echo hello` → see "hello"
- [ ] Cmd+V paste works
- [ ] Cmd+C copy works (select text first)
- [ ] Resize window → terminal reflows correctly
- [ ] Retina display renders crisp text (if applicable)

---

## Design Tokens for This Phase

```swift
// Shared/Theme.swift
import SwiftUI

enum Theme {
    static let appBg         = Color(red: 0.075, green: 0.067, blue: 0.102)  // #13111a
    static let textPrimary   = Color(red: 0.878, green: 0.863, blue: 0.929)  // #e0dced
    static let textSecondary = Color(red: 0.584, green: 0.565, blue: 0.659)  // #9590a8
    static let textMuted     = Color(red: 0.420, green: 0.400, blue: 0.502)  // #6b6680
    static let terracotta    = Color(red: 0.769, green: 0.471, blue: 0.361)  // #c4785c
    static let success       = Color(red: 0.420, green: 0.620, blue: 0.420)  // #6b9e6b
    static let warning       = Color(red: 0.769, green: 0.659, blue: 0.361)  // #c4a85c
    static let info          = Color(red: 0.483, green: 0.424, blue: 0.710)  // #7b6cb5
    static let error         = Color(red: 0.894, green: 0.353, blue: 0.353)  // #e45a5a
}
```

---

## Blockers & Escape Hatches

| Blocker | Escape Hatch |
|---------|-------------|
| GhosttyKit.xcframework won't link | Check architecture (arm64 vs x86_64), re-download from Budah's build script |
| `ghostty_init()` crashes | Check if Ghostty is installed, config file exists |
| Metal rendering blank | Verify IOSurface creation, check CALayer frame matches view |
| Focus not working (can't type) | Ensure NSView becomes firstResponder, check `acceptsFirstResponder` |
| CVDisplayLink not ticking | Verify main thread dispatch, check display link callback |
