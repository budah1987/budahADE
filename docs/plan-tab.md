# tab-plan: Stability & Performance Recommendations

Generated after the March 2026 audit-refactor cycle. These are the remaining known issues on the `tab-plan` branch, ordered by impact.

---

## Stability Concerns

### 1. ConnectionSummaryManager — no subprocess timeout (HIGH)
**File:** `BudahADE/Agent/ConnectionSummaryManager.swift`

`process.waitUntilExit()` blocks forever if the Haiku subprocess hangs. The class caps concurrent summaries at 3 — three simultaneous hangs silently exhaust all slots and no new summaries can be generated until the app restarts.

**Fix:** 10-second timeout + `process.terminate()` on expiry.

```swift
// Replace waitUntilExit() with:
let deadline = Date().addingTimeInterval(10)
while process.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.1)
}
if process.isRunning { process.terminate() }
```

---

### 2. Git operations silently discard errors (MEDIUM)
**File:** `BudahADE/GitPanel/GitRepository.swift`

`stage()`, `commit()`, and `checkout()` do not throw. A failed `git add` or `git commit` returns silently — the user sees no error. Stage/commit/checkout all use `Process` directly and ignore the termination status.

**Fix:** Convert to `throws`, check `process.terminationStatus != 0`, surface errors to the Git panel UI.

---

### 3. Worktree creation failure is console-only (MEDIUM)
**File:** `BudahADE/Task/GitWorktreeManager.swift` (or equivalent)

If `git worktree add` fails (e.g., path conflict, disk full), the task is still created and proceeds as if the worktree exists. The failure is logged to console only.

**Fix:** Propagate worktree creation failure to the task creation flow and block task creation on failure.

---

### 4. Fragile error enum comparison in HarnessMiddleware (LOW-MEDIUM)
**File:** `BudahADE/Agent/HarnessMiddleware.swift`, line ~649

```swift
session.status == .error("")  // fragile — only matches empty-string errors
```

This comparison will miss real agent error states where the associated value is non-empty (e.g., `.error("exit code 1")`). A session stuck with a non-empty error string will not be caught by this guard.

**Fix:** Use a pattern match:
```swift
if case .error = session.status { ... }
```

---

## Performance Bottlenecks

### 1. Git panel polling at 1.5s interval (EASY WIN)
**File:** `BudahADE/GitPanel/GitRepository.swift`

The refresh timer fires every 1.5 seconds and executes 4+ shell-out commands (`git status`, `git log`, `git diff`, `git branch`). While the git panel is open this creates continuous background process spawning.

**Recommendation:** Increase interval to 3–5 seconds. The UX cost is imperceptible; the CPU cost reduction is significant.

---

### 2. PlanChatView.swift at 1,400+ LOC (MEDIUM)
**File:** `BudahADE/Plan/PlanChatView.swift`

At 1,433 lines, this is the largest SwiftUI view in the codebase. SwiftUI evaluates the entire view body when any observed state changes. Inline subviews at this scale mean chat scroll, keyboard events, and tab switches all trigger full re-evaluation.

**Recommendation:** Extract the message list, input bar, and role picker into separate `View` structs. Each becomes an independent diffing boundary. Estimated 30–50% reduction in re-evaluation surface.

---

### 3. ConnectionSummaryManager blocks thread pool threads (MEDIUM)
**File:** `BudahADE/Agent/ConnectionSummaryManager.swift`

Each `waitUntilExit()` call occupies a thread pool thread for the duration of the subprocess. With 3 concurrent slots, this can hold 3 threads blocked on I/O. Under load (many connections being summarized), this competes with Swift Concurrency's cooperative thread pool.

**Recommendation:** Migrate to `AsyncStream` or `NotificationCenter`-based process termination observation instead of blocking `waitUntilExit()`.

---

### 4. Activity feed (fixed this session)
Capped at 200 entries in `AgentSession.swift`. No further action needed.

---

## Deferred Specs (tracked in `docs/specs/`)

| Spec | Status | Priority |
|------|--------|----------|
| `chatmessage-parser-hardening.md` | Written, not implemented | High — AnyCodable dictionary navigation is fragile |
| `connection-summary-manager-audit.md` | Written, not implemented | High — covers timeout + thread issues above |
| `spec-assembler-watcher-audit.md` | Written, not implemented | Medium — SpecAssembler silent write failure |

---

## What Was Completed (March 2026 Audit)

- `AppStatePersistence.swift` — `createDirectory` try? → do/catch
- `PlanCanvasState.swift` — image copy + spec write try? → do/catch
- `PlanChatState.swift` — race condition in `persistConversation()` fixed (capture session before Task.sleep)
- `SessionIdResolver` — extracted from TaskState, now shared utility
- `TaskState.swift` — dead code removed (50 lines), duplicate title parsing consolidated
- `GitRepository.swift` — `@MainActor` added, timer closure fixed for actor isolation
- `AgentSession.swift` — activity feed capped at 200 entries (3 sites)
- `HarnessMiddleware.swift` — 6 write operations converted from try? to do/catch
- All changes committed, merged to `tab-plan`, pushed to GitHub
