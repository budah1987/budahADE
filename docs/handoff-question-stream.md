```
## Handoff Context

### What we're building
BudahADE's interactive question/option modal system — the harness that detects when a CLI agent asks questions, presents them as UI modals (option sheets, question steppers, confirm buttons), and sends answers back. Goal: make the question→answer loop fast, accurate, and resilient to staggered agent output.

### Where things stand
- **Done**: Agent prompt updated to emit `QUESTION:` and `RECOMMENDED:` attributes in interactive markers. Parser extracts these. All three modal types (OptionButtonsSheet, QuestionStepperSheet, ConfirmButton) now display the embedded question text. Cmd+Enter selects recommended option for choice blocks. Multi-block queue advances through blocks in a single message. Persistent question queue accumulates staggered questions across messages.
- **In progress**: The `/simplify` code review was interrupted before the three review agents ran. The review should still be done — there's likely redundant state (`questionQueueAnswers` is declared but unused by the queue sheet), duplicate parsing calls, and the interaction between `answeredBlockCount` (block queue) and `questionQueue` (persistent queue) needs clarity.
- **Not yet tested**: The full end-to-end flow with the new marker format (agents haven't seen the updated prompt yet in a real session).

### Key decisions made
- Agent embeds question text directly in markers (`QUESTION:`) rather than harness guessing from message text
- One interactive block per decision — multiple decisions = multiple blocks
- `RECOMMENDED:N` (1-indexed) declares which option the agent recommends
- Cmd+Enter is the universal "accept recommendation" shortcut (choice + confirm)
- Questions accumulate in a persistent queue — new questions append silently without disrupting the current modal
- Modals only appear after streaming completes (gated on `status != .streaming`)
- Self-answered questions suppressed via `isLastBlockSelfAnswered()` (>40 chars after last close marker)
- GitRepository.init moved to async background thread to prevent AG::precondition_failure crashes

### Important files & paths
- `BudahADE/Agent/AgentSession.swift` — `InteractiveBlock` enum, `parseInteractiveMarkers()`, `parseMarkerAttributes()`, `questionBeforeMarker()`, `isLastBlockSelfAnswered()`, `DetectedQuestionItem`
- `BudahADE/Plan/PlanChatView.swift` — modal rendering, `currentMarkerBlock()`, `advanceBlock()`, `questionQueueSheet`, Cmd+Enter handler, `.onChange` for queue population
- `BudahADE/Plan/AgentPrompts.swift:246-280` — `interactiveMarkerInstructions()` with the marker format spec
- `BudahADE/GitPanel/GitRepository.swift` — `GitSnapshot` struct, `refreshAsync()`

### Constraints & gotchas
- `questionQueueAnswers` state variable exists but is unused — the QuestionStepperSheet manages its own answers internally. Either wire it or remove it.
- The `answeredBlockCount` block queue and `questionQueue` persistent queue are two separate mechanisms that can conflict — choice blocks use the block queue, question blocks use the persistent queue. Clarify ownership.
- `parseInteractiveMarkers()` is called multiple times per render (in `currentMarkerBlock`, in Cmd+Enter handler, in ConfirmButton). Should be cached per message.
- The `.onChange(of: session?.status)` that populates the question queue fires on ALL status transitions, not just streaming→done. The guard helps but it's fragile.
- Build command: `xcodebuild build -scheme BudahADE -quiet` / launch from DerivedData
- SourceKit diagnostics are noisy false positives — ignore "Cannot find type" errors, trust the build.

### Next steps
1. Run the `/simplify` review — launch the three review agents (reuse, quality, efficiency) against the full diff
2. Remove `questionQueueAnswers` if confirmed unused, or wire it to preserve answers across re-renders
3. Cache `parseInteractiveMarkers()` result per message ID to avoid redundant parsing
4. Unify or clearly separate the block queue vs persistent queue — document which modal type uses which
5. Test end-to-end: start a plan conversation, verify modals show correct question text, Cmd+Enter works, staggered questions accumulate
6. Consider: should the block queue (`answeredBlockCount`) also feed into the persistent queue for consistency?
```
