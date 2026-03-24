import XCTest
@testable import BudahADE

final class CanvasPersistenceTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - AgentModel

    func testAgentModelRoundTrip() throws {
        for model in AgentModel.allCases {
            let decoded = try roundTrip(model)
            XCTAssertEqual(decoded, model)
        }
    }

    // MARK: - AgentMode

    func testAgentModeRoundTrip() throws {
        for mode in AgentMode.allCases {
            let decoded = try roundTrip(mode)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - TextData / TextWeight / TextFontFamily

    func testTextDataRoundTrip() throws {
        let original = TextData(
            content: "Hello canvas",
            fontSize: 24,
            weight: .semibold,
            fontFamily: .monospace,
            colorHex: 0xff5500,
            isBold: true,
            isItalic: false
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.content, "Hello canvas")
        XCTAssertEqual(decoded.fontSize, 24)
        XCTAssertEqual(decoded.weight, .semibold)
        XCTAssertEqual(decoded.fontFamily, .monospace)
        XCTAssertEqual(decoded.colorHex, 0xff5500)
        XCTAssertTrue(decoded.isBold)
        XCTAssertFalse(decoded.isItalic)
    }

    func testTextWeightAllCases() throws {
        for weight in TextWeight.allCases {
            let decoded = try roundTrip(weight)
            XCTAssertEqual(decoded, weight)
        }
    }

    func testTextFontFamilyAllCases() throws {
        for family in TextFontFamily.allCases {
            let decoded = try roundTrip(family)
            XCTAssertEqual(decoded, family)
        }
    }

    // MARK: - TileType cases

    func testStickyNoteTileRoundTrip() throws {
        let tile = TileType.stickyNote
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
    }

    func testMarkdownTileRoundTrip() throws {
        let tile = TileType.markdown(path: "/tmp/spec.md")
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
        if case .markdown(let path) = decoded {
            XCTAssertEqual(path, "/tmp/spec.md")
        } else {
            XCTFail("Expected .markdown case")
        }
    }

    func testImageTileRoundTrip() throws {
        let tile = TileType.image(path: "/tmp/diagram.png")
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
    }

    func testBrowserTileWithURLRoundTrip() throws {
        let url = URL(string: "https://example.com")!
        let tile = TileType.browser(url: url)
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
        if case .browser(let decodedURL) = decoded {
            XCTAssertEqual(decodedURL, url)
        } else {
            XCTFail("Expected .browser case")
        }
    }

    func testBrowserTileNilURLRoundTrip() throws {
        let tile = TileType.browser(url: nil)
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
    }

    func testTerminalTileRoundTrip() throws {
        let panelId = UUID()
        let tile = TileType.terminal(panelId: panelId, agent: .developer)
        let decoded = try roundTrip(tile)
        XCTAssertEqual(decoded, tile)
        if case .terminal(let pid, let agent) = decoded {
            XCTAssertEqual(pid, panelId)
            XCTAssertEqual(agent, .developer)
        } else {
            XCTFail("Expected .terminal case")
        }
    }

    func testChatAgentTileRoundTrip() throws {
        let sessionId = UUID()
        let role = AgentRole(
            id: "developer",
            name: "Developer",
            systemPrompt: "You are a developer agent.",
            defaultModel: .sonnet,
            color: .blue
        )
        let tile = TileType.chatAgent(sessionId: sessionId, role: role)
        let data = try JSONEncoder().encode(tile)
        let decoded = try JSONDecoder().decode(TileType.self, from: data)
        // Color round-trip is lossy (stored as hex), so compare fields individually
        if case .chatAgent(let sid, let decodedRole) = decoded {
            XCTAssertEqual(sid, sessionId)
            XCTAssertEqual(decodedRole.id, "developer")
            XCTAssertEqual(decodedRole.name, "Developer")
            XCTAssertEqual(decodedRole.systemPrompt, "You are a developer agent.")
            XCTAssertEqual(decodedRole.defaultModel, .sonnet)
        } else {
            XCTFail("Expected .chatAgent case")
        }
    }

    // MARK: - AgentRole

    func testAgentRoleRoundTrip() throws {
        let role = AgentRole(
            id: "ideator",
            name: "Ideator",
            systemPrompt: "Think creatively.",
            defaultModel: .opus,
            color: .orange
        )
        let decoded = try roundTrip(role)
        XCTAssertEqual(decoded.id, role.id)
        XCTAssertEqual(decoded.name, role.name)
        XCTAssertEqual(decoded.systemPrompt, role.systemPrompt)
        XCTAssertEqual(decoded.defaultModel, role.defaultModel)
        // Color round-trip is lossy (hex), so just verify it decodes without throwing
    }

    // MARK: - FrameData

    func testEmptyFrameDataRoundTrip() throws {
        let frame = FrameData()
        let decoded = try roundTrip(frame)
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(decoded.gap, 32)
        XCTAssertEqual(decoded.padding, 48)
        XCTAssertEqual(decoded.headerHeight, 40)
        XCTAssertTrue(decoded.children.isEmpty)
    }

    func testVerticalFrameDataRoundTrip() throws {
        let frame = FrameData(axis: .vertical, gap: 16, padding: 24, headerHeight: 50)
        let decoded = try roundTrip(frame)
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(decoded.gap, 16)
        XCTAssertEqual(decoded.padding, 24)
    }

    func testFrameWithChildrenRoundTrip() throws {
        var frame = FrameData(axis: .horizontal)
        frame.children = [
            CanvasElement(
                kind: .tile(.stickyNote),
                position: CGPoint(x: 10, y: 20),
                size: CGSize(width: 300, height: 200),
                title: "Child 1"
            ),
            CanvasElement(
                kind: .tile(.markdown(path: "/tmp/doc.md")),
                position: CGPoint(x: 50, y: 60),
                size: CGSize(width: 400, height: 300),
                title: "Child 2"
            )
        ]
        let decoded = try roundTrip(frame)
        XCTAssertEqual(decoded.children.count, 2)
        XCTAssertEqual(decoded.children[0].title, "Child 1")
        XCTAssertEqual(decoded.children[1].title, "Child 2")
        XCTAssertEqual(decoded.children[0].position, CGPoint(x: 10, y: 20))
    }

    // MARK: - CanvasElement

    func testTextElementRoundTrip() throws {
        let textData = TextData(
            content: "Hello World",
            fontSize: 18,
            weight: .bold,
            fontFamily: .serif,
            colorHex: 0xaabbcc,
            isBold: false,
            isItalic: true
        )
        let element = CanvasElement(
            kind: .text(textData),
            position: CGPoint(x: 100, y: 200),
            size: CGSize(width: 480, height: 60),
            title: "My Text",
            specSection: "Architecture",
            specOrder: 3
        )
        let decoded = try roundTrip(element)
        XCTAssertEqual(decoded.id, element.id)
        XCTAssertEqual(decoded.title, "My Text")
        XCTAssertEqual(decoded.position, CGPoint(x: 100, y: 200))
        XCTAssertEqual(decoded.size, CGSize(width: 480, height: 60))
        XCTAssertEqual(decoded.specSection, "Architecture")
        XCTAssertEqual(decoded.specOrder, 3)
        if case .text(let td) = decoded.kind {
            XCTAssertEqual(td, textData)
        } else {
            XCTFail("Expected .text kind")
        }
    }

    func testCanvasElementWithFrameKindRoundTrip() throws {
        let frame = FrameData(axis: .vertical, gap: 20, padding: 30, headerHeight: 44)
        let element = CanvasElement(
            kind: .frame(frame),
            position: CGPoint(x: 0, y: 0),
            size: CGSize(width: 800, height: 600),
            title: "Main Frame"
        )
        let decoded = try roundTrip(element)
        XCTAssertEqual(decoded.title, "Main Frame")
        if case .frame(let fd) = decoded.kind {
            XCTAssertEqual(fd.gap, 20)
            XCTAssertEqual(fd.padding, 30)
        } else {
            XCTFail("Expected .frame kind")
        }
    }

    func testCanvasElementSpecSectionNilRoundTrip() throws {
        let element = CanvasElement(
            kind: .tile(.stickyNote),
            title: "No section"
        )
        let decoded = try roundTrip(element)
        XCTAssertNil(decoded.specSection)
    }

    // MARK: - CanvasPersistence

    func testSaveAndLoadSnapshot() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let elements = [
            CanvasElement(kind: .tile(.stickyNote), position: CGPoint(x: 10, y: 20), title: "Note"),
            CanvasElement(kind: .tile(.markdown(path: "/tmp/spec.md")), position: CGPoint(x: 300, y: 0), title: "Spec"),
        ]
        let snapshot = CanvasSnapshot(
            elements: elements, zoom: 0.75,
            panOffsetWidth: 100, panOffsetHeight: -50,
            chatMessages: [:]
        )
        try CanvasPersistence.save(snapshot, to: dir)

        let path = (dir as NSString).appendingPathComponent(".budahade/canvas.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        let loaded = try XCTUnwrap(CanvasPersistence.load(from: dir))
        XCTAssertEqual(loaded.elements.count, 2)
        XCTAssertEqual(loaded.zoom, 0.75)
        XCTAssertEqual(loaded.panOffsetWidth, 100)
        XCTAssertEqual(loaded.panOffsetHeight, -50)
    }

    func testLoadMissingFileReturnsNil() {
        let dir = NSTemporaryDirectory() + "budahade-nonexistent-\(UUID().uuidString)"
        XCTAssertNil(CanvasPersistence.load(from: dir))
    }

    func testLoadCorruptedFileReturnsNil() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        let budahDir = (dir as NSString).appendingPathComponent(".budahade")
        try FileManager.default.createDirectory(atPath: budahDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = (budahDir as NSString).appendingPathComponent("canvas.json")
        try "{ broken json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertNil(CanvasPersistence.load(from: dir))
    }

    func testChatMessagesPersistedWithSnapshot() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let sessionId = UUID()
        let messages = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there", inputTokens: 10, outputTokens: 5),
        ]
        let snapshot = CanvasSnapshot(
            elements: [], zoom: 1.0, panOffsetWidth: 0, panOffsetHeight: 0,
            chatMessages: [sessionId: messages]
        )
        try CanvasPersistence.save(snapshot, to: dir)
        let loaded = try XCTUnwrap(CanvasPersistence.load(from: dir))
        XCTAssertEqual(loaded.chatMessages[sessionId]?.count, 2)
        XCTAssertEqual(loaded.chatMessages[sessionId]?[1].content, "Hi there")
    }
}
