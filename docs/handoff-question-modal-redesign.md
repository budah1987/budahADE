# Handoff: Question Modal System — Redesign for Apple-grade UX

## Context

BudahADE displays interactive prompts from CLI agents (choice, confirm, multi-question) as modals above the chat input. The current implementation works but is heavy-handed: every block type funnels through one `QuestionStepperSheet`, which is the wrong tool for single-question and confirm cases. A senior designer at Apple would call out the over-uniformity, the wasted chrome, the lost affordances, and the absence of motion choreography between states.

This handoff explains what's currently in place, what's wrong with it, and what should be built instead. The new design must feel **inevitable** — like the only correct shape for the interaction.

---

## What I built (and why it's not good enough)

### The architecture
1. **Unified queue.** All interactive marker types (`choice`, `confirm`, `questions`) get parsed into `[DetectedQuestionItem]` via `InteractiveBlock.asQueueItems(messageId:)` in `BudahADE/Agent/AgentSession.swift`.
2. **Stable IDs.** `AgentSession.stableQuestionId(question:messageId:)` hashes content + message ID so dedup works across re-parses.
3. **Single display path.** `PlanChatView.swift` body shows `questionQueueSheet` whenever `questionQueue.isEmpty == false`. The old marker-block switch (OptionButtonsSheet / ConfirmButton paths) was deleted.
4. **Persistent dedup.** `questionQueueSeenIds` is NOT cleared on submit/dismiss — prevents already-answered questions from re-appearing on the next streaming-complete scan.
5. **Dynamic growth.** `QuestionStepperSheet` got `.onChange(of: questions.count)` to expand its `@State answers` array, plus `.contentTransition(.numericText())` on the counter and `.transition(.opacity.combined(with: .scale))` on dots.

### Why it falls short

**1. Confirms are dressed up like multi-step quizzes.**
A yes/no confirmation now appears with "Question 1 of 1", a single dot, a "Submit" button, and a custom text field. The interaction is *click yes or no*. Everything else is noise. Compare to a native macOS NSAlert — two buttons, a question, a default action. That's the energy this should have.

**2. Choices lost their soul.**
The old `OptionButtonsSheet` carried:
- `recommendedIndex` — the agent's pick is visually highlighted
- `showApproveAndBuild` — when the choice produces a spec-ready answer, an "Approve and Build" button appears (calls `handleApprove()`)
- Rich option parsing — `"Plan Mode only — embed in PlanChatView container"` splits on ` — ` into `text` + `description`
- `questionBeforeMarker()` context — the prose paragraph before the marker

I funnel everything into `DetectedQuestionItem(question:, suggestions: [String])`. All four affordances above are now dead. The queue items carry strings, not structure.

**3. Single questions feel costumed.**
"Question 1 of 1" + step dots + Back/Next chrome is appropriate when there are 5 questions and the user needs progress signal. For one question, the chrome is cosplay. A senior Apple designer would ask: *what is the dot doing? what is the counter doing? if there's nothing to count, why is it there?*

**4. No motion choreography between states.**
When the queue transitions from 1 → 2 questions, the entire layout should re-stage: the single-question card should grow into a stepper, the dots should materialize, the "Submit" button should morph into "Next." Right now there's only `withAnimation(.easeOut(duration: 0.25))` on the count change. SwiftUI handles the rest implicitly, which means it's mediocre by default.

**5. No mid-stream detection.**
Questions only appear when `session.status` transitions out of `.streaming`. If an agent writes a long message, asks a question halfway through, then keeps talking for 30 seconds, the user stares at the streaming text. The agent has finished writing the *question*, but the modal won't appear until the *whole message* is done. This is the single biggest UX miss.

**6. Lost the visual distinction between block types.**
A confirm is a snap decision. A choice is picking from a menu. A multi-question is a structured interview. By forcing them through one component, I made all three feel like the same thing. They're not.

**7. The seen-IDs mechanism is fragile.**
It's keyed on hash(question + messageId). If the agent re-asks a rephrased version of a question the user dismissed, it'll come back with a new ID. If the agent re-asks the *exact* same text, it won't. This is the wrong primitive — dedup should be intent-based, not content-based. (Realistically: track by message ID + block index, not question text.)

---

## What to build instead

### Design principles (non-negotiable)

1. **The shape adapts to the content, not the other way around.** A confirm looks like a confirm. A single question looks like a card. Multiple questions look like a stepper. The component you render is determined by what's in the queue at this moment.

