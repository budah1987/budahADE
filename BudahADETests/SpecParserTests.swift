// BudahADETests/SpecParserTests.swift
import XCTest
@testable import BudahADE

final class SpecParserTests: XCTestCase {
    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "specparser-tests-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    private func writeFile(_ name: String, content: String) -> String {
        let path = (tmpDir as NSString).appendingPathComponent(name)
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testParseTitle() {
        let path = writeFile("test-spec.md", content: "# My Spec\n\n## Tasks\n- [ ] Do thing")
        let result = SpecParser.parse(fileAt: path)
        XCTAssertEqual(result?.title, "My Spec")
    }

    func testParseSections() {
        let path = writeFile("test-spec.md", content: """
        # Spec
        ## Architecture
        Some text.
        ## Tasks
        - [ ] Item 1
        - [x] Item 2
        """)
        let result = SpecParser.parse(fileAt: path)!
        XCTAssertEqual(result.sections.count, 2)
        XCTAssertEqual(result.sections[0].title, "Architecture")
        XCTAssertEqual(result.sections[1].title, "Tasks")
        XCTAssertEqual(result.sections[1].tasks.count, 2)
    }

    func testProgressCalculation() {
        let path = writeFile("test-spec.md", content: """
        # S
        ## T
        - [x] Done
        - [ ] Not done
        - [x] Also done
        """)
        let result = SpecParser.parse(fileAt: path)!
        XCTAssertEqual(result.completedCount, 2)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.progress, 2.0 / 3.0, accuracy: 0.001)
    }

    func testFindSpecFiles() {
        _ = writeFile("feature-spec.md", content: "# F")
        _ = writeFile("plan-plan.md", content: "# P")
        _ = writeFile("readme.md", content: "# R")
        let found = SpecParser.findSpecFiles(in: tmpDir)
        XCTAssertEqual(found.count, 2)
    }

    func testParseReturnsNilForEmptyFile() {
        let path = writeFile("empty-spec.md", content: "Just text, no sections or tasks.")
        let result = SpecParser.parse(fileAt: path)
        XCTAssertNil(result)
    }

    func testParseMissingFile() {
        let result = SpecParser.parse(fileAt: "/nonexistent/path.md")
        XCTAssertNil(result)
    }
}
