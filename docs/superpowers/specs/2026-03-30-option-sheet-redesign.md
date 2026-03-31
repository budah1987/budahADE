# Option Sheet Redesign

**Date:** 2026-03-30
**Branch:** Conversation-Planner
**Status:** Design approved

## Summary

Redesign the option sheet (the slide-up panel that appears when the AI presents structured choices) with two auto-switching variants: **compact** for simple title-only options and **detailed** for options with descriptions/pros/cons. Full keyboard navigation, BudahADE dark/terra cotta aesthetic.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layout switching | Auto-detect from content | If any option has a description, use detailed layout; otherwise compact |
| Polish level | Full Claude-level interaction | Badges, arrow-key nav, focus ring, keyboard hints, skip button |
| Aesthetic | BudahADE native | Dark surfaces, terra cotta accent, existing Theme tokens |
| Custom response | Always-visible text field | Stays at bottom, polished with pencil icon |

## Data Model Changes

### DetectedOption (AgentSession.swift)

Add a `description` field to carry sub-content parsed from between option headings:

```swift
struct DetectedOption: Identifiable {
    let id: Int
    let label: String       // "1", "A", etc.
    let text: String        // Option title: "Session-Based (Traditional)"
    let description: String // Sub-lines: "Username/password → server validates...\nPros: Simple..."
}
```

### detectOptions() Changes

When `foundOptionHeadings` is true, collect non-empty lines between one option heading and the next (or end of content) as that option's `description`. Lines starting with `Pros:`, `Cons:`, `-`, `•` all become part of the description. Empty `description` = compact variant.

## Compact Variant

Triggers when: all options have empty `description`.

### Layout

```
┌─────────────────────────────────────────────────┐
│ [accent top border — 1.5px, rgba(196,120,92,0.4)]
│                                                   │
│  Question text goes here?                    [✕]  │
│  ─────────────────────────────────────────────    │
│  [A]  Session-Based (Traditional)           →     │
│  ·····················································│
│  [B]  Token-Based (JWT)                     →     │
│  ·····················································│
│  [C]  OAuth / Third-Party Provider          →     │
│                                                   │
│  [✎]  Something else... _______________           │
│                                                   │
│  ↑↓ navigate · Enter select · Esc skip   [Skip]  │
└───────────────────────────────────────────────────┘
```

### Row Anatomy

- **Badge:** 22×22px rounded rect (radius 5), `rgba(255,255,255,0.06)` bg, 1px `rgba(255,255,255,0.1)` border, monospace label in terra cotta (`#c4785c`)
- **Text:** 13px system font, `#e5e5e5`
- **Arrow:** `→` character, 12px, hidden by default, appears on hover/focus in terra cotta
- **Separator:** 0.5px `rgba(255,255,255,0.05)` between rows

### Focus/Hover States

- **Hover:** row bg `rgba(255,255,255,0.04)`, badge bg shifts to `rgba(196,120,92,0.15)` with `rgba(196,120,92,0.3)` border
- **Focused (keyboard):** row bg `rgba(255,255,255,0.06)`, same badge treatment as hover

## Detailed Variant

Triggers when: any option has non-empty `description`.

### Layout

```
┌─────────────────────────────────────────────────┐
│ [accent top border]                               │
│                                                   │
│  Which approach interests you?               [✕]  │
│  ─────────────────────────────────────────────    │
│  ┃ [A]  Session-Based (Traditional)          →    │
│  ┃  Username/password → server validates...       │
│  ┃  Pros: Simple    Cons: Doesn't scale           │
│  ·····················································│
│  │ [B]  Token-Based (JWT)                    →    │
│  │  Server returns signed JWT token...            │
│  │  Pros: Stateless  Cons: Hard to revoke         │
│  ·····················································│
│  │ [C]  OAuth / Third-Party Provider         →    │
│  │  Delegate auth to external provider...         │
│  │  Pros: No passwords  Cons: Third-party dep     │
│                                                   │
│  [✎]  Something else... _______________           │
│                                                   │
│  ↑↓ navigate · Enter select · Esc skip   [Skip]  │
└───────────────────────────────────────────────────┘
```

### Card Anatomy

- **Left border:** 2px, transparent default, `rgba(196,120,92,0.3)` on hover, solid `#c4785c` on focus
- **Header row:** badge + title (13px semibold) + arrow indicator
- **Description:** 12px, `#999`, left-indented 32px (past badge)
- **Pros/Cons:** 11px inline, green (`#5a9a6b`) for Pros label, red (`#c45c5c`) for Cons label, `#777` for text
- **Separator:** 0.5px between cards

### Description Parsing

The description field is raw text. The view parses it for display:
- Lines starting with `Pros:` or `**Pros:**` → green-labeled inline
- Lines starting with `Cons:` or `**Cons:**` → red-labeled inline
- Other lines → plain description text in `#999`

## Shared Elements

### Sheet Container

- Background: `Theme.sidebar` (`#1a1a1e`)
- Top border: 1.5px `rgba(196,120,92,0.4)` — the terra cotta accent line
- Padding: 14px horizontal, 10px vertical
- No corner radius (anchored to bottom edge)

### Header

- Question text: 13px, `Theme.textPrimary`, up to 4 lines
- Dismiss button: 22px circle, `Theme.hoverFill` bg, `✕` in `Theme.textMuted`, hover brightens

### Custom Text Field

- Row styled with pencil icon (`✎`) in muted color
- Background: `rgba(255,255,255,0.025)`
- Rounded rect (6px radius)
- Placeholder: "Something else..." in `Theme.textMuted`
- On submit (Enter): sends custom text and dismisses

### Keyboard Hints Footer

- Top border: 0.5px `rgba(255,255,255,0.06)`
- Left: `↑↓ navigate · Enter select · Esc skip` in 11px monospace, `Theme.textMuted`
- Right: "Skip" button — 11px, `Theme.textSecondary`, subtle border, hover brightens

### Keyboard Navigation

| Key | Action |
|-----|--------|
| ↑ / ↓ | Move focus between option rows |
| Enter | Select focused option |
| 1-9 / A-Z | Direct select by label |
| Esc | Dismiss sheet (if custom field focused, unfocus first) |
| Tab | Move focus to custom text field |

### Focus State Tracking

- `@State private var focusedIndex: Int? = nil` — tracks which option row has keyboard focus
- Arrow keys cycle through `0..<options.count`
- On appear, `focusedIndex` starts at `nil` (no pre-selection)
- Pressing ↑ from index 0 wraps to last; ↓ from last wraps to 0

## Files Changed

| File | Change |
|------|--------|
| `BudahADE/Agent/AgentSession.swift` | Add `description` to `DetectedOption`, update `detectOptions()` to collect sub-lines |
| `BudahADE/Plan/PlanChatView.swift` | Rewrite `OptionButtonsSheet` and `OptionSheetRow`, add `DetailedOptionCard`, keyboard nav, hints footer |

No new files needed — this is a rewrite of existing components in PlanChatView.swift.