2. **One queue, many faces.** The unified queue + dedup is the right architecture — keep it. What changes is the *renderer*. Think of it like a SwiftUI `Group` that switches `View` types based on queue shape.

3. **Motion is structural, not decorative.** When the queue grows from 1 to 2 items, the modal must morph — same `matchedGeometryEffect` namespace, the question text and accent stay anchored, dots/counter materialize in. The user should never feel a modal close and reopen.

4. **Every pixel earns its place.** No "Question 1 of 1." No empty dot rows. No "Back" button when there's nowhere to go back to.

5. **Apple-level polish on the small things.** `.contentTransition(.numericText())` on the counter. `.symbolEffect(.bounce)` on confirmation. Spring animations with thoughtful damping (`response: 0.45, dampingFraction: 0.82`). Cmd+Enter as a true "accept the obvious answer" shortcut.

### Architecture

```
AgentSession.InteractiveBlock          (parsed from markers)
            │
            ▼
       QueuedPrompt                    (NEW: structured, not flattened)
            │
            ▼
   @State promptQueue: [QueuedPrompt]  (in PlanChatView)
            │
            ▼
       PromptDispatcher view           (NEW: chooses renderer by queue shape)
            │
   ┌────────┼─────────┬──────────────┐
   ▼        ▼         ▼              ▼
ConfirmCard ChoiceCard QuestionCard  StepperCard
(1 confirm) (1 choice) (1 question)  (2+ items)
```

### Data model (replace `DetectedQuestionItem` for queue use)

```swift
// In AgentSession.swift — sits alongside InteractiveBlock
struct QueuedPrompt: Identifiable, Equatable {
    let id: String                    // hash(messageId + blockIndex), NOT question text
    let messageId: UUID
    let blockIndex: Int               // position within parseInteractiveMarkers result
    let kind: Kind
    let question: String              // QUESTION: attribute
    let context: String               // questionBeforeMarker(), trimmed
    
    enum Kind: Equatable {
        case confirm
        case choice(options: [ChoiceOption], recommendedIndex: Int?, isSpecReady: Bool)
        case question(suggestions: [String])
        case questionSeries([SubQuestion])
    }
    
    struct ChoiceOption: Equatable, Identifiable {
        let id: Int
        let text: String              // before " — "
        let description: String       // after " — ", may be empty
    }
    
    struct SubQuestion: Equatable, Identifiable {
        let id: String                // hash within parent
        let question: String
        let context: String
        let suggestions: [String]
    }
}
```

**Why structured, not flattened:** the renderer for a `.choice` needs `recommendedIndex` and `isSpecReady`. The renderer for a `.confirm` needs nothing but the question text. Forcing them into a shared `[String]` strips the information each renderer needs.

### Stable IDs done right

```swift
// IDs are based on POSITION in the conversation, not content.
// A rephrased re-ask is the same intent → same ID via blockIndex.
static func promptId(messageId: UUID, blockIndex: Int) -> String {
    "\(messageId.uuidString):\(blockIndex)"
}
```

Drop content hashing. Position is the right primitive — it survives rephrasing and prevents the seen-set from leaking across distinct questions that happen to share text.

### Renderer dispatch

```swift
struct PromptDispatcher: View {
    let queue: [QueuedPrompt]
    let onAnswer: (QueuedPrompt, String) -> Void
    let onMultiAnswer: ([String]) -> Void
    let onDismiss: () -> Void
    let onApproveAndBuild: () -> Void
    
    @Namespace private var morph
    
    var body: some View {
        Group {
            if queue.count >= 2 {
                StepperCard(queue: queue, namespace: morph, ...)
            } else if let first = queue.first {
                switch first.kind {
                case .confirm:
                    ConfirmCard(prompt: first, namespace: morph, ...)
                case .choice(let options, let rec, let specReady):
                    ChoiceCard(prompt: first, options: options, recommended: rec,
                               showApproveAndBuild: specReady, namespace: morph, ...)
                case .question(let suggestions):
                    QuestionCard(prompt: first, suggestions: suggestions, namespace: morph, ...)
                case .questionSeries:
                    StepperCard(queue: queue, namespace: morph, ...)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: queue.count)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: queue.first?.id)
    }
}
```

