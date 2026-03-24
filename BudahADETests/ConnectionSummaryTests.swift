import XCTest
@testable import BudahADE

final class ConnectionSummaryTests: XCTestCase {

    @MainActor
    func testSummaryManagerCacheHit() {
        let manager = ConnectionSummaryManager()
        var conn = TileConnection(sourceId: UUID(), destinationId: UUID(), cachedSummary: "cached", sourceVersion: 1)
        let result = manager.resolvedSummary(for: &conn, output: .text("content"))
        XCTAssertEqual(result, "cached")
    }

    @MainActor
    func testSummaryManagerCacheMiss() {
        let manager = ConnectionSummaryManager()
        var conn = TileConnection(sourceId: UUID(), destinationId: UUID(), sourceVersion: 1)
        let result = manager.resolvedSummary(for: &conn, output: .text("content"))
        XCTAssertNil(result) // nil = generating
    }

    @MainActor
    func testSummaryConcurrencyLimit() {
        XCTAssertEqual(ConnectionSummaryManager.maxConcurrentSummaries, 3)
    }
}
