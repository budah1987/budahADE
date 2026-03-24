# Phase 2: CLI Subprocess Agent System + Chat UI Tile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add programmatic `claude -p` subprocess agents with a Chat UI tile on the canvas, enabling lightweight agent conversations alongside terminal tiles.

**Architecture:** `CLISubprocessManager` spawns `claude -p --output-format stream-json` processes, parsing newline-delimited JSON into `ChatMessage` structs. `ChatTileView` renders conversations in a `ScrollView` + `LazyVStack` with send/receive, model switching, and "Send To" for routing content to spec or other agents. Agent roles define system prompts and default models.

**Tech Stack:** Swift, Foundation `Process`, SwiftUI, `stream-json` parsing, existing `TileChrome` pattern, existing `AgentMode`/`AgentPrompts` infrastructure.

**Spec Reference:** `docs/superpowers/specs/2026-03-23-workflow-v2-overhaul-design.md` — Phase 2 (lines 98–223)

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `BudahADE/Agent/ChatMessage.swift` | `ChatMessage` struct + `StreamEvent` enum for parsed stream-json events |
| `BudahADE/Agent/AgentSession.swift` | `AgentSession` observable — owns a subprocess, message history, token count, status |
| `BudahADE/Agent/CLISubprocessManager.swift` | Singleton managing all `AgentSession` instances — spawn, send, resume, cancel |
| `BudahADE/Agent/AgentRole.swift` | `AgentRole` struct — name, system prompt, default model, color. Built-in + custom roles |
| `BudahADE/Plan/TileViews/ChatTileView.swift` | Canvas tile: message list, input area, header with status/model/tokens, "Send To" |
| `BudahADE/Plan/TileViews/SendToMenu.swift` | Reusable dropdown: "Send to Spec" / "Send to Agent" / "New Agent..." |

### Modified Files

| File | Changes |
|------|---------|
| `BudahADE/Plan/TileType.swift` | Add `.chatAgent(sessionId: UUID, role: AgentRole)` case to `TileType` |
| `BudahADE/Plan/CanvasElementView.swift` | Add `.chatAgent` dispatch in `TileContentView` |
| `BudahADE/Plan/AddTileMenu.swift` | Add chat agent section (separate from terminal agents) |
| `BudahADE/Plan/PlanCanvasState.swift` | Add `chatSessions: [UUID: AgentSession]`, `addChatTile()`, cleanup in `closeAll()` |
| `BudahADE/Plan/AgentPrompts.swift` | Add `chatPrompt()` method for non-interactive subprocess prompt construction |

### Test Files

| File | Tests |
|------|-------|
| `BudahADETests/ChatMessageTests.swift` | Stream-json parsing, message construction |
| `BudahADETests/AgentSessionTests.swift` | Session lifecycle, multi-turn state |
| `BudahADETests/CLISubprocessManagerTests.swift` | Spawn, cancel, session tracking |

---

## Task 1: ChatMessage + StreamEvent Models

**Files:**
- Create: `BudahADE/Agent/ChatMessage.swift`
- Test: `BudahADETests/ChatMessageTests.swift`

- [ ] **Step 1: Write failing test for StreamEvent JSON parsing**

```swift
// BudahADETests/ChatMessageTests.swift
import XCTest
@testable import BudahADE

final class ChatMessageTests: XCTestCase {

    // MARK: - StreamEvent Parsing

    func testParseAssistantTextEvent() throws {
        let json = """
        {"type":"assistant","message":{"id":"msg_01","type":"message","role":"assistant","content":[{"type":"text","text":"Hello world"}],"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .assistant(let msg) = event else {
            XCTFail("Expected .assistant, got \(event)")
            return
        }
        XCTAssertEqual(msg.content, "Hello world")
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.inputTokens, 10)
        XCTAssertEqual(msg.outputTokens, 5)
    }

    func testParseContentBlockDelta() throws {
        let json = """
        {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"streaming chunk"}}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .contentDelta(let text) = event else {
            XCTFail("Expected .contentDelta, got \(event)")
            return
        }
        XCTAssertEqual(text, "streaming chunk")
    }

    func testParseToolUseEvent() throws {
        let json = """
        {"type":"assistant","subtype":"tool_use","message":{"id":"msg_02","type":"message","role":"assistant","content":[{"type":"tool_use","id":"tool_01","name":"Read","input":{"file_path":"/tmp/test.swift"}}],"model":"claude-sonnet-4-6","usage":{"input_tokens":20,"output_tokens":15}}}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .assistant(let msg) = event else {
            XCTFail("Expected .assistant, got \(event)")
            return
        }
        XCTAssertEqual(msg.toolCalls?.count, 1)
        XCTAssertEqual(msg.toolCalls?.first?.name, "Read")
    }

    func testParseResultEvent() throws {
        let json = """
        {"type":"result","subtype":"success","cost_usd":0.003,"duration_ms":1200,"session_id":"abc-123","usage":{"input_tokens":100,"output_tokens":50}}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .result(let result) = event else {
            XCTFail("Expected .result, got \(event)")
            return
        }
        XCTAssertEqual(result.costUSD, 0.003)
        XCTAssertEqual(result.sessionId, "abc-123")
    }

    func testParseSystemInitEvent() throws {
        let json = """
        {"type":"system","subtype":"init","session_id":"abc-123","tools":["Read","Write","Bash"],"model":"claude-sonnet-4-6"}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .system(let info) = event else {
            XCTFail("Expected .system, got \(event)")
            return
        }
        XCTAssertEqual(info.sessionId, "abc-123")
    }

    func testParseUnknownEventDoesNotThrow() throws {
        let json = """
        {"type":"unknown_future_type","data":"stuff"}
        """
        let event = try StreamEvent.parse(from: json)
        guard case .unknown = event else {
            XCTFail("Expected .unknown, got \(event)")
            return
        }
    }

    // MARK: - ChatMessage Construction

    func testChatMessageFromUserText() {
        let msg = ChatMessage(role: .user, content: "Hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertNil(msg.toolCalls)
    }

    func testChatMessageTokenCount() {
        let msg = ChatMessage(
            role: .assistant,
            content: "Response",
            inputTokens: 100,
            outputTokens: 50
        )
        XCTAssertEqual(msg.totalTokens, 150)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/ChatMessageTests 2>&1 | tail -20`
