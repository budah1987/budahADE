# Audit: ConnectionSummaryManager Failure Handling

**Status:** Documentation only — canvas not on active path for refactor/cleanup branch
**File:** `BudahADE/Plan/ConnectionSummaryManager.swift` (89 LOC)

---

## What It Does

`ConnectionSummaryManager` generates short text labels for edges (connections) between canvas tiles. When a connection is rendered and has no cached summary, it spawns a `claude` subprocess with `--model haiku --max-turns 1` and the first 2000 characters of the source tile's text output as the prompt. The result is cached on the `TileConnection` object.

---

## Failure Scenarios

### 1. API call fails (process throws on launch)

**Code path:** `ConnectionSummaryManager.swift:78–86`
```swift
do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(...) ?? ""
    return output.isEmpty ? String(prompt.prefix(200)) : output
} catch {
    return String(prompt.prefix(200))  // ← fallback
}
```

**Behavior:** Falls back to the first 200 characters of the prompt (the truncated tile text). The connection gets a label, but it's raw text rather than a summary. No error is logged. No retry.

### 2. Process hangs / never exits

**Behavior:** `process.waitUntilExit()` is a blocking call with no timeout. If the `claude` binary hangs (e.g., waiting for network, stuck on auth), the Task thread blocks indefinitely.

Since `runHaikuSummary` is `nonisolated`, this blocking does NOT block the MainActor or the UI. However:
- The `inFlightIds` set retains the connection ID indefinitely
- `activeSummaryCount` stays elevated
- That connection slot is never released, reducing the effective concurrent cap from 3
- The `pendingQueue` drains more slowly as in-flight slots are consumed by hung processes
- Over multiple hangs, all 3 slots can be occupied by hung processes, stopping all future summaries

**No timeout is implemented.**

### 3. Empty output (claude returns nothing)

**Behavior:** Falls back to `String(prompt.prefix(200))`. Same as failure case — labeled with raw text.

### 4. Connection deleted while in-flight

**Code path:** `ConnectionSummaryManager.swift:44–46`
```swift
guard canvas?.connections.contains(where: { $0.id == id }) == true else { continue }
```

**Behavior:** Handled correctly in `drainQueue`. If a connection is removed while its summary is in flight, `completeSummary` still fires but the `canvas.connections.firstIndex(where:)` lookup at line 27 finds nothing and silently no-ops. Clean.

### 5. Canvas deallocated while summary in-flight

**Code path:** `canvas` is a `weak var`. At line 27–30, if canvas is nil, the `if let canvas` guard fails and the summary result is discarded. No crash. The in-flight slot is freed.

**Behavior:** Clean — weak reference pattern handles this correctly.

---

## Does Failure Block Canvas Operations?

**No.** Canvas operations are fully independent of summary generation.

- `resolvedSummary` returns `nil` while in-flight — the connection renders with no label
- Canvas drag, resize, tile interaction, and conversation flow all continue unaffected
- The connection label simply stays blank until a summary arrives (or the hang is resolved)

The only user-visible degradation is: connection labels don't appear or appear as raw text.

---

## Timeout Values

**There are none.** `process.waitUntilExit()` has no timeout parameter. Swift's `Process` API has no built-in timeout.

To add a timeout, the pattern would be:
```swift
let timeoutTask = Task {
    try await Task.sleep(for: .seconds(10))
    process.terminate()
}
defer { timeoutTask.cancel() }
process.waitUntilExit()
```

This is not currently implemented.

---

## Retry Behavior

**There is none.** Failed or empty summaries fall back to the truncated prompt text and cache that as the label. No retry is queued.

---

## Risk Summary

| Scenario | Impact on canvas | User visible | Risk |
|----------|-----------------|-------------|------|
| Process launch fails | None | Raw text label | 🟢 Low |
| Process hangs | Slot leak, queue stalls | Labels stop appearing after 3 hangs | 🟡 Medium |
| Empty output | None | Raw text label | 🟢 Low |
| Connection deleted in-flight | None | Clean | 🟢 Safe |
| Canvas deallocated in-flight | None | Clean | 🟢 Safe |

---

## Recommendations (not approved for execution)

1. **Add a 10-second timeout** to `runHaikuSummary` — terminate the process and return fallback if it exceeds the limit. This eliminates the hung-slot leak.
2. **Log failures** — even a `print("[ConnectionSummaryManager] ⚠️ ...")` would help diagnose issues during development.
3. **Low priority overall** — canvas/connections are not on the active workflow for this branch. This can wait until canvas is back in the critical path.