`@Namespace + matchedGeometryEffect` is how you get the question text to *fly* from `ConfirmCard` into the first slot of `StepperCard` when a second prompt arrives. This is the choreography Apple ships in apps like Reminders and Mail.

### What each card looks like

**ConfirmCard** — yes/no, no counter, no dots. Two buttons side by side, recommended action highlighted. Cmd+Enter accepts. Escape dismisses. Period.

```swift
HStack(spacing: 12) {
    Text(prompt.question)
        .font(.system(size: 14, weight: .medium))
        .matchedGeometryEffect(id: "question-\(prompt.id)", in: namespace)
    Spacer()
    Button("No") { onAnswer(prompt, "No") }
        .buttonStyle(.bordered)
    Button("Yes") { onAnswer(prompt, "Yes") }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
}
```

**ChoiceCard** — restore the old `OptionButtonsSheet` affordances. Recommended option has a subtle accent ring. Each row shows `text` in primary color and `description` in secondary. "Approve & Build" appears as a separate prominent action when `isSpecReady`. Numbered keyboard shortcuts (1–9) select instantly.

**QuestionCard** — the question, an optional context paragraph, suggestion chips, a custom text field. NO counter. NO dots. Submit button. That's it.

**StepperCard** — the current `QuestionStepperSheet`, but cleaned up. Counter and dots only render when `queue.count >= 2`. Use `matchedGeometryEffect` so when the queue *grew* from a `QuestionCard`, the question text smoothly slides into the first stepper position while dots fade in from below.

### Mid-stream question detection (the big win)

Add this to `PlanChatView.swift`:

```swift
.onChange(of: session?.currentStreamingText) { _, text in
    guard let text, let session else { return }
    // Find COMPLETE interactive blocks (have both open and close markers).
    // Incomplete blocks are ignored — they may still be streaming.
    let completeText = text.prefix(through: text.range(of: "<!-- /INTERACTIVE -->", options: .backwards)?.upperBound ?? text.startIndex)
    guard !completeText.isEmpty else { return }
    
    // Parse only the completed portion. Add new prompts to the queue.
    ingestPrompts(from: String(completeText), messageId: session.streamingMessageId)
}
```

Pair this with the existing `.onChange(of: session?.status)` handler that does the final scan when streaming completes. Now questions appear *as soon as the agent finishes writing them*, not when the entire message is done.

**Critical:** the parser must only consider blocks where the closing `<!-- /INTERACTIVE -->` has been received. Half-streamed blocks are discarded.

### Motion details (the "Apple" part)

| Moment | Animation |
|---|---|
| Queue 0 → 1 (any kind) | Card slides up from below + fades in. `.spring(response: 0.5, dampingFraction: 0.85)` |
| Queue 1 → 2 (e.g. confirm → stepper) | Question text uses `matchedGeometryEffect` to fly into stepper's first slot. Counter fades in with `.contentTransition(.numericText())`. Dots materialize one by one with 0.04s stagger via `.transition(.scale.combined(with: .opacity))` |
| User answers in stepper, advances | Current dot turns green with `.symbolEffect(.bounce)`, content cross-fades to next question |
| Queue drains to 0 | Card slides down + fades. Input area slides up to fill space |
| Cmd+Enter accept | Brief 0.95 → 1.0 scale pulse on the recommended button before action fires |

Use a single `@Namespace` at the `PromptDispatcher` level. Every card gets it as a parameter. Question text, accent color bar, and dismiss button all participate via `matchedGeometryEffect`.

### Cmd+Enter behavior

- `ConfirmCard`: accept (Yes)
- `ChoiceCard`: accept recommended option (or first if none recommended)
- `QuestionCard`: submit current answer if non-empty
- `StepperCard`: same as QuestionCard for current step

This is a single rule, applied uniformly: **Cmd+Enter advances the obvious next action**.

### Spec-ready handling

`ChoiceCard` needs `showApproveAndBuild` and `onApproveAndBuild` wired up. The current code path for this exists in `PlanChatView.handleApprove()` — preserve it. When the queue contains a single choice and `state.looksLikeSpec(lastMessage)` is true, the card shows the secondary action.

For multi-step stepper or other card types, "Approve and Build" doesn't apply.

---

## Files to touch