Expected: FAIL — types don't exist yet

- [ ] **Step 3: Implement ChatMessage and StreamEvent**

```swift
// BudahADE/Agent/ChatMessage.swift
import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let toolCalls: [ToolCall]?
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        timestamp: Date = Date(),
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum MessageRole: String, Equatable {
        case user
        case assistant
        case system
    }
}

struct ToolCall: Equatable {
    let id: String
    let name: String
    let input: String  // raw JSON string
}

// MARK: - Stream Events (from claude -p --output-format stream-json)

enum StreamEvent {
    case system(SystemInfo)
    case assistant(AssistantMessage)
    case contentDelta(String)
    case result(ResultInfo)
    case unknown

    struct SystemInfo {
        let sessionId: String
        let tools: [String]?
        let model: String?
    }

    struct AssistantMessage {
        let content: String
        let role: ChatMessage.MessageRole
        let toolCalls: [ToolCall]?
        let inputTokens: Int
        let outputTokens: Int
        let model: String?
    }

    struct ResultInfo {
        let costUSD: Double
        let durationMs: Int?
        let sessionId: String?
        let inputTokens: Int
        let outputTokens: Int
    }

    static func parse(from jsonString: String) throws -> StreamEvent {
        guard let data = jsonString.data(using: .utf8) else {
            throw StreamParseError.invalidData
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamParseError.invalidJSON
        }
        guard let type = json["type"] as? String else {
            throw StreamParseError.missingType
        }

        switch type {
        case "system":
            let sessionId = json["session_id"] as? String ?? ""
            let tools = json["tools"] as? [String]
            let model = json["model"] as? String
            return .system(SystemInfo(sessionId: sessionId, tools: tools, model: model))

        case "assistant":
            return .assistant(parseAssistantMessage(json))

        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return .contentDelta(text)
            }
            return .unknown

        case "result":
            let usage = json["usage"] as? [String: Any]
            return .result(ResultInfo(
                costUSD: json["cost_usd"] as? Double ?? 0,
                durationMs: json["duration_ms"] as? Int,
                sessionId: json["session_id"] as? String,
                inputTokens: usage?["input_tokens"] as? Int ?? 0,
                outputTokens: usage?["output_tokens"] as? Int ?? 0
            ))

        default:
            return .unknown
        }
    }

    private static func parseAssistantMessage(_ json: [String: Any]) -> AssistantMessage {
        let message = json["message"] as? [String: Any] ?? [:]
        let contentArray = message["content"] as? [[String: Any]] ?? []
        let usage = message["usage"] as? [String: Any] ?? [:]

        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for block in contentArray {
            let blockType = block["type"] as? String
            if blockType == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if blockType == "tool_use" {
                let id = block["id"] as? String ?? ""
                let name = block["name"] as? String ?? ""
                let input: String
                if let inputObj = block["input"] {
                    if let inputData = try? JSONSerialization.data(withJSONObject: inputObj),
                       let inputStr = String(data: inputData, encoding: .utf8) {
                        input = inputStr
                    } else {
                        input = "{}"
                    }
                } else {
                    input = "{}"
                }
                toolCalls.append(ToolCall(id: id, name: name, input: input))
            }
        }

        let roleStr = message["role"] as? String ?? "assistant"
        let role: ChatMessage.MessageRole = roleStr == "user" ? .user : .assistant

        return AssistantMessage(
            content: textParts.joined(separator: "\n"),
            role: role,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            model: message["model"] as? String
        )
    }
}

enum StreamParseError: Error {
    case invalidData
    case invalidJSON
    case missingType
}
```

- [ ] **Step 4: Create Agent directory and add file to project**

```bash
mkdir -p BudahADE/Agent
# Move the file into place (already created by Write tool)
# Add to Xcode project — the project uses directory references, so files in BudahADE/ are auto-discovered
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/ChatMessageTests 2>&1 | tail -20`
Expected: PASS — all 7 tests green

- [ ] **Step 6: Commit**

```bash
git add BudahADE/Agent/ChatMessage.swift BudahADETests/ChatMessageTests.swift
git commit -m "feat: add ChatMessage model and StreamEvent parser for stream-json output"
```

---

## Task 2: AgentSession — Subprocess Lifecycle + Message State

**Files:**
- Create: `BudahADE/Agent/AgentSession.swift`
- Test: `BudahADETests/AgentSessionTests.swift`
- Read first: `BudahADE/Terminal/TerminalPanel.swift` (47 LOC) — parallel lifecycle pattern
- Read first: `BudahADE/Agent/ChatMessage.swift` (Task 1) — message/event types

- [ ] **Step 1: Write failing tests for AgentSession state management**

```swift
// BudahADETests/AgentSessionTests.swift
import XCTest
@testable import BudahADE

@MainActor
final class AgentSessionTests: XCTestCase {

    func testInitialState() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "You are a helper",
            workingDirectory: "/tmp"
        )
        XCTAssertEqual(session.status, .idle)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.totalInputTokens, 0)
        XCTAssertEqual(session.totalOutputTokens, 0)
        XCTAssertNil(session.claudeSessionId)
    }

    func testAddUserMessage() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        session.addUserMessage("Hello")
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages[0].role, .user)
        XCTAssertEqual(session.messages[0].content, "Hello")
    }

    func testHandleAssistantEvent() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        let event = StreamEvent.AssistantMessage(
            content: "Hi there",
            role: .assistant,
            toolCalls: nil,
            inputTokens: 50,
            outputTokens: 20,
            model: "claude-sonnet-4-6"
        )
        session.handleAssistantMessage(event)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages[0].content, "Hi there")
        XCTAssertEqual(session.totalInputTokens, 50)
        XCTAssertEqual(session.totalOutputTokens, 20)
    }

    func testHandleSystemInitSetsSessionId() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        let info = StreamEvent.SystemInfo(
            sessionId: "sess-abc-123",
            tools: ["Read", "Write"],
            model: "claude-sonnet-4-6"
        )
        session.handleSystemInit(info)
        XCTAssertEqual(session.claudeSessionId, "sess-abc-123")
    }

    func testTokenFormatting() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        // Simulate accumulated tokens
        let event = StreamEvent.AssistantMessage(
            content: "test",
            role: .assistant,
            toolCalls: nil,
            inputTokens: 2400,
            outputTokens: 600,
            model: nil
        )
        session.handleAssistantMessage(event)
        XCTAssertEqual(session.formattedTokenCount, "3.0k")
    }

    func testModelEnum() {
        XCTAssertEqual(AgentModel.haiku.cliFlag, "haiku")
        XCTAssertEqual(AgentModel.sonnet.cliFlag, "sonnet")
        XCTAssertEqual(AgentModel.opus.cliFlag, "opus")
    }

    func testAgentModeTracking() {
        let session = AgentSession(
            model: .opus,
            agentMode: .ideator,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        XCTAssertEqual(session.agentMode, .ideator)
        XCTAssertEqual(session.model, .opus)
    }

    func testModelCanBeChangedPerTurn() {
        let session = AgentSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        session.model = .haiku
        XCTAssertEqual(session.model, .haiku)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/AgentSessionTests 2>&1 | tail -20`
