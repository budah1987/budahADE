import XCTest
@testable import BudahADE

final class CrossTabContextTests: XCTestCase {

    func testSiblingContextBlock() {
        // Create sample messages for a research sibling
        let msg1 = ChatMessage(
            role: .user,
            content: "Research the current Swift concurrency best practices."
        )
        let msg2 = ChatMessage(
            role: .assistant,
            content: "Swift concurrency uses async/await and structured concurrency with actors."
        )

        // Create a ConversationSnapshot for the researcher
        let researcherSnapshot = ConversationSnapshot(
            tabId: UUID(),
            role: .researcher,
            messages: [msg1, msg2]
        )

        // Create sample messages for an ideator sibling
        let msg3 = ChatMessage(
            role: .user,
            content: "What features should we prioritize?"
        )
        let msg4 = ChatMessage(
            role: .assistant,
            content: "We should focus on performance and user experience."
        )

        let ideatorSnapshot = ConversationSnapshot(
            tabId: UUID(),
            role: .ideator,
            messages: [msg3, msg4]
        )

        // Call siblingContextBlock with both snapshots
        let context = AgentPrompts.siblingContextBlock(from: [researcherSnapshot, ideatorSnapshot])

        // Assert the header is present
        XCTAssertTrue(context.contains("## Context from other planning conversations"))

        // Assert role names are present
        XCTAssertTrue(context.contains("Research Expert"))
        XCTAssertTrue(context.contains("Ideation Partner"))

        // Assert message content is present
        XCTAssertTrue(context.contains("Research the current Swift concurrency best practices"))
        XCTAssertTrue(context.contains("Swift concurrency uses async/await"))
        XCTAssertTrue(context.contains("What features should we prioritize?"))
        XCTAssertTrue(context.contains("We should focus on performance"))

        // Assert proper formatting
        XCTAssertTrue(context.contains("**User:**"))
        XCTAssertTrue(context.contains("**Research Expert:**"))
        XCTAssertTrue(context.contains("**Ideation Partner:**"))
    }

    func testEmptySiblingsProducesEmptyBlock() {
        let context = AgentPrompts.siblingContextBlock(from: [])
        XCTAssertTrue(context.isEmpty)
    }

    func testSingleSiblingContextBlock() {
        let msg1 = ChatMessage(
            role: .user,
            content: "What is the project architecture?"
        )
        let msg2 = ChatMessage(
            role: .assistant,
            content: "The architecture follows a modular pattern with clear separation of concerns."
        )

        let developerSnapshot = ConversationSnapshot(
            tabId: UUID(),
            role: .developer,
            messages: [msg1, msg2]
        )

        let context = AgentPrompts.siblingContextBlock(from: [developerSnapshot])

        // Assert header and role are present
        XCTAssertTrue(context.contains("## Context from other planning conversations"))
        XCTAssertTrue(context.contains("Senior Architect"))

        // Assert messages are formatted correctly
        XCTAssertTrue(context.contains("**User:**"))
        XCTAssertTrue(context.contains("**Senior Architect:**"))
        XCTAssertTrue(context.contains("What is the project architecture?"))
        XCTAssertTrue(context.contains("The architecture follows a modular pattern"))
    }

    func testContextBlockFormattingWithMultipleMessages() {
        // Create a conversation with more messages
        var messages: [ChatMessage] = []
        messages.append(ChatMessage(role: .user, content: "First question"))
        messages.append(ChatMessage(role: .assistant, content: "First answer"))
        messages.append(ChatMessage(role: .user, content: "Second question"))
        messages.append(ChatMessage(role: .assistant, content: "Second answer"))

        let snapshot = ConversationSnapshot(
            tabId: UUID(),
            role: .claude,
            messages: messages
        )

        let context = AgentPrompts.siblingContextBlock(from: [snapshot])

        // Verify all messages are included
        XCTAssertTrue(context.contains("First question"))
        XCTAssertTrue(context.contains("First answer"))
        XCTAssertTrue(context.contains("Second question"))
        XCTAssertTrue(context.contains("Second answer"))

        // Verify proper role attribution
        let userCount = context.components(separatedBy: "**User:**").count - 1
        let assistantCount = context.components(separatedBy: "**Claude:**").count - 1

        XCTAssertEqual(userCount, 2)
        XCTAssertEqual(assistantCount, 2)
    }
}
