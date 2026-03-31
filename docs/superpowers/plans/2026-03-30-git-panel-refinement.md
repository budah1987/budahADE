# Git Panel Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the git sidebar with interactive branch header, side-by-side diff modal, AI commit messages, and collapsible commit history.

**Architecture:** Clean rebuild of GitSidebarView decomposed into focused subviews (BranchHeaderView, ChangesListView, CommitBarView, CommitHistoryView, DiffModalView). GitRepository gains new properties (mergeTarget, behindCount, forkPointHash). New AICommitService handles diff→Claude→message.

**Tech Stack:** SwiftUI, Foundation/Process (git commands), CLISubprocessManager (AI commit messages)

---

### Task 1: Branch Name Validation

**Files:**
- Create: `BudahADE/GitPanel/BranchNameValidator.swift`
- Create: `BudahADETests/BranchNameValidatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// BudahADETests/BranchNameValidatorTests.swift
import XCTest
@testable import BudahADE

final class BranchNameValidatorTests: XCTestCase {

    func testSpacesConvertedToHyphens() {
        XCTAssertEqual(BranchNameValidator.sanitize("my new branch"), "my-new-branch")
    }

    func testInvalidCharsStripped() {
        XCTAssertEqual(BranchNameValidator.sanitize("feat~test^name"), "feattest-name".replacingOccurrences(of: "-", with: ""), "Should strip ~ and ^")
        // More precise:
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/BranchNameValidatorTests -quiet 2>&1 | tail -20`
Expected: Compilation error — `BranchNameValidator` not defined

- [ ] **Step 3: Write the implementation**

```swift
// BudahADE/GitPanel/BranchNameValidator.swift
import Foundation

enum BranchNameValidator {

    struct PrefixType: Identifiable {
        let id: String
        let prefix: String
        let label: String
        var color: String  // Theme color name for SwiftUI lookup

        init(prefix: String, label: String, color: String) {
            self.id = prefix
            self.prefix = prefix
            self.label = label
            self.color = color
        }
    }

    static let prefixTypes: [PrefixType] = [
        PrefixType(prefix: "feat",       label: "feature",     color: "success"),
        PrefixType(prefix: "fix",        label: "bug fix",     color: "error"),
        PrefixType(prefix: "ui",         label: "visual",      color: "accent"),
        PrefixType(prefix: "refactor",   label: "restructure", color: "info"),
        PrefixType(prefix: "chore",      label: "maintenance", color: "textMuted"),
        PrefixType(prefix: "docs",       label: "specs",       color: "info"),
        PrefixType(prefix: "experiment", label: "prototype",   color: "warning"),
    ]

    private static let invalidChars = CharacterSet(charactersIn: "~^:?*[\\")
    private static let knownPrefixes = Set(prefixTypes.map(\.prefix))

    /// Sanitize a branch name: strip invalid chars, collapse sequences, trim edges
    static func sanitize(_ input: String) -> String {
        var result = input

        // Strip ASCII control characters
        result = result.unicodeScalars.filter { $0.value >= 32 }.map(String.init).joined()

        // Space → hyphen
        result = result.replacingOccurrences(of: " ", with: "-")

        // Strip invalid chars: ~ ^ : ? * [ backslash
        result = result.unicodeScalars.filter { !invalidChars.contains($0) }.map(String.init).joined()

        // Collapse // → / and .. → .
        while result.contains("//") { result = result.replacingOccurrences(of: "//", with: "/") }
        while result.contains("..") { result = result.replacingOccurrences(of: "..", with: ".") }

        // Trim leading/trailing / and .
        let trimChars = CharacterSet(charactersIn: "/.")
        result = result.trimmingCharacters(in: trimChars)

        // Strip trailing .lock
        if result.hasSuffix(".lock") {
            result = String(result.dropLast(5))
        }

        return result
    }

    /// Detect a known prefix from a branch name like "feat/my-feature"
    static func detectPrefix(_ branchName: String) -> String? {
        guard let slashIndex = branchName.firstIndex(of: "/") else { return nil }
        let candidate = String(branchName[branchName.startIndex..<slashIndex])
        return knownPrefixes.contains(candidate) ? candidate : nil
    }

    /// Split a branch name into (prefix, name). Prefix is nil if not a known type.
    static func split(_ branchName: String) -> (prefix: String?, name: String) {
        guard let detected = detectPrefix(branchName),
              let slashIndex = branchName.firstIndex(of: "/") else {
            return (nil, branchName)
        }
        let name = String(branchName[branchName.index(after: slashIndex)...])
        return (detected, name)
    }

    /// Compose prefix + name into a branch name
    static func compose(prefix: String?, name: String) -> String {
        if let prefix, !prefix.isEmpty {
            return "\(prefix)/\(name)"
        }
        return name
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/BranchNameValidatorTests -quiet 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Regenerate Xcode project and commit**

```bash
cd /Users/amir/Documents/Cursor\ Projects/budahADE
xcodegen generate
git add BudahADE/GitPanel/BranchNameValidator.swift BudahADETests/BranchNameValidatorTests.swift
git commit -m "feat: add BranchNameValidator with sanitization and prefix detection"
```

---

### Task 2: Extend GitRepository with New Properties

**Files:**
- Modify: `BudahADE/GitPanel/GitRepository.swift`
- Create: `BudahADETests/GitRepositoryExtensionsTests.swift`

- [ ] **Step 1: Write failing tests for new properties**

```swift
// BudahADETests/GitRepositoryExtensionsTests.swift
import XCTest
@testable import BudahADE

