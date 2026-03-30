import XCTest
@testable import BudahADE

final class PlanConversationPersistenceTests: XCTestCase {
    var tempDir: String!

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: tempDir)
        super.tearDown()
    }

    func testSaveConversation() {
        let tabId = UUID()
        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Hello, world!",
            timestamp: Date()
        )
        let snapshot = ConversationSnapshot(
            tabId: tabId,
            role: .researcher,
            messages: [message]
        )

        PlanConversationPersistence.save(snapshot, to: tempDir)

        let filename = "\(tabId.uuidString).json"
        let path = (tempDir as NSString).appendingPathComponent(".budahade/conversations/\(filename)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "File should exist at \(path)")
    }

    func testLoadConversation() {
        let tabId = UUID()
        let message = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Test message",
            timestamp: Date()
        )
        let snapshot = ConversationSnapshot(
            tabId: tabId,
            role: .researcher,
            messages: [message]
        )

        PlanConversationPersistence.save(snapshot, to: tempDir)
        let loaded = PlanConversationPersistence.load(tabId: tabId, from: tempDir)

        XCTAssertNotNil(loaded, "Should load conversation")
        XCTAssertEqual(loaded?.tabId, tabId)
        XCTAssertEqual(loaded?.role, .researcher)
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages[0].content, "Test message")
    }

    func testLoadAllConversations() {
        let tabId1 = UUID()
        let tabId2 = UUID()

        let message1 = ChatMessage(
            id: UUID(),
            role: .user,
            content: "First conversation",
            timestamp: Date()
        )
        let snapshot1 = ConversationSnapshot(
            tabId: tabId1,
            role: .researcher,
            messages: [message1]
        )

        let message2 = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Second conversation",
            timestamp: Date()
        )
        let snapshot2 = ConversationSnapshot(
            tabId: tabId2,
            role: .developer,
            messages: [message2]
        )

        PlanConversationPersistence.save(snapshot1, to: tempDir)
        PlanConversationPersistence.save(snapshot2, to: tempDir)

        let all = PlanConversationPersistence.loadAll(from: tempDir)

        XCTAssertEqual(all.count, 2, "Should load all conversations")
        XCTAssertTrue(all.contains { $0.tabId == tabId1 })
        XCTAssertTrue(all.contains { $0.tabId == tabId2 })
    }

    func testLoadAllExcluding() {
        let tabId1 = UUID()
        let tabId2 = UUID()

        let message1 = ChatMessage(
            id: UUID(),
            role: .user,
            content: "First",
            timestamp: Date()
        )
        let snapshot1 = ConversationSnapshot(
            tabId: tabId1,
            role: .researcher,
            messages: [message1]
        )

        let message2 = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Second",
            timestamp: Date()
        )
        let snapshot2 = ConversationSnapshot(
            tabId: tabId2,
            role: .ideator,
            messages: [message2]
        )

        PlanConversationPersistence.save(snapshot1, to: tempDir)
        PlanConversationPersistence.save(snapshot2, to: tempDir)

        let excluded = PlanConversationPersistence.loadAllExcluding(tabId: tabId1, from: tempDir)

        XCTAssertEqual(excluded.count, 1, "Should load all except one")
        XCTAssertFalse(excluded.contains { $0.tabId == tabId1 })
        XCTAssertTrue(excluded.contains { $0.tabId == tabId2 })
    }
}