Expected: FAIL — AgentSession doesn't exist

- [ ] **Step 3: Implement AgentSession**

```swift
// BudahADE/Agent/AgentSession.swift
import Foundation
import Combine

// MARK: - Agent Model

enum AgentModel: String, CaseIterable, Identifiable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }

    var cliFlag: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus:   return "Opus"
        }
    }
}

// MARK: - Agent Session Status

enum AgentSessionStatus: Equatable {
    case idle
    case streaming
    case done
    case error(String)
}

// MARK: - Agent Session

@MainActor
final class AgentSession: ObservableObject, Identifiable {
    let id: UUID
    var model: AgentModel          // var — can be changed per-turn via model picker
    let agentMode: AgentMode?      // which AgentMode this session was created from (for sendToAgent matching)
    let systemPrompt: String
    let workingDirectory: String

    @Published var status: AgentSessionStatus = .idle
    @Published var messages: [ChatMessage] = []
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var claudeSessionId: String?
    @Published var currentStreamingText: String = ""

    /// The underlying OS process (nil when idle)
    var process: Process?

    init(
        id: UUID = UUID(),
        model: AgentModel,
        agentMode: AgentMode? = nil,
        systemPrompt: String,
        workingDirectory: String
    ) {
        self.id = id
        self.model = model
        self.agentMode = agentMode
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
    }

    // MARK: - Message Handling

    func addUserMessage(_ content: String) {
        let message = ChatMessage(role: .user, content: content)
        messages.append(message)
    }

    func handleAssistantMessage(_ event: StreamEvent.AssistantMessage) {
        let message = ChatMessage(
            role: event.role,
            content: event.content,
            toolCalls: event.toolCalls,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens
        )
        messages.append(message)
        totalInputTokens += event.inputTokens
        totalOutputTokens += event.outputTokens
        currentStreamingText = ""
    }

    func handleContentDelta(_ text: String) {
        currentStreamingText += text
    }

    func handleSystemInit(_ info: StreamEvent.SystemInfo) {
        claudeSessionId = info.sessionId
    }

    func handleResult(_ result: StreamEvent.ResultInfo) {
        status = .done
        if claudeSessionId == nil, let sid = result.sessionId {
            claudeSessionId = sid
        }
    }

    // MARK: - Formatting

    var formattedTokenCount: String {
        let total = totalInputTokens + totalOutputTokens
        if total < 1000 {
            return "\(total)"
        } else {
            let k = Double(total) / 1000.0
            return String(format: "%.1fk", k)
        }
    }

    var totalTokens: Int { totalInputTokens + totalOutputTokens }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/AgentSessionTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Agent/AgentSession.swift BudahADETests/AgentSessionTests.swift
git commit -m "feat: add AgentSession with message handling, token tracking, and model enum"
```

---

## Task 3: CLISubprocessManager — Spawn + Stream + Cancel

**Files:**
- Create: `BudahADE/Agent/CLISubprocessManager.swift`
- Test: `BudahADETests/CLISubprocessManagerTests.swift`
- Read first: `BudahADE/Agent/AgentSession.swift` (Task 2)
- Read first: `BudahADE/Agent/ChatMessage.swift` (Task 1)
- Read first: `BudahADE/Task/GitWorktreeManager.swift:1-50` — `runGit()` async Process pattern to follow

This is the core infrastructure. It spawns `claude -p` processes, pipes prompts via stdin, and parses newline-delimited `stream-json` from stdout.

- [ ] **Step 1: Write failing test for subprocess manager**

```swift
// BudahADETests/CLISubprocessManagerTests.swift
import XCTest
@testable import BudahADE

@MainActor
final class CLISubprocessManagerTests: XCTestCase {

    func testSpawnCreatesSession() async throws {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .sonnet,
            systemPrompt: "You are a test helper",
            workingDirectory: "/tmp"
        )
        XCTAssertNotNil(manager.sessions[session.id])
        XCTAssertEqual(session.status, .idle)
    }

    func testCancelSetsStatusAndKillsProcess() async throws {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        // Simulate an active process
        session.status = .streaming
        manager.cancel(sessionId: session.id)
        XCTAssertEqual(session.status, .idle)
        XCTAssertNil(session.process)
    }

    func testBuildCommandString() {
        let manager = CLISubprocessManager()
        let cmd = manager.buildCommand(
            prompt: "Hello world",
            model: .sonnet,
            systemPromptPath: "/tmp/prompt.md",
            sessionId: nil
        )
        XCTAssertTrue(cmd.contains("claude"))
        XCTAssertTrue(cmd.contains("-p"))
        XCTAssertTrue(cmd.contains("--output-format stream-json"))
        XCTAssertTrue(cmd.contains("--model sonnet"))
        XCTAssertTrue(cmd.contains("--system-prompt"))
    }

    func testBuildResumeCommand() {
        let manager = CLISubprocessManager()
        let cmd = manager.buildCommand(
            prompt: "Follow up",
            model: .sonnet,
            systemPromptPath: "/tmp/prompt.md",
            sessionId: "sess-abc"
        )
        XCTAssertTrue(cmd.contains("--resume sess-abc"))
    }

    func testParseStreamLines() async throws {
        let manager = CLISubprocessManager()
        let lines = [
            """
            {"type":"system","subtype":"init","session_id":"abc","tools":["Read"],"model":"claude-sonnet-4-6"}
            """,
            """
            {"type":"assistant","message":{"id":"msg_01","type":"message","role":"assistant","content":[{"type":"text","text":"Hello"}],"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":5}}}
            """,
            """
            {"type":"result","subtype":"success","cost_usd":0.001,"session_id":"abc","usage":{"input_tokens":10,"output_tokens":5}}
            """
        ]
        let session = manager.createSession(
            model: .sonnet,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        for line in lines {
            manager.processStreamLine(line, session: session)
        }
        XCTAssertEqual(session.claudeSessionId, "abc")
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages[0].content, "Hello")
        XCTAssertEqual(session.status, .done)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/CLISubprocessManagerTests 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Implement CLISubprocessManager**

```swift
// BudahADE/Agent/CLISubprocessManager.swift
import Foundation

