import XCTest
@testable import BudahADE

@MainActor
final class AgentSessionTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test prompt",
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(session.status, .idle)
        XCTAssertEqual(session.messages, [])
        XCTAssertEqual(session.totalInputTokens, 0)
        XCTAssertEqual(session.totalOutputTokens, 0)
        XCTAssertNil(session.claudeSessionId)
        XCTAssertEqual(session.currentStreamingText, "")
    }

    func testSessionIdentifiable() {
        let session1 = AgentSession(
            model: .haiku,
            agentMode: .ideator,
            systemPrompt: "Prompt",
            workingDirectory: "/tmp"
        )
        let session2 = AgentSession(
            model: .haiku,
            agentMode: .ideator,
            systemPrompt: "Prompt",
            workingDirectory: "/tmp"
        )
        XCTAssertNotEqual(session1.id, session2.id)
    }

    // MARK: - AgentModel Enum

    func testAgentModelCliFlags() {
        XCTAssertEqual(AgentModel.haiku.cliFlag, "haiku")
        XCTAssertEqual(AgentModel.sonnet.cliFlag, "sonnet")
        XCTAssertEqual(AgentModel.opus.cliFlag, "opus")
    }

    func testAgentModelDisplayNames() {
        XCTAssertEqual(AgentModel.haiku.displayName, "Haiku")
        XCTAssertEqual(AgentModel.sonnet.displayName, "Sonnet")
        XCTAssertEqual(AgentModel.opus.displayName, "Opus")
    }

    func testAgentModelIdentifiable() {
        XCTAssertEqual(AgentModel.haiku.id, "haiku")
        XCTAssertEqual(AgentModel.sonnet.id, "sonnet")
        XCTAssertEqual(AgentModel.opus.id, "opus")
    }

    func testAgentModelCaseIterable() {
        let models = AgentModel.allCases
        XCTAssertEqual(models.count, 3)
        XCTAssertTrue(models.contains(.haiku))
        XCTAssertTrue(models.contains(.sonnet))
        XCTAssertTrue(models.contains(.opus))
    }

    // MARK: - Agent Mode Tracking

    func testAgentModeTracking() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .developer,
            systemPrompt: "Dev prompt",
            workingDirectory: "/tmp"
        )
        XCTAssertEqual(session.agentMode, .developer)
    }

    func testAgentModeNil() {
        let session = AgentSession(
            model: .opus,
            agentMode: nil,
            systemPrompt: "Generic",
            workingDirectory: "/tmp"
        )
        XCTAssertNil(session.agentMode)
    }

    // MARK: - Model Mutability

    func testModelMutable() {
        let session = AgentSession(
            model: .haiku,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        XCTAssertEqual(session.model, .haiku)
        session.model = .opus
        XCTAssertEqual(session.model, .opus)
    }

    // MARK: - User Message

    func testAddUserMessage() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        session.addUserMessage("Hello world")

        XCTAssertEqual(session.messages.count, 1)
        let msg = session.messages[0]
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello world")
    }

    func testAddMultipleUserMessages() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )
        session.addUserMessage("First")
        session.addUserMessage("Second")

        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.messages[0].content, "First")
        XCTAssertEqual(session.messages[1].content, "Second")
    }

    // MARK: - Assistant Message

    func testHandleAssistantMessage() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let assistantMsg = StreamEvent.AssistantMessage(
            content: "Response text",
            role: .assistant,
            inputTokens: 10,
            outputTokens: 20
        )
        session.handleAssistantMessage(assistantMsg)

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages[0].role, .assistant)
        XCTAssertEqual(session.messages[0].content, "Response text")
        XCTAssertEqual(session.totalInputTokens, 10)
        XCTAssertEqual(session.totalOutputTokens, 20)
        XCTAssertEqual(session.currentStreamingText, "")
    }

    func testHandleAssistantMessageAccumulatesTokens() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let msg1 = StreamEvent.AssistantMessage(
            content: "First",
            role: .assistant,
            inputTokens: 5,
            outputTokens: 10
        )
        session.handleAssistantMessage(msg1)

        let msg2 = StreamEvent.AssistantMessage(
            content: "Second",
            role: .assistant,
            inputTokens: 8,
            outputTokens: 15
        )
        session.handleAssistantMessage(msg2)

        XCTAssertEqual(session.totalInputTokens, 13)
        XCTAssertEqual(session.totalOutputTokens, 25)
        XCTAssertEqual(session.messages.count, 2)
    }

    // MARK: - Content Delta

    func testHandleContentDelta() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        session.handleContentDelta("Hello ")
        XCTAssertEqual(session.currentStreamingText, "Hello ")

        session.handleContentDelta("world")
        XCTAssertEqual(session.currentStreamingText, "Hello world")
    }

    // MARK: - System Init

    func testHandleSystemInit() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let systemInfo = StreamEvent.SystemInfo(
            sessionId: "test-session-123",
            tools: ["search", "calculate"],
            model: "claude-3-5-sonnet-20241022"
        )
        session.handleSystemInit(systemInfo)

        XCTAssertEqual(session.claudeSessionId, "test-session-123")
    }

    // MARK: - Result Handling

    func testHandleResult() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let resultInfo = StreamEvent.ResultInfo(
            costUSD: 0.001,
            durationMs: 500,
            sessionId: "result-session-456",
            inputTokens: 100,
            outputTokens: 50
        )
        session.handleResult(resultInfo)

        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.claudeSessionId, "result-session-456")
    }

    func testHandleResultDoesNotOverwriteSessionId() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        // Set session ID from system init
        let systemInfo = StreamEvent.SystemInfo(
            sessionId: "initial-session",
            tools: nil,
            model: nil
        )
        session.handleSystemInit(systemInfo)

        // Result with different session ID should not overwrite
        let resultInfo = StreamEvent.ResultInfo(
            costUSD: 0.001,
            durationMs: 500,
            sessionId: "result-session",
            inputTokens: 100,
            outputTokens: 50
        )
        session.handleResult(resultInfo)

        XCTAssertEqual(session.claudeSessionId, "initial-session")
    }

    func testHandleResultSetsSessionIdIfNil() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        XCTAssertNil(session.claudeSessionId)

        let resultInfo = StreamEvent.ResultInfo(
            costUSD: 0.001,
            durationMs: 500,
            sessionId: "from-result",
            inputTokens: 100,
            outputTokens: 50
        )
        session.handleResult(resultInfo)

        XCTAssertEqual(session.claudeSessionId, "from-result")
    }

    // MARK: - Token Formatting

    func testFormattedTokenCountUnder1000() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let msg1 = StreamEvent.AssistantMessage(
            content: "Test",
            role: .assistant,
            inputTokens: 100,
            outputTokens: 50
        )
        session.handleAssistantMessage(msg1)

        XCTAssertEqual(session.formattedTokenCount, "150")
    }

    func testFormattedTokenCountOver1000() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let msg1 = StreamEvent.AssistantMessage(
            content: "Test",
            role: .assistant,
            inputTokens: 2000,
            outputTokens: 1500
        )
        session.handleAssistantMessage(msg1)

        XCTAssertEqual(session.formattedTokenCount, "3.5k")
    }

    func testFormattedTokenCountExactly1000() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let msg1 = StreamEvent.AssistantMessage(
            content: "Test",
            role: .assistant,
            inputTokens: 1000,
            outputTokens: 0
        )
        session.handleAssistantMessage(msg1)

        XCTAssertEqual(session.formattedTokenCount, "1.0k")
    }

    func testFormattedTokenCountZero() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(session.formattedTokenCount, "0")
    }

    // MARK: - Total Tokens

    func testTotalTokens() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        let msg = StreamEvent.AssistantMessage(
            content: "Test",
            role: .assistant,
            inputTokens: 150,
            outputTokens: 350
        )
        session.handleAssistantMessage(msg)

        XCTAssertEqual(session.totalTokens, 500)
    }

    // MARK: - Status Management

    func testStatusTransitions() {
        let session = AgentSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test",
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(session.status, .idle)

        let resultInfo = StreamEvent.ResultInfo(
            costUSD: 0.001,
            durationMs: 500,
            sessionId: "sess",
            inputTokens: 100,
            outputTokens: 50
        )
        session.handleResult(resultInfo)

        XCTAssertEqual(session.status, .done)
    }
}
