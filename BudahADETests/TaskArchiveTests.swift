import XCTest
@testable import BudahADE

final class TaskArchiveTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskArchiveTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - testArchiveTask

    func testArchiveTask() {
        let archive = TaskArchive()

        let task = ArchivedTask(
            id: UUID(),
            name: "My Feature",
            branchName: "feat/my-feature",
            worktreePath: "/tmp/worktrees/feat-my-feature",
            completedAt: Date(),
            specVersionCount: 3,
            conversationCount: 5
        )

        archive.add(task)

        XCTAssertEqual(archive.tasks.count, 1)
        XCTAssertEqual(archive.tasks[0].name, "My Feature")
        XCTAssertEqual(archive.tasks[0].branchName, "feat/my-feature")
        XCTAssertEqual(archive.tasks[0].specVersionCount, 3)
        XCTAssertEqual(archive.tasks[0].conversationCount, 5)
    }

    func testAddInsertsMostRecentFirst() {
        let archive = TaskArchive()

        let first = ArchivedTask(
            id: UUID(),
            name: "First Task",
            branchName: "feat/first",
            worktreePath: "/tmp/first",
            completedAt: Date(timeIntervalSinceNow: -3600),
            specVersionCount: 1,
            conversationCount: 1
        )

        let second = ArchivedTask(
            id: UUID(),
            name: "Second Task",
            branchName: "feat/second",
            worktreePath: "/tmp/second",
            completedAt: Date(),
            specVersionCount: 2,
            conversationCount: 2
        )

        archive.add(first)
        archive.add(second)

        XCTAssertEqual(archive.tasks.count, 2)
        // Most recently added (second) is at index 0
        XCTAssertEqual(archive.tasks[0].name, "Second Task")
        XCTAssertEqual(archive.tasks[1].name, "First Task")
    }

    // MARK: - testArchivePersistence

    func testArchivePersistence() throws {
        let archive = TaskArchive()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let task = ArchivedTask(
            id: UUID(),
            name: "Persisted Task",
            branchName: "feat/persist",
            worktreePath: "/tmp/worktrees/feat-persist",
            completedAt: completedAt,
            specVersionCount: 2,
            conversationCount: 4
        )

        archive.add(task)

        let projectPath = tempDir.path
        TaskArchive.save(archive, to: projectPath)

        guard let loaded = TaskArchive.load(from: projectPath) else {
            XCTFail("Failed to load archive from disk")
            return
        }

        XCTAssertEqual(loaded.tasks.count, 1)

        let loadedTask = loaded.tasks[0]
        XCTAssertEqual(loadedTask.name, "Persisted Task")
        XCTAssertEqual(loadedTask.branchName, "feat/persist")
        XCTAssertEqual(loadedTask.worktreePath, "/tmp/worktrees/feat-persist")
        XCTAssertEqual(loadedTask.specVersionCount, 2)
        XCTAssertEqual(loadedTask.conversationCount, 4)
        // Date precision: iso8601 round-trips to second precision
        XCTAssertEqual(loadedTask.completedAt.timeIntervalSince1970,
                       completedAt.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func testLoadReturnsNilWhenFileAbsent() {
        let result = TaskArchive.load(from: tempDir.path)
        XCTAssertNil(result)
    }

    func testSaveCreatesDirectory() {
        let deepPath = tempDir.appendingPathComponent("deep/nested").path
        let archive = TaskArchive()
        archive.add(ArchivedTask(
            id: UUID(),
            name: "Test",
            branchName: "main",
            worktreePath: "/tmp",
            completedAt: Date(),
            specVersionCount: 0,
            conversationCount: 0
        ))

        TaskArchive.save(archive, to: deepPath)

        let expectedFile = (deepPath as NSString)
            .appendingPathComponent(".budahade/task-archive.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile))
    }
}
