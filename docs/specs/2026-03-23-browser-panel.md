# Browser Panel

## Overview

An embedded browser panel in Build Mode that serves as a localhost preview, general-purpose browser, and agent-controllable tool. Each task gets its own isolated dev server on a unique port, and any agent (Claude, Codex, or future) can control the browser through a local REST API.

---

## Core Concepts

### Tabbed View in Build Mode

The browser shares Build Mode's main content area with the terminal via a content-type toggle in the tab bar. The user switches between Terminal and Browser with `Cmd+Shift+B`. Only one is visible at a time — the active view gets the full area.

Both views use the same opacity-toggle pattern as existing terminal panels:
```swift
.opacity(isActive ? 1 : 0)
.allowsHitTesting(isActive)
```

WKWebView instances persist per-task — they are never destroyed on view switch. This preserves page state, scroll position, and navigation history automatically.

**Pop-out window:** A toolbar button opens the browser in a separate `NSPanel` window. A "dock back" button in the panel returns it to the main content area. True drag-to-detach is deferred — pop-out/dock-back covers the use case without the complexity of SwiftUI tear-off tabs or WKWebView re-parenting issues.

### Per-Task Port Isolation

Each task gets a deterministic localhost port:

- Task 1 → `localhost:3001`
- Task 2 → `localhost:3002`
- Task 3 → `localhost:3003`
- Base port: `3000`, offset by task index

The port badge displays on the **task card** in the task rail as a small pill (e.g., `:3001`) near the branch name. It only appears when a dev server is actively running.

### Task Lifecycle

| Event | Action |
|-------|--------|
| Task opens | Assign port → detect project → start dev server → load browser |
| Task switches | Browser swaps to that task's WKWebView (server already running, instant) |
| Task closes | Kill dev server process group → free port → cleanup WKWebView |

All task dev servers run simultaneously. Switching tasks is instant because both the server and the WKWebView are already warm.

---

## Project Detection

Convention-based auto-detection with manual override.

### Auto-Detect Rules

| Signal | Dev Command | Port Injection |
|--------|------------|----------------|
| `package.json` with `"dev"` script | `npm run dev` | `PORT={port}` env var |
| `vite.config.*` | `npx vite` | `--port {port}` flag |
| `next.config.*` | `npx next dev` | `--port {port}` flag |
| `Cargo.toml` with web framework | `cargo run` | Parse port from stdout |
| `manage.py` (Django) | `python manage.py runserver` | `{port}` arg |
| `go.mod` with net/http | `go run .` | Parse port from stdout |

Detection runs against the task's worktree root when a task opens. First matching rule wins.

### Manual Override

In BudahADE's project settings (not a repo config file), the user can specify:

- **Dev command**: e.g., `docker compose up`
- **Port**: e.g., `8080`
- **Path**: e.g., `/app` (appended to localhost URL)

Override takes precedence over auto-detection.

---

## URL Detection (Three Layers)

1. **Process stdout parsing** — Hook the dev server `Process` stdout pipe directly (before Ghostty) and watch for patterns: `localhost:\d+`, `127.0.0.1:\d+`, `ready on port \d+`, framework-specific messages. Auto-navigate the browser when detected. Uses "last URL wins" heuristic when multiple URLs appear.
2. **Agent sets URL via REST API** — The agent explicitly calls `POST /navigate` with the URL. Most reliable method.
3. **Manual entry** — URL bar in the browser chrome. User can always type a URL directly.

When multiple URLs are detected from stdout (e.g., dev server + API server + storybook), they populate a **detected URLs dropdown** in the browser chrome. The user can pick which one to display. The most recent URL is auto-loaded by default.

---

## Smart Reload

When the agent edits code:

1. Shared `FileWatcher` (extracted from existing `FileWatcher.swift` FSEvents pattern) detects saves in the task's worktree
2. Wait for dev server rebuild signal: parse stdout for framework-specific messages ("compiled successfully", "ready in", "built in") with a 3-second timeout fallback
3. Force-reload the WKWebView via `webView.reload()`

No reliance on HMR — deterministic reload after confirmed build completion. This is intentional: HMR behavior varies wildly across frameworks and versions. Explicit reload is predictable.

---

## Agent Browser Control Protocol

A local HTTP REST API on a configurable port (default: `localhost:9222`, configurable in project settings to avoid conflicts with Chrome DevTools Protocol). Any agent that can make HTTP requests can control the browser.

### HTTP Server Implementation

Built on `NWListener` (Network.framework) with manual HTTP/1.1 request parsing — zero external dependencies. The implementation is a thin `BrowserHTTPServer` class (~200 lines) that:
- Listens on the configured port
- Parses HTTP method, path, headers, and JSON body
- Routes to handler functions
- Returns JSON or binary (PNG) responses

