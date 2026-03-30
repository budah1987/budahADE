import XCTest
@testable import BudahADE

final class SpecVersionManagerTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        // Create a unique temp directory for each test
        let base = NSTemporaryDirectory()
        tempDir = (base as NSString).appendingPathComponent("SpecVersionManagerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    // MARK: - Tests

    func testApproveCreatesVersionedSpec() {
        let content = "# Spec\n- Task 1\n- Task 2"
        let version = SpecVersionManager.approve(content: content, in: tempDir)

        XCTAssertEqual(version, 1, "First approval should return version 1")

        // Check versioned file exists
        let versionedPath = (tempDir as NSString)
            .appendingPathComponent(".budahade/specs/spec-v1.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: versionedPath),
                      "spec-v1.md should exist")

        // Check active spec exists
        let activePath = (tempDir as NSString)
            .appendingPathComponent(".budahade/spec.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: activePath),
                      "spec.md should exist")

        // Check content matches
        let writtenContent = try? String(contentsOfFile: versionedPath, encoding: .utf8)
        XCTAssertEqual(writtenContent, content)

        let activeContent = try? String(contentsOfFile: activePath, encoding: .utf8)
        XCTAssertEqual(activeContent, content)
    }

    func testMultipleApprovalsIncrement() {
        let content1 = "# Spec v1\n- Task A"
        let content2 = "# Spec v2\n- Task B"

        let v1 = SpecVersionManager.approve(content: content1, in: tempDir)
        let v2 = SpecVersionManager.approve(content: content2, in: tempDir)

        XCTAssertEqual(v1, 1)
        XCTAssertEqual(v2, 2)

        let specsDir = (tempDir as NSString).appendingPathComponent(".budahade/specs")

        let v1Path = (specsDir as NSString).appendingPathComponent("spec-v1.md")
        let v2Path = (specsDir as NSString).appendingPathComponent("spec-v2.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: v1Path), "spec-v1.md should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: v2Path), "spec-v2.md should exist")

        // Active spec should reflect v2
        let activeContent = SpecVersionManager.activeSpec(in: tempDir)
        XCTAssertEqual(activeContent, content2, "Active spec should be v2 content")
    }

    func testListVersions() {
        let content1 = "# Spec v1\n- Task 1"
        let content2 = "# Spec v2\n- Task 2"

        SpecVersionManager.approve(content: content1, in: tempDir)
        SpecVersionManager.approve(content: content2, in: tempDir)

        let versions = SpecVersionManager.listVersions(in: tempDir)

        XCTAssertEqual(versions.count, 2, "Should have 2 versions")
        XCTAssertEqual(versions[0].version, 1)
        XCTAssertEqual(versions[1].version, 2)
        XCTAssertEqual(versions[0].content, content1)
        XCTAssertEqual(versions[1].content, content2)
    }

    func testActiveSpecReturnsNilWhenNoSpec() {
        let result = SpecVersionManager.activeSpec(in: tempDir)
        XCTAssertNil(result, "Should return nil when no spec exists")
    }

    func testListVersionsReturnsEmptyWhenNoSpecs() {
        let versions = SpecVersionManager.listVersions(in: tempDir)
        XCTAssertTrue(versions.isEmpty, "Should return empty array when no specs exist")
    }
}
