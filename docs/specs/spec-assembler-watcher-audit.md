# Audit: SpecAssembler + SpecWatcher

**Status:** Findings only — do not execute changes without separate approval
**Files:**
- `BudahADE/Spec/SpecAssembler.swift` (166 LOC)
- `BudahADE/Spec/SpecWatcher.swift` (99 LOC)

---

## Context Note

`SpecAssembler.assemble()` takes a `PlanCanvasState` as its primary input — it collects tagged canvas elements and assembles them into a markdown spec file. On this branch (conversation-based plan mode), **the canvas is not the active workflow.** This means the current SpecAssembler is likely not on the active path for spec output on this branch.

If spec assembly is happening on this branch, it is either:
1. Driven by a different code path that isn't `SpecAssembler.assemble()`, OR
2. Not yet wired up (spec panel shows but assembly is pending)

This audit should be read with that caveat. The critical-path question for this branch is: **how does plan conversation output reach the spec document?** That likely involves `SpecAssembler` being called with canvas elements that represent conversation output, or a separate assembly path not yet identified.

---

## SpecAssembler Findings

### 1. No distinction between "no spec" and "empty spec"

`assemble()` returns `nil` in two different situations:
- No tagged elements found (`tagged.isEmpty` at line 20)
- File write failed (line 72)

The caller cannot distinguish between "nothing to assemble yet" and "assembly failed." If the write fails silently (permissions error, disk full), the return value is the same as a legitimate empty state.

**Risk: 🟡 Medium** — on the critical path. Caller sees `nil` and likely shows no spec, with no diagnostic.

### 2. Silent write failure

`SpecAssembler.swift:68–73`
```swift
do {
    try markdown.write(toFile: path, atomically: true, encoding: .utf8)
    return path
} catch {
    return nil  // ← silent failure, no log
}
```

If the write fails, the assembled spec is discarded and the function returns `nil`. No error is logged. The caller has no way to surface this to the user.

**Risk: 🔴 High** — same category as the file I/O issues in Batch 1.

### 3. Silent content extraction failures

`extractTileContent` at lines 131 and 145:
```swift
case .markdown(let path):
    return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    // ↑ returns "" if file doesn't exist or can't be read

case .terminal(let panelId, let agent):
    if let output = try? String(contentsOfFile: outputPath, encoding: .utf8), !output.isEmpty {
        return output
    }
    return "<!-- \(agent.displayName) agent output pending -->"
```

If a markdown tile's file is missing or unreadable, its content is silently omitted from the spec. The section exists in the output but is blank. No error, no placeholder.

**Risk: 🟡 Medium**

### 4. Partial session handling

`SpecAssembler` has no concept of session state — it reads from whatever is currently in the canvas at the time of assembly. 

**For interrupted sessions:** If a plan conversation is interrupted mid-flow, any canvas elements that were tagged before the interruption are included as-is. Elements that hadn't been created yet are simply absent. There is no "incomplete" marker in the output — the spec reads as if it were fully assembled.

This means an interrupted session produces a silently truncated spec with no indication that it's partial.

**Risk: 🟡 Medium** — particularly relevant on this branch where plan conversations are the primary workflow.

### 5. Canvas coupling concern (branch-specific)

The assembler's signature:
```swift
static func assemble(canvas: PlanCanvasState, taskName: String, worktreePath: String, ...) -> String?
```

On the conversation-based branch, there's no natural `PlanCanvasState` to pass unless one is maintained as a side-effect of conversation output. If spec assembly needs to work from conversation messages rather than canvas elements, this entire assembler needs a different entry point.

**This is a design gap, not a bug.** But it means spec assembly may be dormant on this branch regardless of the pipeline.

---

## SpecWatcher Findings

### 1. Cleanup behavior on task switch

`SpecWatcher.stopWatching()`:
```swift
func stopWatching() {
    timer?.invalidate()
    timer = nil
}
```

Timer is properly invalidated. The closure captures `self` weakly, so no retain cycle. If `stopWatching()` is NOT called by the owner (e.g., a task switch doesn't tear down the watcher), the timer continues firing every 2 seconds — but since `self` is weak and the watcher may be deallocated, the closure no-ops safely.

**Cleanup is correct IF `stopWatching()` is called.** Whether it's always called on task switch requires checking the call sites — not investigated here.

### 2. File removal detection bug

`SpecWatcher.swift:72–74`
```swift
if lastContents.keys.count != currentContents.keys.count {
    changed = true
}
```

This detects count changes, not set changes. If one spec file is deleted and a different one is added in the same polling interval (same count, different keys), the change is not detected. The watcher continues showing the old content.

**Risk: 🟢 Low** — this edge case (atomic file swap) is unlikely in practice. A simple fix would be `Set(lastContents.keys) != Set(currentContents.keys)`.

### 3. Silent file read failures

`SpecWatcher.swift:59`
```swift
guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
```

If a spec file exists (returned by `SpecParser.findSpecFiles`) but can't be read, it's silently skipped. The watcher continues with whatever was previously loaded. No log, no state update.

**Risk: 🟡 Low** — unlikely unless there's a permissions issue mid-session.

### 4. Adaptive polling

Rapid polling (0.5s for 10s after a change) is a good pattern. No issues found here.

The `scheduleTimer(interval:)` method calls `timer?.invalidate()` before creating a new timer, which prevents double-firing. Clean implementation.

### 5. Memory: `lastContents` not cleared on stop

`stopWatching()` does not clear `lastContents`. If the watcher is stopped and restarted (e.g., on task re-open), it resumes with stale content comparisons from the previous session. This means on first poll after restart, it may not detect changes that occurred while it was stopped.

**Risk: 🟡 Low** — could cause a one-poll delay in detecting spec changes after task re-open.

---

## Summary Table

| Issue | File | Risk | Action |
|-------|------|------|--------|
| Silent write failure | SpecAssembler.swift:68–73 | 🔴 High | Fix in a future batch |
| No nil distinction (empty vs error) | SpecAssembler.swift:20, 72 | 🟡 Medium | Consider Result<String, Error> return type |
| Silent content extraction failures | SpecAssembler.swift:131, 145 | 🟡 Medium | Add logging |
| Partial session not marked | SpecAssembler.swift | 🟡 Medium | Design decision needed |
| Canvas coupling (branch-specific) | SpecAssembler.swift | Design gap | Needs separate spec |
| File removal detection (count vs set) | SpecWatcher.swift:72–74 | 🟢 Low | Simple fix |
| Silent file read failure | SpecWatcher.swift:59 | 🟡 Low | Add logging |
| lastContents not cleared on stop | SpecWatcher.swift | 🟢 Low | Clear in stopWatching() |

---

## Open Question for Amir

On this branch, how does plan conversation output reach the spec panel? Does the spec panel currently show anything during an active plan conversation, or is spec assembly not yet wired up for the conversation-based flow? This determines whether the SpecAssembler issues above are currently on the critical path.
