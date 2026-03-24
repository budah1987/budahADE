# Phase 3: Contextual Connections — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a visual connection graph between canvas tiles that enables automatic context flow — upstream tile outputs are summarized and injected into downstream agent conversations.

**Architecture:** Connections are stored as `TileConnection` structs in `PlanCanvasState.connections`. Arrow rendering uses a SwiftUI `Canvas` draw layer (same pattern as SmartGuidesOverlay). Each tile type conforms to `TileOutputProvider` to expose its content. Summary generation spawns Haiku subprocesses via the existing `CLISubprocessManager`, with max 3 concurrent. Context is prepended to chat tile prompts automatically.

**Tech Stack:** SwiftUI, Swift Concurrency, CLISubprocessManager (existing), Canvas draw API (existing pattern)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `BudahADE/Plan/TileConnection.swift` | Create | `TileConnection` model, `TileOutput` enum, `TileOutputProvider` protocol |
| `BudahADE/Plan/ConnectionsLayer.swift` | Create | Arrow rendering via SwiftUI Canvas, port overlays, drag-to-connect interaction |
| `BudahADE/Plan/ConnectionSummaryManager.swift` | Create | Summary generation (Haiku subprocess), caching, concurrency throttle (max 3) |
| `BudahADE/Plan/PlanCanvasState.swift` | Modify | Add `connections` array, CRUD methods, cleanup on element removal |
| `BudahADE/Plan/PlanCanvasView.swift` | Modify | Insert ConnectionsLayer between grid and content |
| `BudahADE/Plan/CanvasPersistence.swift` | Modify | Add connections to CanvasSnapshot |
| `BudahADE/Plan/TileViews/ChatTileView.swift` | Modify | Prepend connected context to prompts in sendMessage() |
| `BudahADE/Plan/ContextManifest.swift` | Modify | Add connections section to plan-context.md |
| `BudahADETests/TileConnectionTests.swift` | Create | Model tests, output provider tests, persistence round-trip |
| `BudahADETests/ConnectionSummaryTests.swift` | Create | Summary cache tests, invalidation, concurrency |

---

### Task 1: TileConnection Data Model + TileOutputProvider Protocol

**Files:**
- Create: `BudahADE/Plan/TileConnection.swift`
- Test: `BudahADETests/TileConnectionTests.swift`

- [ ] **Step 1: Write the failing test for TileConnection model**

```swift
// TileConnectionTests.swift
import XCTest
@testable import BudahADE

final class TileConnectionTests: XCTestCase {

    func testTileConnectionCreation() {
        let src = UUID()
        let dst = UUID()
        let conn = TileConnection(sourceId: src, destinationId: dst)
        XCTAssertEqual(conn.sourceId, src)
        XCTAssertEqual(conn.destinationId, dst)
        XCTAssertNil(conn.cachedSummary)
        XCTAssertEqual(conn.sourceVersion, 0)
    }

    func testTileConnectionCodableRoundTrip() throws {
        let conn = TileConnection(sourceId: UUID(), destinationId: UUID())
        let data = try JSONEncoder().encode(conn)
        let decoded = try JSONDecoder().decode(TileConnection.self, from: data)
        XCTAssertEqual(conn.id, decoded.id)
        XCTAssertEqual(conn.sourceId, decoded.sourceId)
        XCTAssertEqual(conn.destinationId, decoded.destinationId)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: FAIL — TileConnection not defined

- [ ] **Step 3: Implement TileConnection model**

```swift
// BudahADE/Plan/TileConnection.swift
import Foundation

// MARK: - TileConnection

struct TileConnection: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceId: UUID
    let destinationId: UUID
    var cachedSummary: String?
    var summaryTimestamp: Date?
    var sourceVersion: Int

    init(
        id: UUID = UUID(),
        sourceId: UUID,
        destinationId: UUID,
        cachedSummary: String? = nil,
        summaryTimestamp: Date? = nil,
        sourceVersion: Int = 0
    ) {
        self.id = id
        self.sourceId = sourceId
        self.destinationId = destinationId
        self.cachedSummary = cachedSummary
        self.summaryTimestamp = summaryTimestamp
        self.sourceVersion = sourceVersion
    }
}

// MARK: - TileOutput

enum TileOutput {
    case text(String)
    case conversation([ChatMessage])
    case image(URL)
    case url(URL)
    case terminalOutput(String)

    /// Flatten to a string for summary generation
    var textRepresentation: String {
        switch self {
        case .text(let s): return s
        case .conversation(let msgs):
            return msgs.suffix(10).map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }.joined(separator: "\n")
        case .image(let url): return "[Image: \(url.lastPathComponent)]"
        case .url(let url): return "[URL: \(url.absoluteString)]"
        case .terminalOutput(let s): return s
        }
    }
}

// MARK: - TileOutputProvider

