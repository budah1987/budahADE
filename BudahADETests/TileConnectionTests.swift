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

    // MARK: - Connection CRUD

    func testAddConnection() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let idA = await state.addTile(type: .stickyNote, at: .zero)
        let idB = await state.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
        let connId = await state.addConnection(sourceId: idA, destinationId: idB)
        let conns = await state.connections
        XCTAssertEqual(conns.count, 1)
        XCTAssertEqual(conns.first?.id, connId)
        XCTAssertEqual(conns.first?.sourceId, idA)
        XCTAssertEqual(conns.first?.destinationId, idB)
    }

    func testRemoveConnection() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let idA = await state.addTile(type: .stickyNote, at: .zero)
        let idB = await state.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
        let connId = await state.addConnection(sourceId: idA, destinationId: idB)
        await state.removeConnection(connId)
        let conns = await state.connections
        XCTAssertEqual(conns.count, 0)
    }

    func testNoDuplicateConnections() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let idA = await state.addTile(type: .stickyNote, at: .zero)
        let idB = await state.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
        let firstId = await state.addConnection(sourceId: idA, destinationId: idB)
        let secondId = await state.addConnection(sourceId: idA, destinationId: idB)
        let conns = await state.connections
        XCTAssertEqual(conns.count, 1, "Duplicate connection should not be added")
        XCTAssertEqual(firstId, secondId, "Should return existing connection ID")
    }

    func testConnectionsCleanedUpOnElementRemoval() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let idA = await state.addTile(type: .stickyNote, at: .zero)
        let idB = await state.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
        await state.addConnection(sourceId: idA, destinationId: idB)
        await state.removeElement(idA)
        let conns = await state.connections
        XCTAssertEqual(conns.count, 0, "Connection should be removed when source element is deleted")
    }

    func testIncomingConnections() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let idA = await state.addTile(type: .stickyNote, at: .zero)
        let idB = await state.addTile(type: .stickyNote, at: CGPoint(x: 300, y: 0))
        let idC = await state.addTile(type: .stickyNote, at: CGPoint(x: 600, y: 0))
        await state.addConnection(sourceId: idA, destinationId: idC)
        await state.addConnection(sourceId: idB, destinationId: idC)
        await state.addConnection(sourceId: idA, destinationId: idB)

        let incoming = await state.incomingConnections(for: idC)
        XCTAssertEqual(incoming.count, 2)
        XCTAssertTrue(incoming.allSatisfy { $0.destinationId == idC })

        let outgoing = await state.outgoingConnections(for: idA)
        XCTAssertEqual(outgoing.count, 2)
        XCTAssertTrue(outgoing.allSatisfy { $0.sourceId == idA })
    }

    // MARK: - tileOutput(for:)

    func testTileOutputForStickyNoteEmptyTitle() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let id = await state.addTile(type: .stickyNote, at: .zero)
        // Rename to empty to trigger the nil path
        await state.renameElement(id, to: "")
        let output = await state.tileOutput(for: id)
        XCTAssertNil(output, "Empty title should return nil")
    }

    func testTileOutputForMarkdown() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("testTileOutput_\(UUID()).md").path
        try "# Hello\n\nWorld".write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let id = await state.addTile(type: .markdown(path: tmp), at: .zero)
        let output = await state.tileOutput(for: id)
        guard case .text(let content) = output else {
            XCTFail("Expected .text output"); return
        }
        XCTAssertTrue(content.contains("Hello"))
    }

    func testTileOutputForChatAgent() async throws {
        let state = await PlanCanvasState(worktreePath: "/tmp", taskName: "test", branchName: "test")
        let id = await state.addChatTile(agent: .claude, at: .zero)

        // Retrieve the session and inject messages
        guard let element = await state.findElement(id),
              case .tile(.chatAgent(let sessionId, _)) = element.kind,
              let session = await state.chatSessions[sessionId] else {
            XCTFail("Could not find chat session"); return
        }
        await MainActor.run {
            session.messages = [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(role: .assistant, content: "Hi")
            ]
        }

        let output = await state.tileOutput(for: id)
        guard case .conversation(let messages) = output else {
            XCTFail("Expected .conversation output"); return
        }
        XCTAssertEqual(messages.count, 2)
    }

    // MARK: - assembleConnectedContext

    @MainActor
    func testAssembleConnectedContext() throws {
        let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
        let tmpFile = NSTemporaryDirectory() + "ctx-test-\(UUID()).md"
        try "# Design Notes\nUse OAuth2 for auth.".write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let noteId = canvas.addTile(type: .markdown(path: tmpFile), at: .zero)
        let chatId = canvas.addChatTile(agent: .ideator, at: CGPoint(x: 500, y: 0))

        let connId = canvas.addConnection(sourceId: noteId, destinationId: chatId)
        // Manually set cached summary
        if let idx = canvas.connections.firstIndex(where: { $0.id == connId }) {
            canvas.connections[idx].cachedSummary = "Design notes about OAuth2 auth approach"
        }

        let context = canvas.assembleConnectedContext(for: chatId)
        XCTAssertNotNil(context)
        XCTAssertTrue(context!.contains("OAuth2"))
        XCTAssertTrue(context!.contains("Context from connected tiles"))
    }

    @MainActor
    func testAssembleConnectedContextNoConnections() {
        let canvas = PlanCanvasState(worktreePath: "/tmp/test", taskName: "test", branchName: "test")
        let tileId = canvas.addTile(type: .stickyNote, at: .zero)
        XCTAssertNil(canvas.assembleConnectedContext(for: tileId))
    }
}
