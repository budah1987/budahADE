# Phase 1: Compose Bar + Terminal Tabs

```
Risk:     LOW
Status:   NOT STARTED
Progress: [....................] 0%
Depends:  Phase 0
Blocks:   Nothing
```

---

## Objective
Add the TextInput compose bar (from Figma) and terminal tabs for multiple conversations.

## Internal Roadmap

### Step 1.1 — ComposePanel (NSTextView)
```
Duration: ~3 hrs
Risk:     LOW — already prototyped in Budah
```
**Reference**: `Budah/Sources/Panels/ComposePanel.swift`

- [ ] Create `Terminal/ComposePanel.swift`
- [ ] NSView container with two sections:
  - [ ] **Controls bar**: model selector (left) + effort bar graph (right)
  - [ ] **Input area**: liquid glass surface + NSTextView
- [ ] Liquid glass effect:
  - [ ] macOS 26+: `.glassEffect()`
  - [ ] macOS 15: `.ultraThinMaterial` fallback
- [ ] Key handling:
  - [ ] Enter → `panel.sendText(text + "\r")`, clear input
  - [ ] Cmd+Shift+Enter → insert literal newline
  - [ ] Escape → clear input
- [ ] Font: SF Mono 13px for input, SF Pro 11px for controls
- [ ] Verify: type text, Enter sends to terminal

### Step 1.2 — Model Selector Accordion
```
Duration: ~2 hrs
Risk:     LOW
```
- [ ] "opus 4.6 >" text + caret right icon
- [ ] Click → expands dropdown with:
  - [ ] Opus 4.6 (1M context, most capable) — radio
  - [ ] Sonnet 4.6 (200K, fast) — radio
  - [ ] Haiku 4.5 (200K, instant) — radio
- [ ] Hover state: `rgba(255,255,255,0.05)` pill background
- [ ] Cmd+M shortcut to toggle
- [ ] Selection updates the label text
- [ ] Verify: accordion opens, selection persists

### Step 1.3 — Effort Bar Graph
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] 3 ascending bars (3px wide, 5/8/11px tall)
- [ ] + "Max" / "Med" / "Low" label
- [ ] Click cycles: Low (1 bar) → Medium (2 bars) → Max (3 bars)
- [ ] Color: `#938d8d` default
- [ ] Hover state: pill background
- [ ] Verify: click cycles through levels

### Step 1.4 — Terminal Tab Bar
```
Duration: ~3 hrs
Risk:     MEDIUM — tab/session management
```
- [ ] Create `Terminal/TerminalTabBar.swift`
- [ ] Tab data model: id, title, status (active/thinking/idle), surface reference
- [ ] Visual per tab:
  - [ ] Status dot (green=active, yellow=thinking, none=shell)
  - [ ] Title text (e.g. "Claude — Rate Limiter")
  - [ ] Close button (x) on hover
- [ ] Active tab: `rgba(255,255,255,0.05)` pill bg
- [ ] Inactive tabs: just text, muted color
- [ ] "+" button at end
- [ ] Shortcuts: Cmd+T new, Cmd+W close, Cmd+Shift+[/] cycle
- [ ] Each tab owns its own TerminalSurface
- [ ] Verify: create tabs, switch between, close individual tabs

### Step 1.5 — Integration
```
Duration: ~1 hr
Risk:     LOW
```
- [ ] Stack in terminal panel: TabBar → TerminalContent → ComposeBar
- [ ] Tab switching swaps active TerminalSurface
- [ ] ComposeBar always sends to active tab's terminal
- [ ] Verify: full flow works end-to-end

---

## Verification Checklist
- [ ] Multiple terminal tabs render correctly
- [ ] Switching tabs shows different terminal content
- [ ] Compose bar sends text to active tab
- [ ] Model accordion opens and closes
- [ ] Effort bars cycle through 3 levels
- [ ] Cmd+T creates new tab
- [ ] Cmd+W closes current tab
- [ ] Hover states appear on model selector, effort selector, inactive tabs

---

## Figma Reference
- **TextInput component**: `335:4402` in Dealio V2 file
- **GLASS effect**: radius 89, no strokes, near-transparent fill
- **Controls**: SF Pro 11px, `#938d8d`
- **Input**: SF Mono 13px, white text on `rgba(110,110,110,0.2)` glass
- **Hover**: `rgba(255,255,255,0.05)` pill, 99px radius