protocol TileOutputProvider {
    func currentOutput() -> TileOutput?
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Write tests for TileOutput textRepresentation**

```swift
// Add to TileConnectionTests.swift
func testTileOutputTextRepresentation() {
    let textOutput = TileOutput.text("Hello world")
    XCTAssertEqual(textOutput.textRepresentation, "Hello world")

    let urlOutput = TileOutput.url(URL(string: "https://example.com")!)
    XCTAssertTrue(urlOutput.textRepresentation.contains("example.com"))

    let imageOutput = TileOutput.image(URL(fileURLWithPath: "/tmp/test.png"))
    XCTAssertTrue(imageOutput.textRepresentation.contains("test.png"))
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add BudahADE/Plan/TileConnection.swift BudahADETests/TileConnectionTests.swift
git commit -m "feat: add TileConnection model, TileOutput enum, TileOutputProvider protocol"
```

---

### Task 2: TileOutputProvider Conformance for All Tile Types

**Files:**
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add `tileOutput(for:)` method
- Test: `BudahADETests/TileConnectionTests.swift` — add output tests

This task adds a method on PlanCanvasState that resolves TileOutput for any element ID by inspecting its kind. This avoids making individual tile views conform to the protocol (they're SwiftUI views, not data providers).

- [ ] **Step 1: Write failing tests for tile output resolution**

```swift
// Add to TileConnectionTests.swift
@MainActor
func testTileOutputForStickyNote() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let id = canvas.addTile(type: .stickyNote, at: .zero)
    // Sticky notes start empty — output should be nil or empty text
    let output = canvas.tileOutput(for: id)
    // Sticky note with no content returns nil
    XCTAssertNil(output)
}

@MainActor
func testTileOutputForMarkdown() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let tmpFile = NSTemporaryDirectory() + "test-\(UUID()).md"
    try! "# Hello\nWorld".write(toFile: tmpFile, atomically: true, encoding: .utf8)
    let id = canvas.addTile(type: .markdown(path: tmpFile), at: .zero)
    let output = canvas.tileOutput(for: id)
    if case .text(let content) = output {
        XCTAssertTrue(content.contains("Hello"))
    } else {
        XCTFail("Expected .text output for markdown tile")
    }
    try? FileManager.default.removeItem(atPath: tmpFile)
}

@MainActor
func testTileOutputForChatAgent() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let id = canvas.addChatTile(agent: .ideator, at: .zero)
    guard let element = canvas.findElement(id),
          case .tile(.chatAgent(let sessionId, _)) = element.kind,
          let session = canvas.chatSessions[sessionId] else {
        XCTFail("Chat tile not created"); return
    }
    session.addUserMessage("test prompt")
    let output = canvas.tileOutput(for: id)
    if case .conversation(let msgs) = output {
        XCTAssertEqual(msgs.count, 1)
    } else {
        XCTFail("Expected .conversation output")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: FAIL — `tileOutput(for:)` not defined

- [ ] **Step 3: Implement tileOutput(for:) on PlanCanvasState**

Add this method to `PlanCanvasState.swift` in the `// MARK: - Queries` section (after `allTiles`, around line 482):

```swift
// MARK: - Tile Output

/// Resolve the current output of a tile by its element ID
func tileOutput(for elementId: UUID) -> TileOutput? {
    guard let element = findElement(elementId),
          case .tile(let tileType) = element.kind else { return nil }

    switch tileType {
    case .stickyNote:
        // Sticky note content is stored in the element title
        let text = element.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : .text(text)

    case .markdown(let path):
        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(content)

    case .chatAgent(let sessionId, _):
        guard let session = chatSessions[sessionId],
              !session.messages.isEmpty else { return nil }
        return .conversation(session.messages)

    case .image(let path):
        return .image(URL(fileURLWithPath: path))

    case .browser(let url):
        guard let url else { return nil }
        return .url(url)

    case .terminal(let panelId, _):
        // Terminal output not accessible programmatically (Ghostty surface) — return nil
        // MCP tool `get_connected_context()` handles terminal context separately (Phase 4+)
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Plan/PlanCanvasState.swift BudahADETests/TileConnectionTests.swift
git commit -m "feat: add tileOutput(for:) — resolves TileOutput per tile type"
```

---

### Task 3: Connection CRUD on PlanCanvasState

**Files:**
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add `connections` array, add/remove/query methods, cleanup on element removal
- Test: `BudahADETests/TileConnectionTests.swift`

- [ ] **Step 1: Write failing tests for connection CRUD**

```swift
// Add to TileConnectionTests.swift
@MainActor
func testAddConnection() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let a = canvas.addTile(type: .stickyNote, at: .zero)
    let b = canvas.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
    let connId = canvas.addConnection(sourceId: a, destinationId: b)
    XCTAssertEqual(canvas.connections.count, 1)
    XCTAssertEqual(canvas.connections.first?.sourceId, a)
    XCTAssertEqual(canvas.connections.first?.destinationId, b)
    XCTAssertNotNil(connId)
}

@MainActor
func testRemoveConnection() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let a = canvas.addTile(type: .stickyNote, at: .zero)
    let b = canvas.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
    let connId = canvas.addConnection(sourceId: a, destinationId: b)
    canvas.removeConnection(connId)
    XCTAssertTrue(canvas.connections.isEmpty)
}

@MainActor
func testConnectionsCleanedUpOnElementRemoval() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let a = canvas.addTile(type: .stickyNote, at: .zero)
    let b = canvas.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
    let c = canvas.addTile(type: .stickyNote, at: CGPoint(x: 600, y: 0))
    canvas.addConnection(sourceId: a, destinationId: b)
    canvas.addConnection(sourceId: b, destinationId: c)
    XCTAssertEqual(canvas.connections.count, 2)
    canvas.removeElement(b)
    // Both connections involving b should be removed
    XCTAssertTrue(canvas.connections.isEmpty)
}

@MainActor
func testNoDuplicateConnections() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let a = canvas.addTile(type: .stickyNote, at: .zero)
    let b = canvas.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
    canvas.addConnection(sourceId: a, destinationId: b)
    canvas.addConnection(sourceId: a, destinationId: b) // duplicate
    XCTAssertEqual(canvas.connections.count, 1)
}

@MainActor
func testIncomingConnections() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let a = canvas.addTile(type: .stickyNote, at: .zero)
    let b = canvas.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
    let c = canvas.addTile(type: .stickyNote, at: CGPoint(x: 600, y: 0))
    canvas.addConnection(sourceId: a, destinationId: c)
    canvas.addConnection(sourceId: b, destinationId: c)
    let incoming = canvas.incomingConnections(for: c)
    XCTAssertEqual(incoming.count, 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: FAIL — connections property, addConnection, removeConnection not defined

- [ ] **Step 3: Add connections array and CRUD methods to PlanCanvasState**

Add `@Published var connections: [TileConnection] = []` to the published properties section (after line 8).

Add these methods in a new `// MARK: - Connections` section after the `// MARK: - Queries` section:

```swift
// MARK: - Connections

@discardableResult
func addConnection(sourceId: UUID, destinationId: UUID) -> UUID {
    // Prevent duplicates
    if connections.contains(where: { $0.sourceId == sourceId && $0.destinationId == destinationId }) {
        return connections.first(where: { $0.sourceId == sourceId && $0.destinationId == destinationId })!.id
    }
    // Prevent self-connections
    guard sourceId != destinationId else { return UUID() }

    let conn = TileConnection(sourceId: sourceId, destinationId: destinationId)
    connections.append(conn)
    didMutate()
    return conn.id
}

func removeConnection(_ id: UUID) {
    connections.removeAll { $0.id == id }
    didMutate()
}

func incomingConnections(for elementId: UUID) -> [TileConnection] {
    connections.filter { $0.destinationId == elementId }
}

func outgoingConnections(for elementId: UUID) -> [TileConnection] {
    connections.filter { $0.sourceId == elementId }
}

/// Invalidate cached summary for connections from a specific source
func invalidateConnectionSummaries(sourceId: UUID) {
    for i in connections.indices where connections[i].sourceId == sourceId {
        connections[i].cachedSummary = nil
        connections[i].sourceVersion += 1
    }
}
```

Also modify `removeElement(_:)` (around line 238) to clean up connections. Add this at the **top** of the method body, before any existing cleanup:

```swift
// Clean up connections involving this element
connections.removeAll { $0.sourceId == id || $0.destinationId == id }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Plan/PlanCanvasState.swift BudahADETests/TileConnectionTests.swift
git commit -m "feat: connection CRUD on PlanCanvasState with cleanup on element removal"
```

---

### Task 4: Persist Connections in CanvasSnapshot

**Files:**
- Modify: `BudahADE/Plan/CanvasPersistence.swift` — add connections to CanvasSnapshot
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — include connections in snapshot/restore
- Test: `BudahADETests/TileConnectionTests.swift`

- [ ] **Step 1: Write failing test for connection persistence round-trip**

```swift
// Add to TileConnectionTests.swift
func testConnectionSnapshotCodable() throws {
    let conn = TileConnection(sourceId: UUID(), destinationId: UUID(), cachedSummary: "test summary", sourceVersion: 3)
    let snapshot = CanvasSnapshot(
        elements: [],
        zoom: 1.0,
        panOffsetWidth: 0,
        panOffsetHeight: 0,
        chatMessages: [:],
        connections: [conn]
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: data)
    XCTAssertEqual(decoded.connections.count, 1)
    XCTAssertEqual(decoded.connections.first?.cachedSummary, "test summary")
    XCTAssertEqual(decoded.connections.first?.sourceVersion, 3)
}

func testConnectionSnapshotBackwardCompatible() throws {
    // Old snapshots without connections field should decode with empty connections
    let json = """
    {"elements":[],"zoom":1,"panOffsetWidth":0,"panOffsetHeight":0,"chatMessages":{}}
    """
    let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: json.data(using: .utf8)!)
    XCTAssertTrue(decoded.connections.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — CanvasSnapshot doesn't have connections parameter

- [ ] **Step 3: Add connections to CanvasSnapshot**

Modify `CanvasPersistence.swift`:

```swift
struct CanvasSnapshot: Codable {
    let elements: [CanvasElement]
    let zoom: CGFloat
    let panOffsetWidth: CGFloat
    let panOffsetHeight: CGFloat
    let chatMessages: [UUID: [ChatMessage]]
    let connections: [TileConnection]

    // Backward-compatible decoding: old snapshots won't have connections
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elements = try container.decode([CanvasElement].self, forKey: .elements)
        zoom = try container.decode(CGFloat.self, forKey: .zoom)
        panOffsetWidth = try container.decode(CGFloat.self, forKey: .panOffsetWidth)
        panOffsetHeight = try container.decode(CGFloat.self, forKey: .panOffsetHeight)
        chatMessages = try container.decode([UUID: [ChatMessage]].self, forKey: .chatMessages)
        connections = try container.decodeIfPresent([TileConnection].self, forKey: .connections) ?? []
    }

    init(
        elements: [CanvasElement],
        zoom: CGFloat,
        panOffsetWidth: CGFloat,
        panOffsetHeight: CGFloat,
        chatMessages: [UUID: [ChatMessage]],
        connections: [TileConnection] = []
    ) {
        self.elements = elements
        self.zoom = zoom
        self.panOffsetWidth = panOffsetWidth
        self.panOffsetHeight = panOffsetHeight
        self.chatMessages = chatMessages
        self.connections = connections
    }
}
```

- [ ] **Step 4: Update PlanCanvasState snapshot/restore to include connections**

In `PlanCanvasState.swift`, modify `snapshot()` (line 615):

```swift
func snapshot() -> CanvasSnapshot {
    var chatMessages: [UUID: [ChatMessage]] = [:]
    for (sessionId, session) in chatSessions {
        if !session.messages.isEmpty {
            chatMessages[sessionId] = session.messages
        }
    }
    return CanvasSnapshot(
        elements: elements,
        zoom: zoom,
        panOffsetWidth: panOffset.width,
        panOffsetHeight: panOffset.height,
        chatMessages: chatMessages,
        connections: connections
    )
}
```

In `restore(from:)` (line 631), add after `elements = snapshot.elements`:

```swift
connections = snapshot.connections
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Also run existing persistence tests to check backward compatibility**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/CanvasPersistenceTests 2>&1 | tail -20`
Expected: PASS (existing tests should still work with the defaulted connections field)

- [ ] **Step 7: Commit**

```bash
git add BudahADE/Plan/CanvasPersistence.swift BudahADE/Plan/PlanCanvasState.swift BudahADETests/TileConnectionTests.swift
git commit -m "feat: persist connections in CanvasSnapshot with backward compatibility"
```

---

### Task 5: ConnectionsLayer — Arrow Rendering

**Files:**
- Create: `BudahADE/Plan/ConnectionsLayer.swift`
- Modify: `BudahADE/Plan/PlanCanvasView.swift` — insert layer

This is the visual heart of Phase 3. Arrows render as bezier curves between tile edges using SwiftUI Canvas draw API (same pattern as SmartGuidesOverlay and the dot grid background).

- [ ] **Step 1: Create ConnectionsLayer with bezier arrow rendering**

```swift
// BudahADE/Plan/ConnectionsLayer.swift
import SwiftUI

struct ConnectionsLayer: View {
    @ObservedObject var canvas: PlanCanvasState