@MainActor
final class CLISubprocessManager: ObservableObject {
    @Published var sessions: [UUID: AgentSession] = [:]

    // MARK: - Session Lifecycle

    @discardableResult
    func createSession(
        model: AgentModel,
        agentMode: AgentMode? = nil,
        systemPrompt: String,
        workingDirectory: String
    ) -> AgentSession {
        let session = AgentSession(
            model: model,
            agentMode: agentMode,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        )
        sessions[session.id] = session
        return session
    }

    /// Send a prompt to a session. Spawns a new process or resumes an existing session.
    /// Pass `model` to override the session's default (e.g., user changed the model picker).
    func send(sessionId: UUID, prompt: String, model: AgentModel? = nil) {
        guard let session = sessions[sessionId] else { return }

        // Apply model override if provided (per-turn model switching)
        if let model { session.model = model }

        session.addUserMessage(prompt)
        session.status = .streaming

        // Write system prompt to temp file
        let promptPath = writeSystemPrompt(session: session)

        let command = buildCommand(
            prompt: prompt,
            model: session.model,
            systemPromptPath: promptPath,
            sessionId: session.claudeSessionId
        )

        Task.detached { [weak self] in
            await self?.runSubprocess(command: command, session: session)
        }
    }

    func cancel(sessionId: UUID) {
        guard let session = sessions[sessionId] else { return }
        if let process = session.process, process.isRunning {
            process.terminate()
        }
        session.process = nil
        session.status = .idle
        session.currentStreamingText = ""
    }

    func removeSession(sessionId: UUID) {
        cancel(sessionId: sessionId)
        sessions.removeValue(forKey: sessionId)
    }

    // MARK: - Workspace-Level Token Tracking

    /// Total tokens across all sessions (for workspace status bar display)
    var totalTokensAllSessions: Int {
        sessions.values.reduce(0) { $0 + $1.totalTokens }
    }

    var formattedTotalTokens: String {
        let total = totalTokensAllSessions
        if total < 1000 { return "\(total)" }
        let k = Double(total) / 1000.0
        return String(format: "%.1fk", k)
    }

    var activeSessionCount: Int {
        sessions.values.filter { $0.status == .streaming || $0.status == .done }.count
    }

    // MARK: - Command Building

    func buildCommand(
        prompt: String,
        model: AgentModel,
        systemPromptPath: String,
        sessionId: String?
    ) -> [String] {
        var args = ["claude", "-p", prompt]
        args += ["--output-format", "stream-json"]
        args += ["--model", model.cliFlag]
        args += ["--system-prompt-file", systemPromptPath]
        args += ["--dangerously-skip-permissions"]

        if let sessionId {
            args += ["--resume", sessionId]
        }

        return args
    }

    // MARK: - Stream Processing

    func processStreamLine(_ line: String, session: AgentSession) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let event = try StreamEvent.parse(from: trimmed)
            switch event {
            case .system(let info):
                session.handleSystemInit(info)
            case .assistant(let msg):
                session.handleAssistantMessage(msg)
            case .contentDelta(let text):
                session.handleContentDelta(text)
            case .result(let result):
                session.handleResult(result)
            case .unknown:
                break
            }
        } catch {
            print("[CLISubprocessManager] Failed to parse stream line: \(error)")
        }
    }

    // MARK: - Private

    private func writeSystemPrompt(session: AgentSession) -> String {
        let dir = (session.workingDirectory as NSString)
            .appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let path = (dir as NSString)
            .appendingPathComponent("chat-\(session.id.uuidString)-prompt.md")
        try? session.systemPrompt.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private nonisolated func runSubprocess(
        command: [String],
        session: AgentSession
    ) async {
        let process = Process()
        let pipe = Pipe()

        // Find claude executable
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        await MainActor.run {
            session.process = process
            session.workingDirectory.withCString { _ in }
        }
        let workDir = await session.workingDirectory
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)

        do {
            try process.run()
        } catch {
            await MainActor.run {
                session.status = .error("Failed to launch: \(error.localizedDescription)")
                session.process = nil
            }
            return
        }

        // Read stdout line by line
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while process.isRunning || !buffer.isEmpty {
            let chunk = handle.availableData
            if chunk.isEmpty && !process.isRunning { break }
            buffer.append(chunk)

            // Split by newlines
            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    await MainActor.run { [weak self] in
                        self?.processStreamLine(line, session: session)
                    }
                }
            }
        }

        // Process any remaining data
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            await MainActor.run { [weak self] in
                self?.processStreamLine(line, session: session)
            }
        }

        process.waitUntilExit()
        await MainActor.run {
            session.process = nil
            if session.status == .streaming {
                session.status = .done
            }
        }
    }
}
```

**Implementation notes:**
- `runSubprocess` runs on a detached task (background). Stream lines dispatch back to `@MainActor` for state mutation.
- Uses `/usr/bin/env claude` to find the claude binary on PATH.
- System prompt written to `.budahade/chat-{uuid}-prompt.md` to avoid shell escaping.
- Resume uses `--resume {sessionId}` for multi-turn continuation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project BudahADE.xcodeproj -scheme BudahADE -only-testing:BudahADETests/CLISubprocessManagerTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Agent/CLISubprocessManager.swift BudahADETests/CLISubprocessManagerTests.swift
git commit -m "feat: add CLISubprocessManager — spawn, stream-parse, cancel claude -p subprocesses"
```

