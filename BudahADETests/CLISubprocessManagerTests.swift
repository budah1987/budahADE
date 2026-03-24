import XCTest
@testable import BudahADE

@MainActor
final class CLISubprocessManagerTests: XCTestCase {

    // MARK: - testSpawnCreatesSession

    func testSpawnCreatesSession() {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .sonnet,
            agentMode: .claude,
            systemPrompt: "Test prompt",
            workingDirectory: "/tmp"
        )

        XCTAssertNotNil(manager.sessions[session.id])
        XCTAssertEqual(session.status, .idle)
        XCTAssertEqual(session.model, .sonnet)
        XCTAssertEqual(session.systemPrompt, "Test prompt")
        XCTAssertEqual(session.workingDirectory, "/tmp")
    }

    // MARK: - testCancelSetsStatusAndKillsProcess

    func testCancelSetsStatusAndKillsProcess() {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .sonnet,
            agentMode: nil,
            systemPrompt: "Prompt",
            workingDirectory: "/tmp"
        )

        // Simulate streaming state
        session.status = .streaming

        manager.cancel(sessionId: session.id)

        XCTAssertEqual(session.status, .idle)
        XCTAssertNil(session.process)
        XCTAssertEqual(session.currentStreamingText, "")
    }

    // MARK: - testBuildCommandString

    func testBuildCommandString() {
        let manager = CLISubprocessManager()
        let cmd = manager.buildCommand(
            prompt: "Hello world",
            model: .sonnet,
            systemPromptPath: "/tmp/prompt.md",
            sessionId: nil
        )

        XCTAssertTrue(cmd.contains("claude"), "Should contain 'claude'")
        XCTAssertTrue(cmd.contains("-p"), "Should contain '-p'")
        XCTAssertTrue(cmd.contains("Hello world"), "Should contain the prompt")
        XCTAssertTrue(cmd.contains("--output-format"), "Should contain '--output-format'")
        XCTAssertTrue(cmd.contains("stream-json"), "Should contain 'stream-json'")
        XCTAssertTrue(cmd.contains("--model"), "Should contain '--model'")
        XCTAssertTrue(cmd.contains("sonnet"), "Should contain 'sonnet'")
        XCTAssertTrue(cmd.contains("--system-prompt-file"), "Should contain '--system-prompt-file'")
        XCTAssertTrue(cmd.contains("/tmp/prompt.md"), "Should contain the system prompt path")
        XCTAssertTrue(cmd.contains("--dangerously-skip-permissions"), "Should contain '--dangerously-skip-permissions'")
        XCTAssertFalse(cmd.contains("--resume"), "Should not contain '--resume' when sessionId is nil")
    }

    // MARK: - testBuildResumeCommand

    func testBuildResumeCommand() {
        let manager = CLISubprocessManager()
        let cmd = manager.buildCommand(
            prompt: "Continue",
            model: .haiku,
            systemPromptPath: "/tmp/p.md",
            sessionId: "sess-abc"
        )

        XCTAssertTrue(cmd.contains("--resume"), "Should contain '--resume'")
        XCTAssertTrue(cmd.contains("sess-abc"), "Should contain the session ID")
    }

    // MARK: - testParseStreamLines

    func testParseStreamLines() {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .sonnet,
            agentMode: .developer,
            systemPrompt: "Dev prompt",
            workingDirectory: "/tmp"
        )
        session.status = .streaming

        // Line 1: system init
        let systemLine = """
        {"type":"system","session_id":"test-session-xyz","tools":[],"model":"claude-3-5-sonnet-20241022"}
        """
        manager.processStreamLine(systemLine, session: session)
        XCTAssertEqual(session.claudeSessionId, "test-session-xyz")

        // Line 2: assistant message
        let assistantLine = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello!"}],"usage":{"input_tokens":10,"output_tokens":5},"model":"claude-3-5-sonnet-20241022"}}
        """
        manager.processStreamLine(assistantLine, session: session)
        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.messages[0].content, "Hello!")

        // Line 3: result
        let resultLine = """
        {"type":"result","cost_usd":0.001,"duration_ms":500,"session_id":"test-session-xyz","usage":{"input_tokens":10,"output_tokens":5}}
        """
        manager.processStreamLine(resultLine, session: session)
        XCTAssertEqual(session.status, .done)
    }

    // MARK: - testRemoveSession

    func testRemoveSession() {
        let manager = CLISubprocessManager()
        let session = manager.createSession(
            model: .opus,
            agentMode: nil,
            systemPrompt: "Prompt",
            workingDirectory: "/tmp"
        )

        XCTAssertNotNil(manager.sessions[session.id])

        manager.removeSession(sessionId: session.id)

        XCTAssertNil(manager.sessions[session.id])
    }

    // MARK: - testTotalTokensAllSessions

    func testTotalTokensAllSessions() {
        let manager = CLISubprocessManager()

        let session1 = manager.createSession(
            model: .sonnet,
            agentMode: nil,
            systemPrompt: "Prompt 1",
            workingDirectory: "/tmp"
        )
        let session2 = manager.createSession(
            model: .haiku,
            agentMode: nil,
            systemPrompt: "Prompt 2",
            workingDirectory: "/tmp"
        )

        // Add tokens via assistant messages
        let msg1 = StreamEvent.AssistantMessage(
            content: "Response 1",
            role: .assistant,
            inputTokens: 100,
            outputTokens: 50
        )
        session1.handleAssistantMessage(msg1)

        let msg2 = StreamEvent.AssistantMessage(
            content: "Response 2",
            role: .assistant,
            inputTokens: 200,
            outputTokens: 80
        )
        session2.handleAssistantMessage(msg2)

        XCTAssertEqual(manager.totalTokensAllSessions, 430)
    }

    // MARK: - testActiveSessionCount

    func testActiveSessionCount() {
        let manager = CLISubprocessManager()

        let session1 = manager.createSession(
            model: .sonnet,
            agentMode: nil,
            systemPrompt: "Prompt 1",
            workingDirectory: "/tmp"
        )
        let session2 = manager.createSession(
            model: .haiku,
            agentMode: nil,
            systemPrompt: "Prompt 2",
            workingDirectory: "/tmp"
        )

        // Initially both idle
        XCTAssertEqual(manager.activeSessionCount, 0)

        // Set one to streaming
        session1.status = .streaming

        XCTAssertEqual(manager.activeSessionCount, 1)

        // Set the other to done
        session2.status = .done

        XCTAssertEqual(manager.activeSessionCount, 2)

        // Cancel the streaming one
        manager.cancel(sessionId: session1.id)

        XCTAssertEqual(manager.activeSessionCount, 1)
    }
}