    var body: some View {
        Canvas { context, _ in
            for connection in canvas.connections {
                guard let sourceEl = canvas.findElement(connection.sourceId),
                      let destEl = canvas.findElement(connection.destinationId) else { continue }

                let sourceRect = CGRect(origin: sourceEl.position, size: sourceEl.size)
                let destRect = CGRect(origin: destEl.position, size: destEl.size)

                // Source: right edge center (output port)
                let start = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)
                // Destination: left edge center (input port)
                let end = CGPoint(x: destRect.minX, y: destRect.midY)

                // Bezier control points: horizontal offset for smooth curve
                let dx = abs(end.x - start.x) * 0.5
                let cp1 = CGPoint(x: start.x + dx, y: start.y)
                let cp2 = CGPoint(x: end.x - dx, y: end.y)

                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: cp1, control2: cp2)

                // Dashed stroke when summary is stale (nil)
                let isStale = connection.cachedSummary == nil
                let style = StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: isStale ? [6, 4] : []
                )

                let color = Color.white.opacity(0.35)
                context.stroke(path, with: .color(color), style: style)

                // Arrowhead at destination
                drawArrowhead(context: context, at: end, angle: atan2(end.y - cp2.y, end.x - cp2.x), color: color)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawArrowhead(context: GraphicsContext, at point: CGPoint, angle: CGFloat, color: Color) {
        let size: CGFloat = 8
        let spread: CGFloat = .pi / 6  // 30 degrees

        var path = Path()
        path.move(to: point)
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle - spread),
            y: point.y - size * sin(angle - spread)
        ))
        path.addLine(to: CGPoint(
            x: point.x - size * cos(angle + spread),
            y: point.y - size * sin(angle + spread)
        ))
        path.closeSubpath()

        context.fill(path, with: .color(color))
    }
}
```

- [ ] **Step 2: Insert ConnectionsLayer into PlanCanvasView**

In `PlanCanvasView.swift`, inside the ZStack body (line 27-49), add ConnectionsLayer **between** the canvasBackground and canvasContent. After the `canvasBackground` (line 29) and before `canvasContent` (line 32):

```swift
// Connection arrows layer (in canvas coords, transformed)
ConnectionsLayer(canvas: canvas)
    .scaleEffect(localZoom, anchor: .topLeading)
    .offset(localPanOffset)
    .allowsHitTesting(false)
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/ConnectionsLayer.swift BudahADE/Plan/PlanCanvasView.swift
git commit -m "feat: ConnectionsLayer — bezier arrow rendering between tiles"
```

---

### Task 6: Connection Ports + Drag-to-Connect Interaction

**Files:**
- Create: `BudahADE/Plan/ConnectionPort.swift` — port overlay view + drag gesture
- Modify: `BudahADE/Plan/CanvasElementView.swift` — add port overlays on hover
- Modify: `BudahADE/Plan/ConnectionsLayer.swift` — render in-progress drag connection
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add drag state

- [ ] **Step 1: Add drag state to PlanCanvasState**

Add these published properties to `PlanCanvasState.swift` (after `@Published var hoveredFrameId`, around line 22):

```swift
// Connection drag state
@Published var connectionDragSource: UUID?
@Published var connectionDragEndpoint: CGPoint?
```

- [ ] **Step 2: Create ConnectionPort view**

```swift
// BudahADE/Plan/ConnectionPort.swift
import SwiftUI

