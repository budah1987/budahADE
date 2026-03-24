import XCTest
@testable import BudahADE

final class SessionPersistenceTests: XCTestCase {
    func testTabSnapshotRoundTrip() throws {
        let snapshot = TabSnapshot(
            id: UUID(),
            title: "Builder",
            claudeSessionId: "sess_abc123",
            agentMode: "claude",
            isActive: true,
            scrollbackPath: "sessions/abc-scrollback.txt",
            tmuxSession: nil
        )
        let session = SessionSnapshot(tabs: [snapshot], selectedTabId: snapshot.id)

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.tabs.count, 1)
        XCTAssertEqual(decoded.tabs[0].title, "Builder")
        XCTAssertEqual(decoded.tabs[0].claudeSessionId, "sess_abc123")
        XCTAssertEqual(decoded.selectedTabId, snapshot.id)
    }

    func testSaveAndLoad() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let tab = TabSnapshot(id: UUID(), title: "Test", claudeSessionId: nil, agentMode: nil, isActive: false, scrollbackPath: nil, tmuxSession: nil)
        let session = SessionSnapshot(tabs: [tab], selectedTabId: tab.id)

        try SessionPersistence.save(session, to: dir)
        let loaded = SessionPersistence.load(from: dir)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs[0].title, "Test")
    }

    func testLoadMissingFileReturnsNil() {
        let result = SessionPersistence.load(from: "/nonexistent/path")
        XCTAssertNil(result)
    }

    func testScrollbackSaveAndLoad() throws {
        let dir = NSTemporaryDirectory() + "budahade-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let tabId = UUID()
        let text = "$ claude\nHello! I'm Claude.\n> Working on task..."

        let relativePath = try SessionPersistence.saveScrollback(text, tabId: tabId, to: dir)
        let loaded = SessionPersistence.loadScrollback(relativePath: relativePath, from: dir)

        XCTAssertEqual(loaded, text)
    }
}