---

## Task 4: AgentRole — Role Definitions + TileType Extension

**Files:**
- Create: `BudahADE/Agent/AgentRole.swift`
- Modify: `BudahADE/Plan/TileType.swift` — add `.chatAgent` case
- Read first: `BudahADE/Plan/TileType.swift` (78 LOC) — existing `AgentMode` + `TileType`
- Read first: `BudahADE/Plan/AgentPrompts.swift` (212 LOC) — existing prompt construction

`AgentRole` wraps the existing `AgentMode` enum with additional data needed for chat tiles (model default, full system prompt). The existing `AgentMode` stays as-is for terminal tiles — `AgentRole` is the chat-tile equivalent.

- [ ] **Step 1: Create AgentRole**

```swift
// BudahADE/Agent/AgentRole.swift
import SwiftUI

struct AgentRole: Equatable, Identifiable {
    let id: String              // "ideator", "developer", etc.
    let name: String
    let systemPrompt: String
    let defaultModel: AgentModel
    let color: Color

    /// Map from existing AgentMode to AgentRole
    static func from(agent: AgentMode, taskName: String, branchName: String) -> AgentRole {
        AgentRole(
            id: agent.rawValue,
            name: agent.displayName,
            systemPrompt: AgentPrompts.chatSystemPrompt(
                agent: agent,
                taskName: taskName,
                branchName: branchName
            ),
            defaultModel: agent.defaultChatModel,
            color: agent.dotColor
        )
    }

    // Built-in roles
    static let builtInRoles: [AgentMode] = AgentMode.allCases
}
```

- [ ] **Step 2: Add `defaultChatModel` to AgentMode and `chatSystemPrompt` to AgentPrompts**

In `TileType.swift`, add to `AgentMode`:

```swift
var defaultChatModel: AgentModel {
    switch self {
    case .claude:     return .sonnet
    case .researcher: return .sonnet
    case .ideator:    return .opus
    case .developer:  return .sonnet
    }
}
```

In `AgentPrompts.swift`, add a new public method:

```swift
/// System prompt for chat tile (subprocess) agents — same content as terminal prompts
/// but without output capture instructions (chat tiles handle that via stream-json).
static func chatSystemPrompt(
    agent: AgentMode,
    taskName: String,
    branchName: String,
    specFilePath: String? = nil,
    specProgress: (completed: Int, total: Int)? = nil
) -> String {
    systemPrompt(
        agent: agent,
        taskName: taskName,
        branchName: branchName,
        specFilePath: specFilePath,
        specProgress: specProgress
    )
}
```

And change `private static func systemPrompt(...)` to `static func systemPrompt(...)` (remove `private`).

- [ ] **Step 3: Add `.chatAgent` to TileType**

In `TileType.swift`, add the new case:

```swift
enum TileType: Equatable {
    case terminal(panelId: UUID, agent: AgentMode)
    case stickyNote
    case markdown(path: String)
    case image(path: String)
    case browser(url: URL?)
    case chatAgent(sessionId: UUID, role: AgentRole)  // NEW

    var displayName: String {
        switch self {
        // ... existing cases ...
        case .chatAgent(_, let role): return role.name
        }
    }

    var iconName: String {
        switch self {
        // ... existing cases ...
        case .chatAgent:              return "bubble.left.and.text.bubble.right"
        }
    }
}
```

Since `AgentRole` contains `Color` (not `Equatable` by default in some contexts), ensure `AgentRole` conforms to `Equatable` by comparing on `id` — already handled since all stored properties are `Equatable` (Color conforms in SwiftUI).

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE 2>&1 | tail -20`
Expected: Compiles. The new `.chatAgent` case in `TileType` will require exhaustive switch handling — add placeholder cases in any switch statements that match on `TileType` (e.g., `CanvasElementView`'s `TileContentView`). Use `EmptyView()` or a `Text("Chat Agent")` placeholder. The real dispatch is wired in Task 6 after `ChatTileView` and `chatSessions` exist.

- [ ] **Step 5: Commit**

```bash
git add BudahADE/Agent/AgentRole.swift BudahADE/Plan/TileType.swift BudahADE/Plan/AgentPrompts.swift BudahADE/Plan/CanvasElementView.swift
git commit -m "feat: add AgentRole, chatAgent tile type, and chat system prompt support"
```

---

## Task 5: ChatTileView — Conversation UI

**Files:**
- Create: `BudahADE/Plan/TileViews/ChatTileView.swift`
- Create: `BudahADE/Plan/TileViews/SendToMenu.swift`
- Read first: `BudahADE/Plan/TileViews/TileChrome.swift` (76 LOC) — reusable header pattern
- Read first: `BudahADE/Plan/TileViews/StickyNoteView.swift` (57 LOC) — simple tile reference
- Read first: `BudahADE/Plan/TileViews/MarkdownTileView.swift:1-60` — complex tile reference
- Read first: `BudahADE/Agent/AgentSession.swift` (Task 2) — state source
- Read first: `BudahADE/Agent/AgentRole.swift` (Task 4) — role for display

This is the largest view file. Build it incrementally: header, message list, input area, then Send To.

- [ ] **Step 1: Implement ChatTileView — header + message list**

```swift
// BudahADE/Plan/TileViews/ChatTileView.swift
import SwiftUI

struct ChatTileView: View {
    @ObservedObject var session: AgentSession
    let role: AgentRole
    @ObservedObject var canvas: PlanCanvasState
    let elementId: UUID
    let onClose: () -> Void