struct ConnectionPort: View {
    let elementId: UUID
    let edge: PortEdge
    let elementRect: CGRect
    @ObservedObject var canvas: PlanCanvasState

    enum PortEdge {
        case output  // right edge
        case input   // left edge
    }

    private var portCenter: CGPoint {
        switch edge {
        case .output:
            return CGPoint(x: elementRect.maxX, y: elementRect.midY)
        case .input:
            return CGPoint(x: elementRect.minX, y: elementRect.midY)
        }
    }

    var body: some View {
        let isActive = edge == .output
            ? canvas.connectionDragSource == elementId
            : false

        Circle()
            .fill(isActive ? Theme.accent : Theme.surface2)
            .overlay(
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5)
            )
            .frame(width: 12, height: 12)
            .gesture(
                edge == .output ? outputDragGesture : nil
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    private var outputDragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                canvas.connectionDragSource = elementId
                canvas.connectionDragEndpoint = value.location
            }
            .onEnded { value in
                // Find the destination tile under the drop point
                let dropPoint = value.location
                if let destId = canvas.elementAt(point: dropPoint),
                   destId != elementId {
                    canvas.addConnection(sourceId: elementId, destinationId: destId)
                }
                canvas.connectionDragSource = nil
                canvas.connectionDragEndpoint = nil
            }
    }
}
```

- [ ] **Step 3: Add elementAt(point:) hit test to PlanCanvasState**

Add to `PlanCanvasState.swift` in the Queries section:

```swift
/// Find the topmost element whose rect contains the given canvas-space point
func elementAt(point: CGPoint) -> UUID? {
    // Iterate in reverse (topmost = last in array)
    for element in elements.reversed() {
        let rect = CGRect(origin: element.position, size: element.size)
        if rect.contains(point) {
            return element.id
        }
    }
    return nil
}
```

- [ ] **Step 4: Add port overlays to CanvasElementView**

In `CanvasElementView.swift`, in the free-on-canvas branch (the `else` block starting at line 43), add a port overlay. After the `.onHover` modifier (line 104-109) and before the `.gesture(tileDragGesture(...))` (line 110), add:

```swift
// Connection ports (visible on hover)
.overlay(alignment: .leading) {
    if isHovered || canvas.connectionDragSource != nil, case .tile = element.kind {
        ConnectionPort(
            elementId: element.id,
            edge: .input,
            elementRect: CGRect(origin: .zero, size: element.size),
            canvas: canvas
        )
        .offset(x: -6)
    }
}
.overlay(alignment: .trailing) {
    if isHovered || canvas.connectionDragSource != nil, case .tile = element.kind {
        ConnectionPort(
            elementId: element.id,
            edge: .output,
            elementRect: CGRect(origin: .zero, size: element.size),
            canvas: canvas
        )
        .offset(x: 6)
    }
}
```

- [ ] **Step 5: Add in-progress drag line to ConnectionsLayer**

In `ConnectionsLayer.swift`, add this after the `for connection in canvas.connections` loop, inside the Canvas closure:

```swift
// Draw in-progress connection drag
if let sourceId = canvas.connectionDragSource,
   let sourceEl = canvas.findElement(sourceId),
   let endpoint = canvas.connectionDragEndpoint {
    let sourceRect = CGRect(origin: sourceEl.position, size: sourceEl.size)
    let start = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)
    let end = endpoint

    let dx = abs(end.x - start.x) * 0.5
    let cp1 = CGPoint(x: start.x + dx, y: start.y)
    let cp2 = CGPoint(x: end.x - dx, y: end.y)

    var path = Path()
    path.move(to: start)
    path.addCurve(to: end, control1: cp1, control2: cp2)

    let style = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3])
    context.stroke(path, with: .color(Theme.accent.opacity(0.6)), style: style)
}
```

- [ ] **Step 6: Add coordinateSpace to canvasContent in PlanCanvasView**

In `PlanCanvasView.swift`, on the `canvasContent` view (line 228-236), add `.coordinateSpace(name: "canvas")` after `.offset(localPanOffset)`:

```swift
private var canvasContent: some View {
    ZStack {
        ForEach(visibleElements) { element in
            CanvasElementView(element: element, canvas: canvas)
        }
    }
    .scaleEffect(localZoom, anchor: .topLeading)
    .offset(localPanOffset)
    .coordinateSpace(name: "canvas")
}
```

- [ ] **Step 7: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add BudahADE/Plan/ConnectionPort.swift BudahADE/Plan/CanvasElementView.swift BudahADE/Plan/ConnectionsLayer.swift BudahADE/Plan/PlanCanvasState.swift BudahADE/Plan/PlanCanvasView.swift
git commit -m "feat: connection ports + drag-to-connect interaction"
```