The server is hidden behind a `BrowserAPIServerProtocol` so the implementation can be swapped later (e.g., to Hummingbird or GCDWebServer) without changing the handler logic.

### Single Port, Header-Routed

One API server instance serves all tasks. Requests include an `X-Task-Id` header to route to the correct WKWebView instance. This avoids port proliferation and is trivial for any HTTP client.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/capabilities` | List available actions and current state |
| `POST` | `/navigate` | Navigate to a URL |
| `GET` | `/screenshot` | Capture viewport or element screenshot (returns PNG) |
| `POST` | `/click` | Click element by CSS selector |
| `POST` | `/type` | Type text into element by selector |
| `GET` | `/dom` | Read DOM tree, element HTML, or query selector |
| `POST` | `/evaluate` | Execute JavaScript in page context |
| `GET` | `/console` | Read console log entries |
| `GET` | `/network` | Read network request log |
| `GET` | `/url` | Get current URL and page title |
| `POST` | `/reload` | Force reload the page |
| `POST` | `/select-element` | Enter element pick mode programmatically |

### Request/Response Format

All requests and responses are JSON. Example:

```
POST /navigate
X-Task-Id: <uuid>
{ "url": "http://localhost:3001/dashboard" }
→ { "ok": true, "url": "http://localhost:3001/dashboard", "title": "Dashboard" }

POST /click
X-Task-Id: <uuid>
{ "selector": "#submit-btn" }
→ { "ok": true, "element": "button#submit-btn" }

GET /screenshot?selector=.navbar
X-Task-Id: <uuid>
→ PNG binary (Content-Type: image/png)

GET /console?since=1706000000
X-Task-Id: <uuid>
→ { "entries": [{ "level": "error", "text": "...", "timestamp": 1706000101 }] }
```

---

## Element Pick → Chat

The signature interaction: user clicks an element in the browser, and its full context is injected into the active agent's input.

### Flow

1. User enters inspect mode via toolbar button or `Cmd+Shift+I`
2. JavaScript overlay (injected via `WKUserScript`, bypasses CSP since it runs as host app) highlights elements on hover
3. User clicks an element
4. BudahADE captures a **context bundle**:
   - CSS selector path using strategy: `#id` > `.class` chain > `nth-child` path
   - Outer HTML of the element (truncated to 2KB if massive)
   - Cropped screenshot: `WKWebView.takeSnapshot()` then crop to element's bounding rect (obtained via JS `getBoundingClientRect()`)
   - Computed styles (color, font, padding, margin, display, etc.)
   - Parent component context (nearest component boundary, surrounding HTML)
5. Context bundle is injected into the active agent's input area as a structured message
6. User types their instruction (e.g., "make this button larger") and sends

### Scope Limitations (v1)

- **No iframe support** — element picker operates on the top-level document only
- **No shadow DOM piercing** — web components with shadow roots show the host element only
- **Canvas/WebGL** — element picker detects `<canvas>` elements and falls back to screenshot-only mode (no DOM context). The canvas element itself is just a single DOM node; the visual content inside it is rendered as pixels, not DOM elements, so there's nothing meaningful to inspect beyond the canvas bounds and attributes.

### Injection Format

The context appears in the agent input as a collapsible block:

```
[Selected Element: button.submit-btn]
Selector: div.form > button.submit-btn
HTML: <button class="submit-btn">Submit</button>
Styles: { color: #fff, background: #3b82f6, padding: 8px 16px, font-size: 14px }
Parent: <div class="form">...</div>
[Screenshot attached]
```

---

## Browser Chrome (UI)

Minimal browser controls in the browser view:

- **URL bar** — editable, shows current URL, monospaced font, Enter to navigate
- **Back / Forward / Reload** — standard navigation buttons (reuse pattern from `BrowserTileView`)
- **Inspect mode toggle** — enters element-pick mode (`Cmd+Shift+I`)
- **Port indicator** — shows which task port is active (e.g., `:3001`)
- **Detected URLs dropdown** — when multiple localhost URLs are found, shows a picker
- **Pop-out button** — opens browser in separate `NSPanel` window
- **Dock-back button** — (shown only in pop-out window) returns browser to main content area

No visible DevTools panel. Agents access DevTools-level data (console, network, DOM) through the REST API. The agent _is_ the DevTools.

