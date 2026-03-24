import XCTest
@testable import BudahADE

final class ChatMessageTests: XCTestCase {

    // MARK: - ChatMessage Construction

    func testChatMessageConstruction() {
        let msg = ChatMessage(
            role: .user,
            content: "Hello world"
        )
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello world")
        XCTAssertNil(msg.toolCalls)
        XCTAssertEqual(msg.inputTokens, 0)
        XCTAssertEqual(msg.outputTokens, 0)
    }

    func testChatMessageTokenCountComputation() {
        let msg = ChatMessage(
            role: .assistant,
            content: "Test",
            inputTokens: 100,
            outputTokens: 50
        )
        XCTAssertEqual(msg.totalTokens, 150)
    }

    func testChatMessageIdentifiable() {
        let msg1 = ChatMessage(role: .user, content: "Hello")
        let msg2 = ChatMessage(role: .user, content: "Hello")
        XCTAssertNotEqual(msg1.id, msg2.id)
    }

    func testChatMessageEquatable() {
        let id = UUID()
        let timestamp = Date()
        let msg1 = ChatMessage(
            id: id,
            role: .user,
            content: "Hello",
            timestamp: timestamp,
            inputTokens: 10,
            outputTokens: 20
        )
        let msg2 = ChatMessage(
            id: id,
            role: .user,
            content: "Hello",
            timestamp: timestamp,
            inputTokens: 10,
            outputTokens: 20
        )
        XCTAssertEqual(msg1, msg2)
    }

    // MARK: - StreamEvent Parsing

    func testParseSystemInitEvent() throws {
        let json = """
        {
            "type": "system",
            "session_id": "abc123",
            "tools": ["tool1", "tool2"],
            "model": "claude-3-5-sonnet-20241022"
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .system(let info):
            XCTAssertEqual(info.sessionId, "abc123")
            XCTAssertEqual(info.tools, ["tool1", "tool2"])
            XCTAssertEqual(info.model, "claude-3-5-sonnet-20241022")
        default:
            XCTFail("Expected .system event, got \(event)")
        }
    }

    func testParseSystemEventWithoutOptionals() throws {
        let json = """
        {
            "type": "system",
            "session_id": "xyz789"
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .system(let info):
            XCTAssertEqual(info.sessionId, "xyz789")
            XCTAssertNil(info.tools)
            XCTAssertNil(info.model)
        default:
            XCTFail("Expected .system event")
        }
    }

    func testParseAssistantTextEvent() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "text",
                        "text": "This is a response"
                    }
                ],
                "role": "assistant",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50
                },
                "model": "claude-3-5-sonnet-20241022"
            }
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .assistant(let msg):
            XCTAssertEqual(msg.content, "This is a response")
            XCTAssertEqual(msg.role, .assistant)
            XCTAssertEqual(msg.inputTokens, 100)
            XCTAssertEqual(msg.outputTokens, 50)
            XCTAssertEqual(msg.model, "claude-3-5-sonnet-20241022")
            XCTAssertNil(msg.toolCalls)
        default:
            XCTFail("Expected .assistant event")
        }
    }

    func testParseAssistantWithToolUse() throws {
        let json = """
        {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "text",
                        "text": "I'll use a tool"
                    },
                    {
                        "type": "tool_use",
                        "id": "tool_call_123",
                        "name": "search",
                        "input": {"query": "climate change"}
                    }
                ],
                "role": "assistant",
                "usage": {
                    "input_tokens": 200,
                    "output_tokens": 75
                }
            }
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .assistant(let msg):
            XCTAssertEqual(msg.content, "I'll use a tool")
            XCTAssertNotNil(msg.toolCalls)
            XCTAssertEqual(msg.toolCalls?.count, 1)
            XCTAssertEqual(msg.toolCalls?[0].id, "tool_call_123")
            XCTAssertEqual(msg.toolCalls?[0].name, "search")
            XCTAssertEqual(msg.toolCalls?[0].input, """
            {
              "query" : "climate change"
            }
            """)
        default:
            XCTFail("Expected .assistant event")
        }
    }

    func testParseContentBlockDelta() throws {
        let json = """
        {
            "type": "content_block_delta",
            "delta": {
                "type": "text_delta",
                "text": "streaming text"
            }
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .contentDelta(let text):
            XCTAssertEqual(text, "streaming text")
        default:
            XCTFail("Expected .contentDelta event")
        }
    }

    func testParseResultEvent() throws {
        let json = """
        {
            "type": "result",
            "cost_usd": 0.00123,
            "duration_ms": 1500,
            "session_id": "sess_456",
            "usage": {
                "input_tokens": 250,
                "output_tokens": 100
            }
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .result(let info):
            XCTAssertEqual(info.costUSD, 0.00123, accuracy: 0.000001)
            XCTAssertEqual(info.durationMs, 1500)
            XCTAssertEqual(info.sessionId, "sess_456")
            XCTAssertEqual(info.inputTokens, 250)
            XCTAssertEqual(info.outputTokens, 100)
        default:
            XCTFail("Expected .result event")
        }
    }

    func testParseResultEventWithoutOptionals() throws {
        let json = """
        {
            "type": "result",
            "cost_usd": 0.001,
            "usage": {
                "input_tokens": 100,
                "output_tokens": 50
            }
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .result(let info):
            XCTAssertEqual(info.costUSD, 0.001, accuracy: 0.000001)
            XCTAssertNil(info.durationMs)
            XCTAssertNil(info.sessionId)
        default:
            XCTFail("Expected .result event")
        }
    }

    func testParseUnknownEvent() throws {
        let json = """
        {
            "type": "unknown_type",
            "data": "some data"
        }
        """
        let event = try StreamEvent.parse(from: json)

        switch event {
        case .unknown:
            // Expected
            break
        default:
            XCTFail("Expected .unknown event")
        }
    }

    // MARK: - Error Handling

    func testParseInvalidJSON() {
        let json = "not valid json {"
        XCTAssertThrowsError(try StreamEvent.parse(from: json)) { error in
            XCTAssertTrue(error is StreamParseError)
        }
    }

    func testParseMissingType() {
        let json = """
        {
            "session_id": "abc123"
        }
        """
        XCTAssertThrowsError(try StreamEvent.parse(from: json)) { error in
            if let parseError = error as? StreamParseError {
                XCTAssertEqual(parseError, .missingType)
            } else {
                XCTFail("Expected StreamParseError")
            }
        }
    }

    func testParseMultipleEvents() throws {
        let jsonLines = """
        {"type": "system", "session_id": "sess_1"}
        {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "hello"}}
        """

        let lines = jsonLines.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let event = try StreamEvent.parse(from: String(line))
            XCTAssertNotNil(event)
        }
    }
}
