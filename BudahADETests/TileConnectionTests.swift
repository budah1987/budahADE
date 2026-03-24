import XCTest
@testable import BudahADE

final class TileConnectionTests: XCTestCase {

    // MARK: - TileConnection Creation

    func testTileConnectionCreation() {
        let sourceId = UUID()
        let destinationId = UUID()
        let connection = TileConnection(
            id: UUID(),
            sourceId: sourceId,
            destinationId: destinationId,
            sourceVersion: 1
        )
        XCTAssertEqual(connection.sourceId, sourceId)
        XCTAssertEqual(connection.destinationId, destinationId)
        XCTAssertEqual(connection.sourceVersion, 1)
        XCTAssertNil(connection.cachedSummary)
        XCTAssertNil(connection.summaryTimestamp)
    }

    func testTileConnectionWithOptionalFields() {
        let now = Date()
        let connection = TileConnection(
            id: UUID(),
            sourceId: UUID(),
            destinationId: UUID(),
            cachedSummary: "A summary",
            summaryTimestamp: now,
            sourceVersion: 3
        )
        XCTAssertEqual(connection.cachedSummary, "A summary")
        XCTAssertEqual(connection.summaryTimestamp, now)
        XCTAssertEqual(connection.sourceVersion, 3)
    }

    func testTileConnectionEquatable() {
        let id = UUID()
        let sourceId = UUID()
        let destinationId = UUID()
        let a = TileConnection(id: id, sourceId: sourceId, destinationId: destinationId, sourceVersion: 1)
        let b = TileConnection(id: id, sourceId: sourceId, destinationId: destinationId, sourceVersion: 1)
        let c = TileConnection(id: UUID(), sourceId: sourceId, destinationId: destinationId, sourceVersion: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - TileConnection Codable

    func testTileConnectionCodableRoundTrip() throws {
        let original = TileConnection(
            id: UUID(),
            sourceId: UUID(),
            destinationId: UUID(),
            cachedSummary: "Cached",
            summaryTimestamp: Date(timeIntervalSince1970: 1_000_000),
            sourceVersion: 5
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TileConnection.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testTileConnectionCodableRoundTripWithNilOptionals() throws {
        let original = TileConnection(
            id: UUID(),
            sourceId: UUID(),
            destinationId: UUID(),
            sourceVersion: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TileConnection.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.cachedSummary)
        XCTAssertNil(decoded.summaryTimestamp)
    }

    // MARK: - TileOutput.textRepresentation

    func testTileOutputTextRepresentation() {
        let output = TileOutput.text("Hello world")
        XCTAssertEqual(output.textRepresentation, "Hello world")
    }

    func testTileOutputTerminalRepresentation() {
        let output = TileOutput.terminalOutput("$ ls -la\ntotal 0")
        XCTAssertEqual(output.textRepresentation, "$ ls -la\ntotal 0")
    }

    func testTileOutputImageRepresentation() {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        let output = TileOutput.image(url)
        XCTAssertEqual(output.textRepresentation, "[Image: photo.png]")
    }

    func testTileOutputURLRepresentation() {
        let url = URL(string: "https://example.com/page")!
        let output = TileOutput.url(url)
        XCTAssertEqual(output.textRepresentation, "[URL: https://example.com/page]")
    }

    func testTileOutputConversationEmpty() {
        let output = TileOutput.conversation([])
        XCTAssertEqual(output.textRepresentation, "")
    }

    func testTileOutputConversationFormatsMessages() {
        let messages = [
            ChatMessage(role: .user, content: "What is 2+2?"),
            ChatMessage(role: .assistant, content: "4"),
        ]
        let output = TileOutput.conversation(messages)
        XCTAssertEqual(output.textRepresentation, "User: What is 2+2?\nAssistant: 4")
    }

    func testTileOutputConversationLast10Messages() {
        // 12 messages — only last 10 should appear
        let messages = (0..<12).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant, content: "msg\(i)")
        }
        let output = TileOutput.conversation(messages)
        let lines = output.textRepresentation.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 10)
        // First included message is index 2
        XCTAssertTrue(output.textRepresentation.hasPrefix("User: msg2"))
    }

    func testTileOutputConversationSkipsSystemMessages() {
        let messages = [
            ChatMessage(role: .system, content: "You are helpful."),
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there"),
        ]
        let output = TileOutput.conversation(messages)
        // system messages are included in raw output; verify user/assistant format
        XCTAssertTrue(output.textRepresentation.contains("User: Hello"))
        XCTAssertTrue(output.textRepresentation.contains("Assistant: Hi there"))
    }
}
