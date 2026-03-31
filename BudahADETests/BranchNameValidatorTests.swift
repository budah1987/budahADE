// BudahADETests/BranchNameValidatorTests.swift
import XCTest
@testable import BudahADE

final class BranchNameValidatorTests: XCTestCase {

    func testSpacesConvertedToHyphens() {
        XCTAssertEqual(BranchNameValidator.sanitize("my new branch"), "my-new-branch")
    }

    func testInvalidCharsStripped() {
        XCTAssertEqual(BranchNameValidator.sanitize("feat~name"), "featname")
        XCTAssertEqual(BranchNameValidator.sanitize("test:branch"), "testbranch")
        XCTAssertEqual(BranchNameValidator.sanitize("test?branch"), "testbranch")
        XCTAssertEqual(BranchNameValidator.sanitize("test*branch"), "testbranch")
        XCTAssertEqual(BranchNameValidator.sanitize("test[branch"), "testbranch")
        XCTAssertEqual(BranchNameValidator.sanitize("test\\branch"), "testbranch")
    }

    func testDoubleDotsCollapsed() {
        XCTAssertEqual(BranchNameValidator.sanitize("feat..test"), "feat.test")
    }

    func testDoubleSlashesCollapsed() {
        XCTAssertEqual(BranchNameValidator.sanitize("feat//test"), "feat/test")
    }

    func testLeadingTrailingSlashTrimmed() {
        XCTAssertEqual(BranchNameValidator.sanitize("/feat/test/"), "feat/test")
    }

    func testLeadingTrailingDotTrimmed() {
        XCTAssertEqual(BranchNameValidator.sanitize(".feat.test."), "feat.test")
    }

    func testTrailingLockStripped() {
        XCTAssertEqual(BranchNameValidator.sanitize("my-branch.lock"), "my-branch")
    }

    func testControlCharsStripped() {
        XCTAssertEqual(BranchNameValidator.sanitize("feat\u{01}test"), "feattest")
    }

    func testPrefixDetection() {
        XCTAssertEqual(BranchNameValidator.detectPrefix("feat/my-feature"), "feat")
        XCTAssertEqual(BranchNameValidator.detectPrefix("fix/bug-123"), "fix")
        XCTAssertEqual(BranchNameValidator.detectPrefix("my-branch"), nil)
        XCTAssertEqual(BranchNameValidator.detectPrefix("unknown/thing"), nil)
    }

    func testPrefixSplit() {
        let (prefix, name) = BranchNameValidator.split("feat/my-feature")
        XCTAssertEqual(prefix, "feat")
        XCTAssertEqual(name, "my-feature")
    }

    func testPrefixSplitNoPrefix() {
        let (prefix, name) = BranchNameValidator.split("my-branch")
        XCTAssertNil(prefix)
        XCTAssertEqual(name, "my-branch")
    }

    func testCompose() {
        XCTAssertEqual(BranchNameValidator.compose(prefix: "feat", name: "my-feature"), "feat/my-feature")
        XCTAssertEqual(BranchNameValidator.compose(prefix: nil, name: "my-branch"), "my-branch")
    }

    func testAllPrefixTypes() {
        let types = BranchNameValidator.prefixTypes
        XCTAssertEqual(types.count, 7)
        XCTAssertTrue(types.contains(where: { $0.prefix == "feat" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "fix" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "ui" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "refactor" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "chore" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "docs" }))
        XCTAssertTrue(types.contains(where: { $0.prefix == "experiment" }))
    }
}