---

### Task 7: Right-Click Delete on Connection Arrows

**Files:**
- Modify: `BudahADE/Plan/ConnectionsLayer.swift` — make arrows hit-testable for right-click

The Canvas draw API doesn't support per-path hit testing. Instead, we overlay invisible hit regions along each connection path.

- [ ] **Step 1: Add hit-testable connection overlays**

Replace the ConnectionsLayer body with a ZStack that has the Canvas for rendering and invisible Path overlays for hit testing:

```swift
var body: some View {
    ZStack {
        // Render layer (Canvas for performance)
        Canvas { context, _ in
            // ... existing arrow rendering code ...
        }
        .allowsHitTesting(false)

        // Hit-test layer (invisible stroked paths for right-click)
        ForEach(canvas.connections) { connection in
            if let sourceEl = canvas.findElement(connection.sourceId),
               let destEl = canvas.findElement(connection.destinationId) {
                let sourceRect = CGRect(origin: sourceEl.position, size: sourceEl.size)
                let destRect = CGRect(origin: destEl.position, size: destEl.size)
                let start = CGPoint(x: sourceRect.maxX, y: sourceRect.midY)
                let end = CGPoint(x: destRect.minX, y: destRect.midY)
                let dx = abs(end.x - start.x) * 0.5

                connectionBezierPath(from: start, to: end, dx: dx)
                    .stroke(Color.clear, lineWidth: 12) // fat invisible hit area
                    .contentShape(
                        connectionBezierPath(from: start, to: end, dx: dx)
                            .strokedPath(StrokeStyle(lineWidth: 12))
                    )
                    .contextMenu {
                        Button("Delete Connection") {
                            canvas.removeConnection(connection.id)
                        }
                    }
            }
        }
    }
}

private func connectionBezierPath(from start: CGPoint, to end: CGPoint, dx: CGFloat) -> Path {
    var path = Path()
    path.move(to: start)
    path.addCurve(
        to: end,
        control1: CGPoint(x: start.x + dx, y: start.y),
        control2: CGPoint(x: end.x - dx, y: end.y)
    )
    return path
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Plan/ConnectionsLayer.swift
git commit -m "feat: right-click delete on connection arrows"
```