- `BudahADE/Agent/AgentSession.swift`
  - Add `QueuedPrompt` struct + `Kind` enum
  - Add `InteractiveBlock.asQueuedPrompt(messageId:blockIndex:isSpecReady:)` method
  - Replace `stableQuestionId` with position-based `promptId(messageId:blockIndex:)`
  - Keep `parseInteractiveMarkers`, `questionBeforeMarker`, `isLastBlockSelfAnswered`
  - Remove `asQueueItems` (and `DetectedQuestionItem` if nothing else uses it — check `detectQuestionSeries` callers)

- `BudahADE/Plan/PlanChatView.swift`
  - Replace `questionQueue: [DetectedQuestionItem]` with `promptQueue: [QueuedPrompt]`
  - Replace `questionQueueSheet` with `PromptDispatcher`
  - Add `.onChange(of: session?.currentStreamingText)` for mid-stream detection
  - Update `.onChange(of: session?.status)` to use the new ingest function
  - Remove `QuestionStepperSheet` from this file (move to its own file as `StepperCard`)
  - Wire Cmd+Enter to dispatcher's "accept obvious action"

- `BudahADE/Plan/Prompts/` (NEW directory)
  - `PromptDispatcher.swift` — the renderer switch + `@Namespace`
  - `ConfirmCard.swift`
  - `ChoiceCard.swift` (port from existing `OptionButtonsSheet`)
  - `QuestionCard.swift`
  - `StepperCard.swift` (port from existing `QuestionStepperSheet`, drop counter/dots when count==1)

- `BudahADE/Agent/AgentPrompts.swift`
  - The `interactiveMarkerInstructions()` text is fine. No changes needed unless you want to add a `SPEC_READY:true` attribute on choice markers.

## Tests to write

1. `QueuedPromptTests.swift` — assert that re-parsing the same message produces stable IDs (same `messageId + blockIndex`)
2. `PromptDispatcherTests.swift` — snapshot test the four card types at queue counts 1 and 2+
3. `MidStreamDetectionTests.swift` — feed a streaming text fragment with one complete block and one half-streamed block; verify only the complete one is ingested

## Verification

1. Build: `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
2. Launch from DerivedData
3. **Single confirm:** agent emits `<!-- INTERACTIVE:confirm QUESTION:Proceed? -->` → ConfirmCard appears with two buttons. Cmd+Enter sends "Yes". Esc dismisses.
4. **Single choice:** agent emits a 3-option choice with `RECOMMENDED:2` → ChoiceCard appears, option 2 highlighted. Pressing `2` selects it. Cmd+Enter accepts.
5. **Single question:** agent emits a `questions` block with one bold question → QuestionCard appears, NO dots, NO "1 of 1" counter.
6. **Stacking:** while ConfirmCard is showing, agent sends another message with a choice → ConfirmCard morphs into StepperCard, dots animate in, counter reads "Question 1 of 2", original question text flies into the first slot via `matchedGeometryEffect`.
7. **Mid-stream:** agent writes 200 lines of text, asks a question, then writes 200 more lines → question modal appears as soon as the closing `<!-- /INTERACTIVE -->` is streamed, NOT when the whole message is done.
8. **Dedup:** answer a question, agent sends a new message, the answered question never re-appears.
9. **Spec-ready:** a choice arrives during a planning conversation when `looksLikeSpec` is true → ChoiceCard shows "Approve & Build" button. Clicking it triggers `handleApprove()`.

---

## What "good" looks like

When you show this to a senior designer at Apple, they should:

1. Not notice the modal exists for confirms — it should feel like part of the chat.
2. Watch the morph from ConfirmCard to StepperCard and ask "how did you do that transition?"
3. Try Cmd+Enter and have it do exactly what they expected.
4. Notice that single-question cards have no chrome and approve.
5. See the streaming detection work and say "oh that's clever."

If any of those checks fail, the implementation isn't done.

## Constraints

- **Do not regress** the dedup behavior or the stacking. These work in the current build.
- **Do not edit** `AgentPrompts.swift` interactive marker instructions unless adding `SPEC_READY:true` is necessary.
- **Do not** keep the old `OptionButtonsSheet` and `ConfirmButton` and `QuestionStepperSheet` alongside the new cards. Delete them. One way to do something.
- **Build with** `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5` and launch from DerivedData. Don't use Xcode IDE.
- **Never edit** `project.pbxproj`. Run `xcodegen generate` after creating new files.
- **The `Plan/Prompts/` directory** is new. After creating it and the files, run `xcodegen generate` so they get picked up.