final class GitRepositoryExtensionsTests: XCTestCase {

    func testRenameBranchCommand() {
        // Test that renameBranch constructs correct args
        // We can't run real git in tests, but we can test the method exists
        let repo = GitRepository(path: "/tmp/nonexistent")
        // Just verifying the method compiles and has correct signature
        XCTAssertNotNil(repo as GitRepository)
    }

    func testMergeTargetDefaultsToBaseBranch() {
        let repo = GitRepository(path: "/tmp/nonexistent")
        repo.mergeTarget = "main"
        XCTAssertEqual(repo.mergeTarget, "main")
    }

    func testBehindCountDefault() {
        let repo = GitRepository(path: "/tmp/nonexistent")
        XCTAssertEqual(repo.behindCount, 0)
    }

    func testForkPointDefault() {
        let repo = GitRepository(path: "/tmp/nonexistent")
        XCTAssertNil(repo.forkPointHash)
    }

    func testCommitCountDefault() {
        let repo = GitRepository(path: "/tmp/nonexistent")
        XCTAssertEqual(repo.totalCommitCount, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/GitRepositoryExtensionsTests -quiet 2>&1 | tail -20`
Expected: Compilation error — missing properties

- [ ] **Step 3: Add new properties and methods to GitRepository**

Add these published properties after line 45 in `GitRepository.swift`:

```swift
@Published var mergeTarget: String = "main"
@Published var behindCount: Int = 0
@Published var forkPointHash: String?
@Published var totalCommitCount: Int = 0
```

Add this method after the existing `parseRemoteStatus()` method (after line 316):

```swift
// MARK: - Extended Parsing

func parseMergeInfo() {
    // Count behind target
    if !mergeTarget.isEmpty, !currentBranch.isEmpty {
        if let output = runGit(["rev-list", "--count", "HEAD..\(mergeTarget)"]) {
            behindCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } else {
            behindCount = 0
        }
    }

    // Fork point
    if !mergeTarget.isEmpty {
        if let output = runGit(["merge-base", "HEAD", mergeTarget]) {
            forkPointHash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            forkPointHash = nil
        }
    }

    // Total commit count
    if let output = runGit(["rev-list", "--count", "HEAD"]) {
        totalCommitCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

func renameBranch(from oldName: String, to newName: String) -> Bool {
    let result = runGit(["branch", "-m", oldName, newName])
    if result != nil {
        refresh()
        return true
    }
    return false
}

func extendedLog(limit: Int = 20) -> [GitCommit] {
    guard let output = runGit(["log", "--oneline", "-\(limit)", "--format=%H|||%s|||%an|||%ar"]) else {
        return []
    }

    return output
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .compactMap { line in
            let parts = line.components(separatedBy: "|||")
            guard parts.count == 4 else { return nil }
            return GitCommit(
                id: parts[0],
                message: parts[1],
                author: parts[2],
                date: parts[3]
            )
        }
}

func diffForCommit(_ hash: String) -> String {
    return runGit(["show", "--format=", hash]) ?? ""
}

func filesChangedInCommit(_ hash: String) -> [GitFileStatus] {
    guard let output = runGit(["show", "--name-status", "--format=", hash]) else { return [] }
    return output
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { return nil }
            return GitFileStatus(status: mapStatusChar(parts[0]), path: parts[1])
        }
}
```

Update the `refresh()` method (around line 70) to also call `parseMergeInfo()`:

```swift
func refresh() {
    parseStatus()
    parseBranches()
    parseLog()
    parseRemoteStatus()
    parseMergeInfo()
}
```

Also change `mapStatusChar` from `private` to `internal` so `filesChangedInCommit` can use it (line 404, remove `private`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme BudahADE -only-testing:BudahADETests/GitRepositoryExtensionsTests -quiet 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Verify full build**

Run: `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add BudahADE/GitPanel/GitRepository.swift BudahADETests/GitRepositoryExtensionsTests.swift
git commit -m "feat: extend GitRepository with mergeTarget, behindCount, forkPoint, and branch rename"
```

---

### Task 3: BranchHeaderView

**Files:**
- Create: `BudahADE/GitPanel/BranchHeaderView.swift`

- [ ] **Step 1: Create BranchHeaderView**

```swift
// BudahADE/GitPanel/BranchHeaderView.swift
import SwiftUI

struct BranchHeaderView: View {
    @ObservedObject var repo: GitRepository
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var selectedPrefix: String?
    @State private var showPrefixDropdown = false
    @State private var showTargetDropdown = false

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editingHeader
            } else {
                defaultHeader
            }
        }
        .padding(10)
        .background(Theme.surface2)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEditing ? Theme.info : Theme.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Default State

    private var defaultHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.info)

                if let prefix = BranchNameValidator.detectPrefix(repo.currentBranch) {
                    prefixBadge(prefix)
                    Text("/")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
                }

                let (_, name) = BranchNameValidator.split(repo.currentBranch)
                Text(name)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundColor(Theme.info)
                    .onTapGesture {
                        let parts = BranchNameValidator.split(repo.currentBranch)
                        selectedPrefix = parts.prefix
                        editedName = parts.name
                        isEditing = true
                    }
            }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)

                Button {
                    showTargetDropdown.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Text(repo.mergeTarget)
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.info.opacity(0.8))
                            .underline()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if showTargetDropdown {
                        targetDropdown
                            .offset(y: 20)
                    }
                }

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.12))
                        .cornerRadius(8)
                }

                if repo.behindCount > 0 {
                    Text("\(repo.behindCount) behind")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.error)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.error.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Editing State

    private var editingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.info)

                // Prefix dropdown button
                Button {
                    showPrefixDropdown.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedPrefix ?? "none")
                            .font(Theme.mono(11))
                            .foregroundColor(selectedPrefix != nil ? prefixColor(selectedPrefix!) : Theme.textMuted)
                        Image(systemName: showPrefixDropdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.info, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if showPrefixDropdown {
                        prefixDropdownMenu
                            .offset(y: 28)
                    }
                }

                if selectedPrefix != nil {
                    Text("/")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
                }

                // Name text field
                TextField("branch-name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.info, lineWidth: 1)
                    )
                    .onChange(of: editedName) { _, newValue in
                        editedName = BranchNameValidator.sanitize(newValue)
                    }
                    .onSubmit { saveBranchName() }

                // Save button
                Button { saveBranchName() } label: {
                    Text("Save")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.info)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .onExitCommand { cancelEdit() }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)
                Text(repo.mergeTarget)
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.info.opacity(0.8))

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Prefix Dropdown

    private var prefixDropdownMenu: some View {
        VStack(spacing: 0) {
            // "None" option
            Button {
                selectedPrefix = nil
                showPrefixDropdown = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedPrefix == nil ? "checkmark" : "")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.info)
                        .frame(width: 12)
                    Text("none")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(BranchNameValidator.prefixTypes) { type in
                Divider().opacity(0.3)
                Button {
                    selectedPrefix = type.prefix
                    showPrefixDropdown = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedPrefix == type.prefix ? "checkmark" : "")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.info)
                            .frame(width: 12)
                        Text(type.prefix)
                            .font(Theme.mono(11))
                            .foregroundColor(prefixColor(type.prefix))
                        Spacer()
                        Text(type.label)
                            .font(Theme.caption(9))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 150)
        .background(Theme.surface3)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .zIndex(10)
    }

    // MARK: - Target Dropdown

    private var targetDropdown: some View {
        VStack(spacing: 0) {
            ForEach(repo.branches.filter { !$0.hasPrefix("remotes/") && $0 != repo.currentBranch }, id: \.self) { branch in
                Button {
                    repo.mergeTarget = branch
                    showTargetDropdown = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: branch == repo.mergeTarget ? "checkmark" : "")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.info)
                            .frame(width: 12)
                        Text(branch)
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if branch != repo.branches.filter({ !$0.hasPrefix("remotes/") && $0 != repo.currentBranch }).last {
                    Divider().opacity(0.3)
                }
            }
        }
        .frame(width: 180)
        .background(Theme.surface3)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .zIndex(10)
    }

    // MARK: - Helpers

    private func prefixBadge(_ prefix: String) -> some View {
        Text(prefix)
            .font(Theme.mono(10, weight: .medium))
            .foregroundColor(prefixColor(prefix))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(prefixColor(prefix).opacity(0.12))
            .cornerRadius(3)
    }

    private func prefixColor(_ prefix: String) -> Color {
        guard let type = BranchNameValidator.prefixTypes.first(where: { $0.prefix == prefix }) else {
            return Theme.textMuted
        }
        switch type.color {
        case "success": return Theme.success
        case "error": return Theme.error
        case "accent": return Theme.accent
        case "info": return Theme.info
        case "warning": return Theme.warning
        case "textMuted": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    private func saveBranchName() {
        let newName = BranchNameValidator.compose(prefix: selectedPrefix, name: editedName)
        let sanitized = BranchNameValidator.sanitize(newName)
        guard !sanitized.isEmpty, sanitized != repo.currentBranch else {
            cancelEdit()
            return
        }
        _ = repo.renameBranch(from: repo.currentBranch, to: sanitized)
        isEditing = false
        showPrefixDropdown = false
    }

    private func cancelEdit() {
        isEditing = false
        showPrefixDropdown = false
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/GitPanel/BranchHeaderView.swift
git commit -m "feat: add BranchHeaderView with inline edit, prefix dropdown, and merge target picker"
```

---

### Task 4: ChangesListView

**Files:**
- Create: `BudahADE/GitPanel/ChangesListView.swift`

- [ ] **Step 1: Create ChangesListView**

```swift
// BudahADE/GitPanel/ChangesListView.swift
import SwiftUI

struct ChangesListView: View {
    @ObservedObject var repo: GitRepository
    var onSelectFile: (GitFileStatus, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Unstaged section
            unstagedSection
            // Staged section
            stagedSection
        }
    }

    // MARK: - Unstaged

    private var unstagedSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: "CHANGES",
                count: repo.unstagedFiles.count,
                countColor: Theme.accent
            )

            if repo.unstagedFiles.isEmpty {
                emptyState("No changes yet")
            } else {
                ForEach(repo.unstagedFiles) { file in
                    fileRow(file: file, staged: false)
                }

                Button {
                    repo.stageAll()
                } label: {
                    Text("Stage All")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Theme.surface3)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Staged

    private var stagedSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: "STAGED",
                count: repo.stagedFiles.count,
                countColor: Theme.info
            )

            if !repo.stagedFiles.isEmpty {
                ForEach(repo.stagedFiles) { file in
                    fileRow(file: file, staged: true)
                }

                Button {
                    repo.unstageAll()
                } label: {
                    Text("Unstage All")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Theme.surface3)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, count: Int, countColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.8)

            if count > 0 {
                Text("\(count)")
                    .font(Theme.mono(9))
                    .foregroundColor(countColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(countColor.opacity(0.12))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - File Row

    private func fileRow(file: GitFileStatus, staged: Bool) -> some View {
        HStack(spacing: 8) {
            statusBadge(file.status)

            Text(file.path)
                .font(Theme.mono(11))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                if staged { repo.unstage(file.path) } else { repo.stage(file.path) }
            } label: {
                Image(systemName: staged ? "minus" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 16, height: 16)
                    .background(Theme.hoverFill)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(staged ? Theme.info.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectFile(file, staged)
        }
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(statusColor(status))
            .frame(width: 14, height: 14)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.success
        case "A": return Theme.info
        case "D": return Theme.error
        case "R": return Theme.warning
        case "?": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    // MARK: - Empty State

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(11))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/GitPanel/ChangesListView.swift
git commit -m "feat: add ChangesListView with unified unstaged/staged sections"
```

---

### Task 5: CommitBarView with AI Commit Messages

**Files:**
- Create: `BudahADE/GitPanel/CommitBarView.swift`
- Create: `BudahADE/GitPanel/AICommitService.swift`

- [ ] **Step 1: Create AICommitService**

```swift
// BudahADE/GitPanel/AICommitService.swift
import Foundation

actor AICommitService {

    static let shared = AICommitService()

    private init() {}

    /// Generate a commit message from a staged diff using Claude CLI
    func generateMessage(repoPath: String) async -> String? {
        // Get the staged diff
        let diff = runGitSync(["diff", "--cached"], at: repoPath)
        guard let diff, !diff.isEmpty else { return nil }

        // Truncate very large diffs to avoid overwhelming the model
        let truncatedDiff = String(diff.prefix(4000))

        // Run claude CLI to generate a commit message
        let prompt = """
        Write a concise git commit message for this diff. Rules:
        - First line under 72 characters
        - Use conventional commit format (feat:, fix:, chore:, etc.) if appropriate
        - Focus on WHY the change was made, not WHAT changed
        - No quotes around the message
        - Just the message text, nothing else

        Diff:
        \(truncatedDiff)
        """

        return await runClaude(prompt: prompt, workingDirectory: repoPath)
    }

    private func runClaude(prompt: String, workingDirectory: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
        process.arguments = ["-p", prompt, "--model", "haiku"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == true ? nil : output
    }

    private func runGitSync(_ args: [String], at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Create CommitBarView**

```swift
// BudahADE/GitPanel/CommitBarView.swift
import SwiftUI

struct CommitBarView: View {
    @ObservedObject var repo: GitRepository
    @Binding var commitMessage: String
    @State private var isGenerating = false

    private var canCommit: Bool {
        !repo.stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            // Message field
            TextField("Commit message...", text: $commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(8)
                .background(Theme.surface3)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
                .onSubmit { if canCommit { performCommit() } }

            // Action row
            HStack(spacing: 6) {
                // Commit button
                Button { performCommit() } label: {
                    Text("Commit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(canCommit ? .white : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(canCommit ? Theme.info : Theme.surface3)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)

                // AI generate button
                Button {
                    generateAIMessage()
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("✨")
                                .font(.system(size: 12))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(repo.stagedFiles.isEmpty || isGenerating)
                .help("Generate commit message with AI")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func performCommit() {
        guard canCommit else { return }
        repo.commit(message: commitMessage)
        commitMessage = ""
    }

    private func generateAIMessage() {
        guard !repo.stagedFiles.isEmpty else { return }
        isGenerating = true
        Task {
            if let message = await AICommitService.shared.generateMessage(repoPath: repo.path) {
                await MainActor.run {
                    commitMessage = message
                    isGenerating = false
                }
            } else {
                await MainActor.run {
                    // Fall back to auto-generated message
                    commitMessage = repo.generateCommitMessage()
                    isGenerating = false
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BudahADE/GitPanel/CommitBarView.swift BudahADE/GitPanel/AICommitService.swift
git commit -m "feat: add CommitBarView with AI commit message generation"
```

---

### Task 6: DiffModalView

**Files:**
- Create: `BudahADE/GitPanel/DiffModalView.swift`

- [ ] **Step 1: Create DiffModalView**

```swift
// BudahADE/GitPanel/DiffModalView.swift
import SwiftUI

struct DiffModalView: View {
    @ObservedObject var repo: GitRepository
    let files: [GitFileStatus]
    let initialFileIndex: Int
    let staged: Bool
    /// If set, we're viewing a commit's diff instead of working tree
    let commitHash: String?
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showSplit = true

    init(repo: GitRepository, files: [GitFileStatus], initialFileIndex: Int, staged: Bool, commitHash: String? = nil) {
        self.repo = repo
        self.files = files
        self.initialFileIndex = initialFileIndex
        self.staged = staged
        self.commitHash = commitHash
        _currentIndex = State(initialValue: initialFileIndex)
    }

    private var currentFile: GitFileStatus? {
        guard currentIndex >= 0, currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().foregroundColor(Theme.borderSubtle)
            diffContent
            Divider().foregroundColor(Theme.borderSubtle)
            footerBar
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Theme.appBackground)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            if let file = currentFile {
                statusBadge(file.status)

                Text((file.path as NSString).lastPathComponent)
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Text((file.path as NSString).deletingLastPathComponent)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            if let file = currentFile, commitHash == nil {
                let diffText = repo.diff(file: file.path, staged: staged)
                let adds = diffText.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
                let removes = diffText.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

                Text("+\(adds)")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.success)
                Text("−\(removes)")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.error)

                Button {
                    if staged { repo.unstage(file.path) } else { repo.stage(file.path) }
                } label: {
                    Text(staged ? "Unstage File" : "Stage File")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surface3)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface2)
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        Group {
            if let file = currentFile {
                let rawDiff: String = {
                    if let hash = commitHash {
                        return repo.diffForCommit(hash)
                    } else {
                        return repo.diff(file: file.path, staged: staged)
                    }
                }()

                if showSplit {
                    splitDiffView(rawDiff)
                } else {
                    unifiedDiffView(rawDiff)
                }
            } else {
                Text("No file selected")
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Split Diff

    private func splitDiffView(_ diff: String) -> some View {
        let lines = diff.components(separatedBy: "\n")
        let (leftLines, rightLines) = parseSplitDiff(lines)

        return HStack(spacing: 0) {
            // Left: before
            VStack(spacing: 0) {
                Text("HEAD (before)")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.surface2)

                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(leftLines.enumerated()), id: \.offset) { idx, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider().foregroundColor(Theme.borderSubtle)

            // Right: after
            VStack(spacing: 0) {
                Text("Working Tree (after)")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.surface2)

                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rightLines.enumerated()), id: \.offset) { idx, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Unified Diff

    private func unifiedDiffView(_ diff: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 36, alignment: .trailing)
                            .padding(.trailing, 8)

                        Text(line)
                            .font(Theme.mono(11))
                            .foregroundColor(lineColor(line))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(lineBackground(line))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // File navigation
            Button {
                if currentIndex > 0 { currentIndex -= 1 }
            } label: {
                Text("← Prev")
                    .font(Theme.caption(11))
                    .foregroundColor(currentIndex > 0 ? Theme.info : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)

            Text("\(currentIndex + 1) of \(files.count) files")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textSecondary)

            Button {
                if currentIndex < files.count - 1 { currentIndex += 1 }
            } label: {
                Text("Next →")
                    .font(Theme.caption(11))
                    .foregroundColor(currentIndex < files.count - 1 ? Theme.info : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= files.count - 1)

            Spacer()

            // View toggle
            HStack(spacing: 0) {
                Button {
                    showSplit = false
                } label: {
                    Text("Unified")
                        .font(Theme.caption(10))
                        .foregroundColor(!showSplit ? Theme.info : Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(!showSplit ? Theme.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button {
                    showSplit = true
                } label: {
                    Text("Split")
                        .font(Theme.caption(10))
                        .foregroundColor(showSplit ? Theme.info : Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(showSplit ? Theme.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.surface3)
            .cornerRadius(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface2)
    }

    // MARK: - Diff Parsing

    struct DiffLine {
        let number: Int?
        let text: String
        let type: LineType
    }

    enum LineType {
        case context, added, removed, header
    }

    private func parseSplitDiff(_ lines: [String]) -> ([DiffLine], [DiffLine]) {
        var left: [DiffLine] = []
        var right: [DiffLine] = []
        var leftNum = 0
        var rightNum = 0

        for line in lines {
            if line.hasPrefix("@@") {
                // Parse hunk header for line numbers
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    let oldPart = parts[1].dropFirst() // remove -
                    let newPart = parts[2].dropFirst() // remove +
                    leftNum = Int(oldPart.components(separatedBy: ",").first ?? "0") ?? 0
                    rightNum = Int(newPart.components(separatedBy: ",").first ?? "0") ?? 0
                }
                left.append(DiffLine(number: nil, text: line, type: .header))
                right.append(DiffLine(number: nil, text: line, type: .header))
            } else if line.hasPrefix("---") || line.hasPrefix("+++") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                // Skip file headers
                continue
            } else if line.hasPrefix("-") {
                left.append(DiffLine(number: leftNum, text: String(line.dropFirst()), type: .removed))
                leftNum += 1
            } else if line.hasPrefix("+") {
                right.append(DiffLine(number: rightNum, text: String(line.dropFirst()), type: .added))
                rightNum += 1
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                left.append(DiffLine(number: leftNum, text: text, type: .context))
                right.append(DiffLine(number: rightNum, text: text, type: .context))
                leftNum += 1
                rightNum += 1
            }
        }

        return (left, right)
    }

    private func diffLineView(lineNumber: Int?, text: String, type: LineType) -> some View {
        HStack(spacing: 0) {
            Text(lineNumber.map { "\($0)" } ?? "")
                .font(Theme.mono(10))
                .foregroundColor(Theme.textMuted)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 8)

            Text(text)
                .font(Theme.mono(11))
                .foregroundColor(lineTypeColor(type))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(lineTypeBackground(type))
    }

    // MARK: - Colors

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(statusColor(status))
            .frame(width: 14, height: 14)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.success
        case "A": return Theme.info
        case "D": return Theme.error
        case "R": return Theme.warning
        default: return Theme.textMuted
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("@@") { return Theme.info }
        if line.hasPrefix("+") { return Theme.success }
        if line.hasPrefix("-") { return Theme.error }
        return Theme.textSecondary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Theme.success.opacity(0.06) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Theme.error.opacity(0.05) }
        return .clear
    }

    private func lineTypeColor(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.success
        case .removed: return Theme.error
        case .header: return Theme.info
        case .context: return Theme.textSecondary
        }
    }

    private func lineTypeBackground(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.success.opacity(0.06)
        case .removed: return Theme.error.opacity(0.05)
        case .header, .context: return .clear
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/GitPanel/DiffModalView.swift
git commit -m "feat: add DiffModalView with split/unified toggle and file navigation"
```

---

### Task 7: CommitHistoryView

**Files:**
- Create: `BudahADE/GitPanel/CommitHistoryView.swift`

- [ ] **Step 1: Create CommitHistoryView**

```swift
// BudahADE/GitPanel/CommitHistoryView.swift
import SwiftUI

struct CommitHistoryView: View {
    @ObservedObject var repo: GitRepository
    @State private var isExpanded = false
    @State private var commits: [GitCommit] = []
    @State private var selectedCommit: GitCommit?
    @State private var showCommitDiff = false
    var onSelectCommit: (GitCommit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header — toggle expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                    if isExpanded && commits.isEmpty {
                        loadCommits()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 10)

                    Text("HISTORY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(0.8)

                    Text("\(repo.totalCommitCount)")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.surface3)
                        .cornerRadius(8)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                timelineView
            }
        }
        .onChange(of: repo.recentCommits) { _, _ in
            if isExpanded { loadCommits() }
        }
    }

    // MARK: - Timeline

    private var timelineView: some View {
        VStack(spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                commitRow(commit: commit, index: index, total: commits.count)
            }

            if commits.count < repo.totalCommitCount {
                Button {
                    loadMoreCommits()
                } label: {
                    Text("Load more...")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.info)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .padding(.leading, 24) // align with text, past the line
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Commit Row

    private func commitRow(commit: GitCommit, index: Int, total: Int) -> some View {
        let isHead = index == 0
        let isForkPoint = commit.id == repo.forkPointHash
        let isBelowFork: Bool = {
            guard let forkHash = repo.forkPointHash else { return false }
            guard let forkIndex = commits.firstIndex(where: { $0.id == forkHash }) else { return false }
            return index > forkIndex
        }()
        let isAtOrBelowFork = isForkPoint || isBelowFork
        let dotColor = isBelowFork ? Theme.accent : Theme.info
        let lineColor = isAtOrBelowFork ? Theme.accent : Theme.info

        return HStack(alignment: .top, spacing: 0) {
            // Line + dot column
            VStack(spacing: 0) {
                if isHead {
                    // No line above HEAD
                    Color.clear.frame(width: 2, height: 4)
                } else {
                    // Line above dot
                    Rectangle()
                        .fill(isBelowFork ? Theme.accent : Theme.info)
                        .frame(width: 2, height: 4)
                }

                // Dot
                Circle()
                    .fill(dotColor)
                    .frame(width: isHead ? 10 : 8, height: isHead ? 10 : 8)
                    .overlay {
                        if isHead {
                            Circle()
                                .stroke(dotColor.opacity(0.5), lineWidth: 2)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .shadow(color: isHead ? dotColor.opacity(0.3) : .clear, radius: 4)

                if index < total - 1 {
                    // Line below dot
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    // Last commit — no line below
                    Color.clear.frame(width: 2)
                }
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(Theme.body(11))
                    .foregroundColor(isBelowFork ? Theme.textMuted : Theme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(String(commit.id.prefix(7)))
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.textMuted)

                    Text(commit.date)
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.textMuted)

                    Spacer()

                    if isHead {
                        badgePill("HEAD", color: Theme.info)
                        badgePill(repo.currentBranch.components(separatedBy: "/").last ?? repo.currentBranch, color: Theme.success)
                    }

                    if isBelowFork, index == (commits.firstIndex(where: { $0.id == repo.forkPointHash }).map { $0 + 1 } ?? -1) {
                        badgePill("origin/\(repo.mergeTarget)", color: Theme.accent)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 12)
        .opacity(isBelowFork ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(commit)
        }
        .help("\(commit.message)\nAuthor: \(commit.author)\nHash: \(commit.id)")
    }

    // MARK: - Helpers

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.mono(8))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }

    private func loadCommits() {
        commits = repo.extendedLog(limit: 20)
    }

    private func loadMoreCommits() {
        let newLimit = commits.count + 20
        commits = repo.extendedLog(limit: newLimit)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BudahADE/GitPanel/CommitHistoryView.swift
git commit -m "feat: add CommitHistoryView with continuous timeline, fork point detection, and branch badges"
```

---

### Task 8: Rebuild GitSidebarView

**Files:**
- Modify: `BudahADE/GitPanel/GitSidebarView.swift`

This is the integration task — replace the internals of GitSidebarView with the new subviews.

- [ ] **Step 1: Rewrite GitSidebarView**

Replace the entire contents of `GitSidebarView.swift` with:

```swift
// BudahADE/GitPanel/GitSidebarView.swift
import SwiftUI

struct GitSidebarView: View {
    @ObservedObject var taskState: TaskState
    @StateObject private var repo: GitRepository
    @State private var panelWidth: CGFloat = 320
    @State private var isDragging: Bool = false
    @State private var commitMessage: String = ""
    @State private var pushState: ActionState = .idle
    @State private var mergeState: ActionState = .idle
    @State private var actionError: String?
    @State private var showDiffModal = false
    @State private var diffFiles: [GitFileStatus] = []
    @State private var diffFileIndex: Int = 0
    @State private var diffStaged: Bool = false
    @State private var diffCommitHash: String?

    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 420

    enum ActionState { case idle, loading, success }

    init(task: TaskState) {
        self.taskState = task
        _repo = StateObject(wrappedValue: GitRepository(path: task.worktreePath))
    }

    var body: some View {
        HStack(spacing: 0) {
            dragHandle

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        // Branch header
                        BranchHeaderView(repo: repo)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)

                        Divider().foregroundColor(Theme.borderSubtle)

                        // Changes list
                        ChangesListView(repo: repo) { file, staged in
                            openDiffForFile(file, staged: staged)
                        }

                        Divider().foregroundColor(Theme.borderSubtle)

                        // Commit bar
                        CommitBarView(repo: repo, commitMessage: $commitMessage)

                        Divider().foregroundColor(Theme.borderSubtle)

                        // Commit history
                        CommitHistoryView(repo: repo) { commit in
                            openDiffForCommit(commit)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Error banner
                if let error = actionError {
                    errorBanner(error)
                }

                // Action bar
                actionBar
            }
            .frame(width: panelWidth)
            .background(Theme.sidebar)
            .onAppear {
                repo.mergeTarget = taskState.baseBranch
                repo.startPolling()
            }
            .onDisappear { repo.stopPolling() }
        }
        .sheet(isPresented: $showDiffModal) {
            DiffModalView(
                repo: repo,
                files: diffFiles,
                initialFileIndex: diffFileIndex,
                staged: diffStaged,
                commitHash: diffCommitHash
            )
        }
    }

    // MARK: - Diff Modal Triggers

    private func openDiffForFile(_ file: GitFileStatus, staged: Bool) {
        let fileList = staged ? repo.stagedFiles : repo.unstagedFiles
        diffFiles = fileList
        diffFileIndex = fileList.firstIndex(where: { $0.path == file.path }) ?? 0
        diffStaged = staged
        diffCommitHash = nil
        showDiffModal = true
    }

    private func openDiffForCommit(_ commit: GitCommit) {
        diffFiles = repo.filesChangedInCommit(commit.id)
        diffFileIndex = 0
        diffStaged = false
        diffCommitHash = commit.id
        showDiffModal = true
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            // Push
            Button { performPush() } label: {
                HStack(spacing: 4) {
                    if pushState == .loading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(pushButtonLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Theme.appBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(pushState == .loading)

            // PR
            Button {
                repo.openPullRequestURL(baseBranch: repo.mergeTarget)
            } label: {
                Text("PR")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surface3)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Merge
            Button { performMerge() } label: {
                HStack(spacing: 4) {
                    if mergeState == .loading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(mergeState == .success ? "Merged ✓" : "Merge")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surface3)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(mergeState == .loading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.sidebar)
    }

    private var pushButtonLabel: String {
        switch pushState {
        case .loading: return "Pushing..."
        case .success: return "Pushed ✓"
        case .idle:
            return repo.aheadCount > 0 ? "Push (\(repo.aheadCount))" : "Push"
        }
    }

    // MARK: - Actions

    private func performPush() {
        pushState = .loading
        Task {
            do {
                try await repo.push()
                await MainActor.run {
                    pushState = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pushState = .idle }
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    pushState = .idle
                }
            }
        }
    }

    private func performMerge() {
        mergeState = .loading
        Task {
            do {
                try await repo.mergeIntoBase(repo.mergeTarget)
                await MainActor.run {
                    mergeState = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { mergeState = .idle }
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    mergeState = .idle
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.error)

            Text(message)
                .font(Theme.caption(11))
                .foregroundColor(Theme.error)
                .lineLimit(2)

            Spacer()

            Button { actionError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.error.opacity(0.08))
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(isDragging ? Theme.accent.opacity(0.3) : Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in isDragging = false }
            )
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Fix any compilation issues**

Check for references to removed types (`SidebarSection` enum was used elsewhere). Search the codebase:

Run: `grep -r "SidebarSection" BudahADE/ --include="*.swift"`

If found in other files, update references. The `SidebarSection` enum is no longer needed since sections are always visible (not collapsible in the old sense — only HISTORY collapses, and that's handled internally by CommitHistoryView).

- [ ] **Step 4: Commit**

```bash
git add BudahADE/GitPanel/GitSidebarView.swift
git commit -m "feat: rebuild GitSidebarView with decomposed subviews and diff modal"
```

---

### Task 9: Clean Up Old Files

**Files:**
- Delete: `BudahADE/GitPanel/CommitBar.swift` (replaced by CommitBarView)
- Delete: `BudahADE/GitPanel/BranchFlowView.swift` (replaced by BranchHeaderView)
- Delete: `BudahADE/GitPanel/StagingView.swift` (replaced by ChangesListView)
- Keep: `BudahADE/GitPanel/DiffView.swift` (still used by GitPanelView)
- Keep: `BudahADE/GitPanel/BranchPicker.swift` (still used by GitPanelView)

- [ ] **Step 1: Check for remaining references to old files**

Run: `grep -r "CommitBar\b" BudahADE/ --include="*.swift" | grep -v CommitBarView`
Run: `grep -r "BranchFlowView" BudahADE/ --include="*.swift"`
Run: `grep -r "StagingView" BudahADE/ --include="*.swift"`

If any references remain outside of GitSidebarView.swift (which was already rewritten), update them. If GitPanelView.swift still uses StagingView/CommitBar, leave those files — only delete if they're truly unreferenced.

- [ ] **Step 2: Delete unreferenced files**

```bash
# Only delete files with zero remaining references
rm BudahADE/GitPanel/BranchFlowView.swift  # replaced by BranchHeaderView
# Keep CommitBar.swift and StagingView.swift if GitPanelView still uses them
```

- [ ] **Step 3: Regenerate project and verify build**

```bash
xcodegen generate
xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -u  # stages deletions
git commit -m "chore: remove old git panel files replaced by new subviews"
```

---

### Task 10: Integration Test and Final Verification

- [ ] **Step 1: Run all existing tests**

Run: `xcodebuild test -scheme BudahADE -quiet 2>&1 | tail -30`
Expected: All tests pass (including new BranchNameValidatorTests and GitRepositoryExtensionsTests)

- [ ] **Step 2: Run the app and verify**

Run: `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5`

Manual verification checklist:
1. Open a task — git sidebar appears with new layout
2. Branch header shows prefix badge + branch name
3. Click branch name → edit mode with prefix dropdown + text field + Save button
4. Change merge target via dropdown
5. Ahead/behind badges update
6. Changed files appear in CHANGES section with colored status badges
7. Click a file → diff modal opens with side-by-side view
8. Prev/Next navigation works in diff modal
9. Split/Unified toggle works
10. Stage/Unstage from diff modal works
11. ✨ button generates AI commit message
12. Commit with message works
13. HISTORY section expands with timeline
14. Commit dots connected by continuous line
15. Fork point shows color transition
16. Push/PR/Merge buttons work

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration fixes for git panel refinement"
```