---

### Task 8: ConnectionSummaryManager — Haiku Summary Generation + Caching

**Files:**
- Create: `BudahADE/Plan/ConnectionSummaryManager.swift`
- Test: `BudahADETests/ConnectionSummaryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// BudahADETests/ConnectionSummaryTests.swift
import XCTest
@testable import BudahADE

final class ConnectionSummaryTests: XCTestCase {

    @MainActor
    func testSummaryManagerCacheHit() async {
        let manager = ConnectionSummaryManager()
        var conn = TileConnection(sourceId: UUID(), destinationId: UUID(), cachedSummary: "cached", sourceVersion: 1)
        // Cache is fresh — should return cached value without spawning subprocess
        let result = manager.resolvedSummary(for: &conn, output: .text("some content"))
        XCTAssertEqual(result, "cached")
    }

    @MainActor
    func testSummaryManagerCacheMiss() {
        let manager = ConnectionSummaryManager()
        var conn = TileConnection(sourceId: UUID(), destinationId: UUID(), sourceVersion: 1)
        // No cache — should return nil and trigger async generation
        let result = manager.resolvedSummary(for: &conn, output: .text("some content"))
        XCTAssertNil(result) // nil means "generating"
    }

    @MainActor
    func testSummaryConcurrencyLimit() {
        let manager = ConnectionSummaryManager()
        XCTAssertEqual(manager.activeSummaryCount, 0)
        // Verify the limit constant
        XCTAssertEqual(ConnectionSummaryManager.maxConcurrentSummaries, 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — ConnectionSummaryManager not defined

- [ ] **Step 3: Implement ConnectionSummaryManager**

```swift
// BudahADE/Plan/ConnectionSummaryManager.swift
import Foundation

@MainActor
final class ConnectionSummaryManager: ObservableObject {

    static let maxConcurrentSummaries = 3

    @Published private(set) var activeSummaryCount: Int = 0
    private var pendingQueue: [(UUID, String)] = []  // (connectionId, inputText)
    private var inFlightIds: Set<UUID> = []

    /// Returns cached summary if fresh, nil if generating. Triggers async generation on cache miss.
    func resolvedSummary(for connection: inout TileConnection, output: TileOutput) -> String? {
        // Cache hit
        if connection.cachedSummary != nil {
            return connection.cachedSummary
        }

        // Already in flight
        if inFlightIds.contains(connection.id) {
            return nil
        }

        // Queue generation
        let text = output.textRepresentation
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        enqueue(connectionId: connection.id, inputText: text)
        return nil
    }

    /// Update connection with completed summary
    func completeSummary(connectionId: UUID, summary: String, canvas: PlanCanvasState) {
        inFlightIds.remove(connectionId)
        activeSummaryCount = inFlightIds.count

        if let idx = canvas.connections.firstIndex(where: { $0.id == connectionId }) {
            canvas.connections[idx].cachedSummary = summary
            canvas.connections[idx].summaryTimestamp = Date()
        }

        drainQueue(canvas: canvas)
    }

    private func enqueue(connectionId: UUID, inputText: String) {
        if inFlightIds.count < Self.maxConcurrentSummaries {
            startGeneration(connectionId: connectionId, inputText: inputText)
        } else {
            pendingQueue.append((connectionId, inputText))
        }
    }

    private func drainQueue(canvas: PlanCanvasState) {
        while inFlightIds.count < Self.maxConcurrentSummaries, !pendingQueue.isEmpty {
            let (id, text) = pendingQueue.removeFirst()
            // Skip if connection was removed while queued
            guard canvas.connections.contains(where: { $0.id == id }) else { continue }
            startGeneration(connectionId: id, inputText: text)
        }
    }