---

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `BudahADE/Browser/BrowserPanelView.swift` | Main browser view with WKWebView, URL bar, navigation controls. Reuses patterns from `BrowserTileView` (URL bar, back/forward/reload) but without `TileChrome` wrapper. |
| `BudahADE/Browser/BrowserState.swift` | `@Observable` state: current URL, title, loading, console entries, network log, detected URLs list. Extends `WebViewStore` pattern with console/network capture via `WKScriptMessageHandler`. |
| `BudahADE/Browser/BrowserAPIServer.swift` | HTTP REST API server using `NWListener`. Implements `BrowserAPIServerProtocol`. Routes requests by `X-Task-Id` header to correct `BrowserState`/WKWebView instance. |
| `BudahADE/Browser/BrowserAPIServerProtocol.swift` | Protocol defining server interface: `start(port:)`, `stop()`, `registerTask(_:)`, `unregisterTask(_:)`. Allows swapping HTTP implementation later. |
| `BudahADE/Browser/ElementPicker.swift` | Inspect mode: injects JS overlay via `WKUserScript`, captures context bundle (selector, HTML, screenshot crop, styles), packages for chat injection. |
| `BudahADE/Browser/DevServerManager.swift` | Per-task dev server lifecycle: project detection (scan for config files), process start/stop with process group management, port assignment, stdout pipe for URL detection. |
| `BudahADE/Browser/DevServerDetector.swift` | Pure function: given a worktree path, returns `DevServerConfig?` (command, port injection strategy). Separated from manager for testability. |
| `BudahADE/Browser/URLDetector.swift` | Parses `Process` stdout pipe data for localhost URL patterns. Emits detected URLs to `BrowserState`. |
| `BudahADE/Browser/SmartReloader.swift` | Monitors worktree for file changes (reuses `FileWatcher` FSEvents pattern), waits for build-ready signal from dev server stdout, triggers WKWebView reload. |
| `BudahADE/Browser/BrowserPopoutWindow.swift` | `NSPanel` window for pop-out mode. Hosts the same `BrowserPanelView`, communicates dock-back via notification. |

### Modified Files

| File | Change |
|------|--------|
| `TaskState.swift` | Add `assignedPort: Int`, `devServerProcess: Process?`, `browserState: BrowserState`, `devServerManager: DevServerManager?`. Add `startDevServer()` and `stopDevServer()` methods. |
| `TaskRailView.swift` | Add port badge pill (e.g., `:3001`) to task card, visible when `devServerManager?.isRunning == true`. |
| `WorkspaceView.swift` | Add content-type state (`.terminal` / `.browser`) to `terminalArea`. Toggle between `TerminalPanelView` and `BrowserPanelView` using opacity pattern. Wire `Cmd+Shift+B` notification. |
| `TerminalTabBar.swift` | Add browser/terminal toggle indicator or segmented control to the tab bar area. |
| `KeyboardShortcuts.swift` | Add `toggleBrowser` (`Cmd+Shift+B`), `toggleInspectMode` (`Cmd+Shift+I`). |
| `FileWatcher.swift` | Extract shared FSEvents debouncing into a reusable utility if `SmartReloader` needs different debounce timing (or reuse directly). |

### Dependencies

All Apple frameworks — zero external dependencies:

- **WebKit** (`WKWebView`, `WKUserScript`, `WKScriptMessageHandler`) — already used in `BrowserTileView`
- **Network** (`NWListener`, `NWConnection`) — for the REST API HTTP server
- **Foundation** (`Process`, `Pipe`, `FileHandle`) — for dev server management

### Dev Server Process Safety

Dev servers (webpack, vite, next) spawn child processes. Killing only the parent `Process` orphans children.

**Solution:** Process group management:
```swift
// On start: create new process group
process.qualityOfService = .utility
// The Process automatically gets its own pgid

// On stop: kill entire process group
let pgid = process.processIdentifier
kill(-pgid, SIGTERM)
// Fallback after 5s timeout:
kill(-pgid, SIGKILL)
```

**Cleanup safety nets:**
- `AppDelegate.applicationWillTerminate` — iterate all tasks, call `stopDevServer()`
- `AppDelegate.applicationDidFinishLaunching` — sweep ports 3001-3099, kill any orphaned processes from previous crash
- `TaskState.closeAllTerminals()` — already called on task close, add `stopDevServer()` call

---

## Keyboard Shortcuts

| Shortcut | Action | Notification |
|----------|--------|-------------|
| `Cmd+Shift+B` | Toggle Terminal ↔ Browser | `.toggleBrowser` |
| `Cmd+Shift+I` | Toggle inspect/element-pick mode | `.toggleInspectMode` |

---

## Implementation Phases

### Phase 1: Browser Panel MVP
_Goal: User can see localhost preview alongside terminal_