    @State private var inputText: String = ""
    @State private var selectedModel: AgentModel
    @State private var showSendToMenu: UUID?  // message id for active menu
    @State private var pendingImage: NSImage?  // image pasted/dropped, awaiting send
    @State private var pendingImagePath: String?  // path after saving to .budahade/images/

    init(
        session: AgentSession,
        role: AgentRole,
        canvas: PlanCanvasState,
        elementId: UUID,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.role = role
        self.canvas = canvas
        self.elementId = elementId
        self.onClose = onClose
        self._selectedModel = State(initialValue: role.defaultModel)
    }

    var body: some View {
        TileChrome(
            title: role.name,
            icon: "bubble.left.and.text.bubble.right",
            dotColor: role.color,
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                // Status bar: model picker + token count
                statusBar
                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                // Messages
                messageList

                // Input
                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
                inputArea
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Model picker
            Picker("", selection: $selectedModel) {
                ForEach(AgentModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            .font(Theme.caption(11))

            Spacer()

            // Token count
            if session.totalTokens > 0 {
                Text(session.formattedTokenCount)
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
            }

            // Menu
            Menu {
                Button("New Session") { newSession() }
                Button("Summarize & Compact") { /* Phase 3+ */ }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch session.status {
        case .streaming: return .green
        case .error:     return .red
        default:         return Theme.textMuted
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Empty state
                    if session.messages.isEmpty && session.status != .streaming {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.textMuted.opacity(0.4))
                            Text("Send a message to start the conversation")
                                .font(Theme.caption(12))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }

                    // Error banner
                    if case .error(let msg) = session.status {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text(msg)
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Button("Retry") { session.status = .idle }
                                .font(Theme.caption(11))
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.accent)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    ForEach(session.messages) { message in
                        MessageBubble(
                            message: message,
                            roleColor: role.color,
                            showSendTo: showSendToMenu == message.id,
                            onSendToTap: { showSendToMenu = showSendToMenu == message.id ? nil : message.id },
                            onSendToSpec: { sendToSpec(message) },
                            onSendToAgent: { agentMode in sendToAgent(message, agentMode: agentMode) }
                        )
                        .id(message.id)
                    }

                    // Streaming indicator
                    if session.status == .streaming {
                        if !session.currentStreamingText.isEmpty {
                            streamingBubble
                        } else {
                            thinkingIndicator
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.count) { _ in
                if let lastId = session.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var streamingBubble: some View {
        HStack {
            Text(session.currentStreamingText)
                .font(Theme.body(13))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Theme.surface2.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(role.color.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(10)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 6) {
            // Image preview (if pasted/dropped)
            if let image = pendingImage {
                HStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        pendingImage = nil
                        pendingImagePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .lineLimit(1...5)
                    .onSubmit { sendMessage() }
                    .padding(8)
                    .background(Theme.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImage == nil
                            ? Theme.textMuted
                            : Theme.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    (inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImage == nil)
                    || session.status == .streaming
                )
            }
            .padding(10)
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleImageDrop(providers)
        }
        // Cmd+V paste handler for images
        .onPasteCommand(of: [.png, .tiff]) { providers in
            handleImagePaste(providers)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }

        // Build prompt with optional image reference
        var prompt = text
        if let imagePath = pendingImagePath {
            prompt += (text.isEmpty ? "" : "\n\n") + "[Image: \(imagePath)]"
        }

        inputText = ""
        pendingImage = nil
        pendingImagePath = nil
        canvas.sendChatMessage(sessionId: session.id, prompt: prompt, model: selectedModel)
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let path = self.saveImage(data: data)
            DispatchQueue.main.async {
                self.pendingImage = image
                self.pendingImagePath = path
            }
        }
        return true
    }

    private func handleImagePaste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
            guard let data, let image = NSImage(data: data) else { return }
            let path = self.saveImage(data: data)
            DispatchQueue.main.async {
                self.pendingImage = image
                self.pendingImagePath = path
            }
        }
    }

    private func saveImage(data: Data) -> String {
        let dir = (canvas.worktreePath as NSString)
            .appendingPathComponent(".budahade/images")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let filename = "\(UUID().uuidString).png"
        let path = (dir as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func newSession() {
        // Clear messages and session ID to start fresh
        session.messages.removeAll()
        session.claudeSessionId = nil
        session.totalInputTokens = 0
        session.totalOutputTokens = 0
        session.status = .idle
    }

    private func sendToSpec(_ message: ChatMessage) {
        canvas.sendToSpec(content: message.content, fromAgent: role.name)
        showSendToMenu = nil
    }

    private func sendToAgent(_ message: ChatMessage, agentMode: AgentMode) {
        canvas.sendToAgent(content: message.content, fromAgent: role.name, targetAgent: agentMode)
        showSendToMenu = nil
    }
}
```

- [ ] **Step 2: Implement MessageBubble and SendToMenu**

```swift
// Append to ChatTileView.swift or add as extension

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let roleColor: Color
    let showSendTo: Bool
    let onSendToTap: () -> Void
    let onSendToSpec: () -> Void
    let onSendToAgent: (AgentMode) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.role == .user { Spacer(minLength: 40) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.textPrimary)
                        .textSelection(.enabled)

                    // Collapsed tool calls
                    if let tools = message.toolCalls, !tools.isEmpty {
                        DisclosureGroup {
                            ForEach(tools, id: \.id) { tool in
                                Text(tool.name)
                                    .font(Theme.caption(11))
                                    .foregroundColor(Theme.textMuted)
                            }
                        } label: {
                            Text("> \(tools.count) tool call\(tools.count == 1 ? "" : "s")")
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                }
                .padding(10)
                .background(
                    message.role == .user
                    ? Theme.accent.opacity(0.15)
                    : Theme.surface2.opacity(0.6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if message.role != .user { Spacer(minLength: 40) }
            }

            // "Send to" button (assistant messages only)
            if message.role == .assistant {
                HStack(spacing: 4) {
                    Button(action: onSendToTap) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 9))
                            Text("Send to")
                                .font(Theme.caption(10))
                        }
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(showSendTo ? Theme.hoverFill : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    if showSendTo {
                        SendToMenu(
                            onSendToSpec: onSendToSpec,
                            onSendToAgent: onSendToAgent
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
    }
}
```

```swift
// BudahADE/Plan/TileViews/SendToMenu.swift
import SwiftUI

struct SendToMenu: View {
    let onSendToSpec: () -> Void
    let onSendToAgent: (AgentMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                onSendToSpec()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text("Spec")
                        .font(Theme.caption(10))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            ForEach(AgentMode.allCases) { agent in
                Button {
                    onSendToAgent(agent)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(agent.dotColor)
                            .frame(width: 5, height: 5)
                        Text(agent.displayName)
                            .font(Theme.caption(10))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 3: Build to check compilation**

Run: `xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE 2>&1 | tail -30`
Expected: May fail on missing `canvas.chatSessions`, `canvas.sendChatMessage`, `canvas.sendToSpec`, `canvas.sendToAgent` — these are wired up in Task 6.

- [ ] **Step 4: Commit**

```bash
git add BudahADE/Plan/TileViews/ChatTileView.swift BudahADE/Plan/TileViews/SendToMenu.swift
git commit -m "feat: add ChatTileView with message bubbles, input area, model picker, Send To menu"
```

---

## Task 6: Wire Everything Together — PlanCanvasState + AddTileMenu

**Files:**
- Modify: `BudahADE/Plan/PlanCanvasState.swift` — add chat session management, `sendChatMessage`, `sendToSpec`, `sendToAgent`
- Modify: `BudahADE/Plan/AddTileMenu.swift` — add "Chat Agent" section
- Modify: `BudahADE/Plan/PlanCanvasView.swift` — wire new AddTileMenu callback
- Read first: `BudahADE/Plan/PlanCanvasState.swift:1-110` — existing addTile pattern
- Read first: `BudahADE/Plan/PlanCanvasView.swift` — context menu wiring
- Read first: `BudahADE/Plan/TileViews/MarkdownTileView.swift:250-311` — for understanding spec tile interaction

- [ ] **Step 1: Add chat session state to PlanCanvasState**

Add these properties after `@Published var terminals`:

```swift
// Chat agent sessions
@Published var chatSessions: [UUID: AgentSession] = [:]
let chatManager = CLISubprocessManager()
```

- [ ] **Step 2: Add `addChatTile()` method to PlanCanvasState**

Add after the existing `addTerminalTile` method:

```swift
/// Add a chat agent tile to the canvas
@discardableResult
func addChatTile(agent: AgentMode, at position: CGPoint, parentFrameId: UUID? = nil) -> UUID {
    let role = AgentRole.from(agent: agent, taskName: taskName, branchName: branchName)
    let session = chatManager.createSession(
        model: role.defaultModel,
        agentMode: agent,
        systemPrompt: role.systemPrompt,
        workingDirectory: worktreePath
    )
    chatSessions[session.id] = session

    let element = CanvasElement(
        kind: .tile(.chatAgent(sessionId: session.id, role: role)),
        position: position,
        size: CGSize(width: 400, height: 500),
        title: role.name
    )

    if let frameId = parentFrameId {
        insertIntoFrame(element, frameId: frameId)
    } else {
        elements.append(element)
    }

    didMutate()
    return element.id
}
```

- [ ] **Step 3: Add `sendChatMessage`, `sendToSpec`, `sendToAgent` methods**

```swift
/// Send a message to a chat agent session (model override for per-turn switching)
func sendChatMessage(sessionId: UUID, prompt: String, model: AgentModel) {
    chatManager.send(sessionId: sessionId, prompt: prompt, model: model)
}

/// Send content to the spec tile (creates a new section in the first markdown tile)
func sendToSpec(content: String, fromAgent: String) {
    // Find the first markdown tile on the canvas
    guard let specElement = allTiles.first(where: {
        if case .tile(.markdown) = $0.kind { return true }
        return false
    }),
    case .tile(.markdown(let path)) = specElement.kind else { return }

    // Append a new section to the spec file
    let section = """

    ## From \(fromAgent)

    <!-- source: \(fromAgent.lowercased()) -->

    \(content)
    """

    if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
        try? (existing + "\n" + section).write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Send content to another agent's next turn context
func sendToAgent(content: String, fromAgent: String, targetAgent: AgentMode) {
    // Find or create a chat tile for the target agent
    let targetSession: AgentSession
    if let existing = chatSessions.values.first(where: { $0.agentMode == targetAgent }) {
        targetSession = existing
    } else {
        // Create a new chat tile for the target agent
        let pos = nextFreePosition(size: CGSize(width: 400, height: 500))
        let elementId = addChatTile(agent: targetAgent, at: pos)
        guard let element = findElement(elementId),
              case .tile(.chatAgent(let sessionId, _)) = element.kind,
              let session = chatSessions[sessionId] else { return }
        targetSession = session
    }

    // Inject context as a system-style message visible in the chat
    let contextMessage = ChatMessage(
        role: .system,
        content: "Context from \(fromAgent):\n\n\(content)"
    )
    targetSession.messages.append(contextMessage)
}
```

- [ ] **Step 4: Add cleanup — both `closeAll()` and individual tile removal**

In the existing `closeAll()` method, add:

```swift
// Cancel all chat sessions
for sessionId in chatSessions.keys {
    chatManager.cancel(sessionId: sessionId)
}
chatSessions.removeAll()
```

In the existing `removeElement(_ id:)` method, add chat session cleanup before the element is removed:

```swift
// If removing a chat agent tile, clean up its session and process
if let element = findElement(id),
   case .tile(.chatAgent(let sessionId, _)) = element.kind {
    chatManager.cancel(sessionId: sessionId)
    chatSessions.removeValue(forKey: sessionId)
}
```

This prevents orphaned `claude -p` processes when users close individual chat tiles.

- [ ] **Step 5: Update AddTileMenu with chat agent option**

Add a new callback and section to `AddTileMenu`:

```swift
// New property:
let onAddChatAgent: (AgentMode) -> Void

// In body, after the terminal agents ForEach and before the divider,
// add a second section:

Rectangle()
    .fill(Theme.borderSubtle)
    .frame(height: 1)
    .padding(.vertical, 4)

Text("Chat Agents")
    .font(Theme.caption(10))
    .foregroundColor(Theme.textMuted)
    .padding(.horizontal, 10)
    .padding(.bottom, 2)

ForEach(AgentMode.allCases) { agent in
    Button {
        onAddChatAgent(agent)
        dismiss()
    } label: {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 10))
                .foregroundColor(agent.dotColor)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(agent.displayName) Chat")
                    .font(Theme.label(13))
                    .foregroundColor(Theme.textPrimary)
                Text("Lightweight, no skills")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hoveredChatAgent == agent ? Theme.hoverFill : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
        hoveredChatAgent = hovering ? agent : nil
    }
}
```

Also add `@State private var hoveredChatAgent: AgentMode?` alongside the existing `hoveredAgent` state to avoid hover collision between the two agent sections.

Also rename the existing terminal section header — add "Terminal Agents" label above the existing agent rows for clarity.

- [ ] **Step 6: Update CanvasElementView — real ChatTileView dispatch**

In `BudahADE/Plan/CanvasElementView.swift`, replace the placeholder `.chatAgent` case in `TileContentView.body` with the real dispatch:

```swift
case .chatAgent(let sessionId, let role):
    if let session = canvas.chatSessions[sessionId] {
        ChatTileView(session: session, role: role, canvas: canvas, elementId: elementId) {
            canvas.removeElement(elementId)
        }
    }
```

- [ ] **Step 7: Wire `onAddChatAgent` in PlanCanvasView**

In `PlanCanvasView.swift`, wherever `AddTileMenu` is instantiated, add the new callback:

```swift
onAddChatAgent: { agent in
    let pos = canvas.screenToCanvas(menuPosition)
    canvas.addChatTile(agent: agent, at: pos)
}
```

- [ ] **Step 8: Build the full project**

Run: `xcodebuild build -project BudahADE.xcodeproj -scheme BudahADE 2>&1 | tail -30`
Expected: PASS — all pieces connected

- [ ] **Step 9: Commit**

```bash
git add BudahADE/Plan/PlanCanvasState.swift BudahADE/Plan/AddTileMenu.swift BudahADE/Plan/PlanCanvasView.swift
git commit -m "feat: wire chat agent tiles into canvas — add/send/close lifecycle complete"
```

---

## Task 7: Integration Testing + Polish

**Files:**
- All files from Tasks 1-6
- May modify: `BudahADE/Agent/CLISubprocessManager.swift` — fixes from integration
- May modify: `BudahADE/Plan/TileViews/ChatTileView.swift` — UI polish

This task verifies the Phase 2 Verification checklist from the spec.

- [ ] **Step 1: Manual test — spawn chat agent, send message, verify multi-turn**

1. Build and run the app
2. Create a new task
3. Enter Plan mode
4. Right-click canvas → Add Chat Agent (any role)
5. Type a message and send
6. Verify: user message appears right-aligned, agent response appears left-aligned
7. Send a follow-up → verify multi-turn works (session-id reuse)

- [ ] **Step 2: Manual test — cancel mid-stream**

1. Send a long prompt (e.g., "Write a 500-word essay on Swift concurrency")
2. While streaming, close the tile
3. Verify: process terminates cleanly, no crash, no orphaned processes
4. Check: `ps aux | grep "claude -p"` shows no lingering processes

- [ ] **Step 3: Manual test — model switching**

1. Open a chat agent tile
2. Change model picker from Sonnet to Haiku
3. Send a message
4. Verify the response uses the selected model (check stream-json output)

- [ ] **Step 4: Manual test — Send to Spec**

1. Have a markdown tile on canvas with a spec file
2. Have a chat agent tile
3. Get an agent response
4. Click "Send to" → "Spec"
5. Verify: new section appears in spec file with source attribution

- [ ] **Step 5: Manual test — Send to Agent**

1. Have two chat agent tiles (e.g., Ideator + Developer)
2. Get a response from Ideator
3. Click "Send to" → Developer
4. Verify: Developer tile shows context injection message

- [ ] **Step 6: Manual test — token tracking**

1. Send several messages to a chat agent
2. Verify: token count in header updates after each turn
3. Values should be plausible (not zero, increases with each turn)

- [ ] **Step 7: Manual test — agent roles**

1. Create Ideator (should default to Opus)
2. Create Developer (should default to Sonnet)
3. Verify system prompts apply (check .budahade/chat-*-prompt.md files)

- [ ] **Step 8: Manual test — image paste**

1. Copy an image to clipboard
2. Paste into chat tile input area (Cmd+V)
3. Verify: thumbnail preview appears above input field
4. Verify: X button removes the pending image
5. Send with text — verify image saved to `.budahade/images/{uuid}.png`
6. Verify: image path referenced in the prompt sent to agent
7. Also test drag-and-drop from Finder — same result

- [ ] **Step 9: Manual test — empty + error states**

1. Create a new chat tile — verify empty state placeholder shows ("Send a message to start...")
2. Send a message — verify placeholder disappears
3. If possible, trigger an error (e.g., kill claude binary temporarily) — verify red error banner with message and Retry button

- [ ] **Step 10: Fix any issues found during testing**

Address bugs, UI polish, edge cases discovered during Steps 1-7.

- [ ] **Step 11: Commit fixes**

```bash
git add -A
git commit -m "fix: integration testing fixes for Phase 2 chat agent system"
```

---

## Dependency Graph

```
Task 1 (ChatMessage + StreamEvent)
  ↓
Task 2 (AgentSession) ← depends on Task 1
  ↓
Task 3 (CLISubprocessManager) ← depends on Task 2
  ↓
Task 4 (AgentRole + TileType) ← depends on Task 2 (AgentModel), Task 1
  ↓
Task 5 (ChatTileView + SendToMenu) ← depends on Tasks 2, 4
  ↓
Task 6 (Wire together) ← depends on Tasks 3, 4, 5
  ↓
Task 7 (Integration testing) ← depends on Task 6
```

Tasks 1-3 are strictly sequential (each builds on prior).
Task 4 can start after Task 2.
Task 5 can start after Tasks 2 + 4.
Task 6 requires all of 3, 4, 5.
Task 7 requires 6.