    private func startGeneration(connectionId: UUID, inputText: String) {
        inFlightIds.insert(connectionId)
        activeSummaryCount = inFlightIds.count

        let truncated = String(inputText.prefix(2000))  // limit input to ~500 tokens
        let prompt = "Summarize this concisely for a developer in 2-3 sentences:\n\n\(truncated)"

        Task {
            let summary = await runHaikuSummary(prompt: prompt)
            await MainActor.run {
                // Note: canvas reference needed — caller provides via completeSummary
                // For now, store result and let the caller apply it
            }
            _ = summary  // Used by caller
        }
    }

    /// Spawn a Haiku subprocess to generate a summary
    nonisolated private func runHaikuSummary(prompt: String) async -> String {
        let claudePath = CLISubprocessManager.resolveClaudePath()
        guard let claudePath else { return prompt.prefix(200).description }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--model", "haiku", "--max-turns", "1"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? prompt.prefix(200).description : output
        } catch {
            return prompt.prefix(200).description
        }
    }
}
```

- [ ] **Step 4: Add resolveClaudePath() as a static method on CLISubprocessManager**

Check if `CLISubprocessManager` already has path resolution logic. If it resolves the claude binary path in `runSubprocess`, extract it as a static method. Add to `CLISubprocessManager.swift`:

```swift
/// Resolve the claude binary path (GUI apps don't inherit shell PATH)
static func resolveClaudePath() -> String? {
    let candidates = [
        "\(NSHomeDirectory())/.claude/local/claude",
        "/usr/local/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}
```

If a similar method already exists, reuse it.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/ConnectionSummaryTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/ConnectionSummaryManager.swift BudahADE/Agent/CLISubprocessManager.swift BudahADETests/ConnectionSummaryTests.swift
git commit -m "feat: ConnectionSummaryManager — Haiku summary generation with concurrency throttle"
```

---

### Task 9: Wire Summary Generation Into Canvas Lifecycle

**Files:**
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add summaryManager, trigger on mutation
- Modify: `BudahADE/Plan/ConnectionSummaryManager.swift` — integrate with canvas

- [ ] **Step 1: Add summaryManager to PlanCanvasState**

In `PlanCanvasState.swift`, add after `let chatManager = CLISubprocessManager()` (line 12):

```swift
let summaryManager = ConnectionSummaryManager()
```

- [ ] **Step 2: Add method to refresh stale summaries**

Add to PlanCanvasState in the Connections section:

```swift
/// Check all connections and regenerate stale summaries
func refreshStaleSummaries() {
    for i in connections.indices {
        guard connections[i].cachedSummary == nil,
              let output = tileOutput(for: connections[i].sourceId) else { continue }
        let _ = summaryManager.resolvedSummary(for: &connections[i], output: output)
    }
}
```

- [ ] **Step 3: Trigger summary refresh in didMutate**

In `didMutate()` (line 695), add after the existing calls:

```swift
refreshStaleSummaries()
```

- [ ] **Step 4: Wire completeSummary callback**

Update `ConnectionSummaryManager.startGeneration` to properly call back to the canvas. The simplest approach: pass a completion closure from the canvas.

Actually, a cleaner design: have `ConnectionSummaryManager` hold a weak reference to the canvas state, set during init. Update accordingly:

Add to `ConnectionSummaryManager`:

```swift
weak var canvas: PlanCanvasState?
```

In `startGeneration`, replace the Task body:

```swift
Task {
    let summary = await runHaikuSummary(prompt: prompt)
    await MainActor.run { [weak self] in
        guard let self, let canvas = self.canvas else { return }
        self.completeSummary(connectionId: connectionId, summary: summary, canvas: canvas)
    }
}
```

In `PlanCanvasState.init`, after creating summaryManager, set:

```swift
summaryManager.canvas = self
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Plan/PlanCanvasState.swift BudahADE/Plan/ConnectionSummaryManager.swift
git commit -m "feat: wire summary generation into canvas mutation lifecycle"
```

---

### Task 10: Context Injection Into Chat Tiles

**Files:**
- Modify: `BudahADE/Plan/TileViews/ChatTileView.swift` — prepend connected context to prompts
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add assembleContext method

- [ ] **Step 1: Add assembleConnectedContext method to PlanCanvasState**

Add to the Connections section:

```swift
/// Assemble context from all incoming connections for a destination tile
func assembleConnectedContext(for destinationId: UUID) -> String? {
    let incoming = incomingConnections(for: destinationId)
    guard !incoming.isEmpty else { return nil }

    var contextBlocks: [String] = []
    for connection in incoming {
        guard let sourceEl = findElement(connection.sourceId) else { continue }
        let label = sourceEl.title.isEmpty ? "Tile" : sourceEl.title

        if let summary = connection.cachedSummary {
            contextBlocks.append("[\(label)] \(summary)")
        } else if let output = tileOutput(for: connection.sourceId) {
            // No summary yet — use truncated raw output
            let raw = String(output.textRepresentation.prefix(500))
            contextBlocks.append("[\(label)] \(raw)")
        }
    }

    guard !contextBlocks.isEmpty else { return nil }

    return "Context from connected tiles:\n---\n" +
        contextBlocks.joined(separator: "\n---\n") +
        "\n---"
}
```

- [ ] **Step 2: Find the element ID for a chat session in ChatTileView**

`ChatTileView` already receives `elementId` as a parameter. We need to use it in `sendMessage()`.

- [ ] **Step 3: Modify sendMessage() in ChatTileView to prepend connected context**

In `ChatTileView.swift`, in the `sendMessage()` method (line 421), after building `prompt` and before the staged content handling (line 428), add:

```swift
// Prepend connected tile context
if let connectedContext = canvas.assembleConnectedContext(for: elementId) {
    prompt = "\(connectedContext)\n\n\(prompt)"
}
```

This must go **before** the staged content handling so that both context sources compose correctly.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Write a test for context assembly**

```swift
// Add to TileConnectionTests.swift
@MainActor
func testAssembleConnectedContext() {
    let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
    let tmpFile = NSTemporaryDirectory() + "ctx-test-\(UUID()).md"
    try! "# Design Notes\nUse OAuth2 for auth.".write(toFile: tmpFile, atomically: true, encoding: .utf8)

    let noteId = canvas.addTile(type: .markdown(path: tmpFile), at: .zero)
    let chatId = canvas.addChatTile(agent: .developer, at: CGPoint(x: 500, y: 0))

    // Create connection: note → chat
    var connId = canvas.addConnection(sourceId: noteId, destinationId: chatId)

    // Manually set cached summary
    if let idx = canvas.connections.firstIndex(where: { $0.id == connId }) {
        canvas.connections[idx].cachedSummary = "Design notes about OAuth2 auth approach"
    }

    let context = canvas.assembleConnectedContext(for: chatId)
    XCTAssertNotNil(context)
    XCTAssertTrue(context!.contains("OAuth2"))
    XCTAssertTrue(context!.contains("Context from connected tiles"))

    try? FileManager.default.removeItem(atPath: tmpFile)
}
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' -only-testing BudahADETests/TileConnectionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add BudahADE/Plan/PlanCanvasState.swift BudahADE/Plan/TileViews/ChatTileView.swift BudahADETests/TileConnectionTests.swift
git commit -m "feat: context injection — connected tile summaries prepended to chat prompts"
```

---

### Task 11: Update ContextManifest with Connections

**Files:**
- Modify: `BudahADE/Plan/ContextManifest.swift`

- [ ] **Step 1: Add connections section to ContextManifest.write()**

In `ContextManifest.swift`, after the `Active Conversations` section (after line 70), add:

```swift
if !canvas.connections.isEmpty {
    lines.append("## Connections")
    for conn in canvas.connections {
        let sourceName = canvas.findElement(conn.sourceId)?.title ?? "unknown"
        let destName = canvas.findElement(conn.destinationId)?.title ?? "unknown"
        let status = conn.cachedSummary != nil ? "✓" : "pending"
        lines.append("- \(sourceName) → \(destName) (\(status))")
    }
    lines.append("")
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/Plan/ContextManifest.swift
git commit -m "feat: include connections in ContextManifest output"
```

---

### Task 12: Add to Xcode Project + Full Test Run

**Files:**
- Modify: `BudahADE.xcodeproj/project.pbxproj` — add new files to build targets

- [ ] **Step 1: Ensure all new files are in the Xcode project**

New source files to verify are in the project:
- `BudahADE/Plan/TileConnection.swift`
- `BudahADE/Plan/ConnectionsLayer.swift`
- `BudahADE/Plan/ConnectionPort.swift`
- `BudahADE/Plan/ConnectionSummaryManager.swift`

New test files:
- `BudahADETests/TileConnectionTests.swift`
- `BudahADETests/ConnectionSummaryTests.swift`

If any file was created but not automatically added to the Xcode project by the build system, add it manually via `xcodebuild` or by editing `project.pbxproj`.

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -scheme BudahADE -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass (existing 90 + new ~12 = ~102 tests)

- [ ] **Step 3: Run the app from terminal to verify no runtime issues**

Run: `~/Library/Developer/Xcode/DerivedData/BudahADE-*/Build/Products/Debug/BudahADE.app/Contents/MacOS/BudahADE`
Expected: App launches, canvas works, no crashes

- [ ] **Step 4: Commit if any project file changes were needed**

```bash
git add BudahADE.xcodeproj/project.pbxproj
git commit -m "chore: add Phase 3 files to Xcode project"
```

---

### Task 13: Integration Verification (Manual)

Run through the Phase 3 verification checklist from the spec:

- [ ] **1. Connection creation** — right-click canvas → add two tiles. Hover tile edge → output port appears. Drag from output port to another tile's input port. Arrow renders as bezier curve. Right-click arrow → "Delete Connection" removes it.

- [ ] **2. Arrow rendering performance** — add 10+ connections. Pan/zoom. Arrows follow tile positions when tiles are dragged. No jank.

- [ ] **3. Content-type outputs** — connect different tile types. Verify `tileOutput(for:)` returns correct type for: sticky → text, markdown → text, chat → conversation, image → image URL, browser → URL.

- [ ] **4. Summary generation** — connect two tiles. Verify Haiku subprocess spawns (check Activity Monitor for claude process). Summary populates. Arrow becomes solid (not dashed). Modify source → arrow becomes dashed → regenerates.

- [ ] **5. Context injection into chat tiles** — connect Ideator → Developer. Send message in Developer. Verify context appears prepended in the prompt sent to claude CLI.

- [ ] **6. Concurrency** — stale 5+ connections simultaneously. Verify max 3 claude processes at once.

- [ ] **7. Persistence** — create connections, switch tasks and return. Connections preserved. Close app and relaunch → connections survive.

- [ ] **8. Final commit**

```bash
git add -A
git commit -m "feat: Phase 3 — Contextual Connections complete"
```