- [ ] **1.1 BrowserState** — `@Observable` class with URL, title, loading state, canGoBack/Forward. Extends `WebViewStore` pattern from `BrowserTileView`.
- [ ] **1.2 BrowserPanelView** — WKWebView + URL bar + nav buttons. Reuse `BrowserTileView` layout without `TileChrome`. Add port indicator and pop-out button.
- [ ] **1.3 Content toggle in WorkspaceView** — Add `contentMode: .terminal | .browser` state. Opacity-toggle between terminal panels and browser panel in `terminalArea`. Wire to `Cmd+Shift+B`.
- [ ] **1.4 Tab bar indicator** — Add terminal/browser toggle to `TerminalTabBar` so user has visual indicator of which view is active.
- [ ] **1.5 DevServerDetector** — Pure function: scan worktree for package.json/vite.config/next.config, return `DevServerConfig` (command string, port injection strategy).
- [ ] **1.6 DevServerManager** — Start/stop `Process` with process group management. Pipe stdout. Assign port `3000 + taskIndex`. Port-availability check before start.
- [ ] **1.7 Wire into TaskState** — Add `browserState`, `assignedPort`, `devServerManager`. Call `startDevServer()` from `startTerminal()`. Call `stopDevServer()` from `closeAllTerminals()`.
- [ ] **1.8 Port badge on task card** — Small pill in `TaskRailView` showing `:3001` when dev server is running.
- [ ] **1.9 Process cleanup safety** — AppDelegate termination cleanup + orphan sweep on launch.

### Phase 2: Intelligence Layer
_Goal: Browser auto-navigates and reloads on code changes_

- [ ] **2.1 URLDetector** — Parse `Process` stdout for localhost URL patterns. Emit to `BrowserState.detectedURLs`. Auto-navigate on first detection.
- [ ] **2.2 Detected URLs dropdown** — When `detectedURLs.count > 1`, show picker in browser chrome.
- [ ] **2.3 SmartReloader** — File watcher on worktree (reuse FSEvents pattern from `FileWatcher`). On change, parse dev server stdout for build-complete messages. Reload after confirmation or 3s timeout.

### Phase 3: Agent Control
_Goal: Agents can control the browser via HTTP_

- [ ] **3.1 BrowserAPIServerProtocol** — Define protocol: `start(port:)`, `stop()`, `registerTask(_:)`, `unregisterTask(_:)`, handler signatures for each endpoint.
- [ ] **3.2 BrowserHTTPServer** — `NWListener`-based HTTP/1.1 parser. Handle GET/POST, parse JSON body, route by path, return JSON/PNG responses.
- [ ] **3.3 Endpoint handlers** — Implement all endpoints: `/navigate`, `/screenshot`, `/click`, `/type`, `/dom`, `/evaluate`, `/console`, `/network`, `/url`, `/reload`, `/capabilities`.
- [ ] **3.4 Console/network capture** — Add `WKScriptMessageHandler` to intercept `console.log` and XHR/fetch calls via injected JS. Store in `BrowserState` ring buffer.
- [ ] **3.5 Wire API server lifecycle** — Start server when first task opens, stop when last task closes. Register/unregister tasks as they open/close.
- [ ] **3.6 API port configuration** — Add `browserAPIPort` to project settings with default `9222`.

### Phase 4: Interaction
_Goal: Full interactive browser-agent loop_

- [ ] **4.1 ElementPicker JS overlay** — Inject via `WKUserScript`: highlight on hover, capture click with selector/rect/styles. Send message to Swift via `WKScriptMessageHandler`.
- [ ] **4.2 Selector strategy** — `#id` > `.class` chain > `tag.class` > `nth-child` fallback. Pure Swift function, testable.
- [ ] **4.3 Screenshot cropping** — `WKWebView.takeSnapshot()` + crop to element bounding rect from JS `getBoundingClientRect()`.
- [ ] **4.4 Context bundle assembly** — Package selector + HTML + screenshot + styles + parent context into structured format.
- [ ] **4.5 Chat injection** — Insert context bundle into active agent's terminal input area as formatted text block with attached screenshot.
- [ ] **4.6 Canvas/WebGL fallback** — Detect `<canvas>` elements, skip DOM context, provide screenshot-only mode with element bounds.
- [ ] **4.7 Inspect mode toggle** — Wire `Cmd+Shift+I` to activate/deactivate picker. Show visual indicator in browser chrome when active.
- [ ] **4.8 Pop-out window** — `NSPanel` with `BrowserPanelView`. "Pop out" button in main view, "Dock back" button in panel. Communicate via notification.

---

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| REST API port configurable? | Yes, via project settings. Default `9222`. |
| Multiple browser tabs per task? | No. One preview per task in v1. `BrowserState` can hold an array later. |
| Element pick for canvas/WebGL? | Screenshot-only fallback. Canvas renders pixels, not DOM — nothing to inspect. |
| Persist navigation history? | Free — WKWebView instances live per-task, never destroyed on switch. |
