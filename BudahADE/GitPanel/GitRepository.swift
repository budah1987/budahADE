import Foundation
import Combine
import AppKit

// MARK: - Models

struct GitFileStatus: Identifiable {
    let id = UUID()
    let status: String // M, A, D, R, ?
    let path: String
}

struct GitCommit: Identifiable {
    let id: String // commit hash
    let message: String
    let author: String
    let date: String
}

enum GitError: Error, LocalizedError {
    case commandFailed(String)
    case noRemote
    case mergeConflict

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .noRemote: return "No remote configured"
        case .mergeConflict: return "Merge conflict — resolve in terminal"
        }
    }
}

// MARK: - Git Repository

final class GitRepository: ObservableObject {
    let path: String

    @Published var currentBranch: String = ""
    @Published var branches: [String] = []
    @Published var stagedFiles: [GitFileStatus] = []
    @Published var unstagedFiles: [GitFileStatus] = []
    @Published var recentCommits: [GitCommit] = []
    @Published var hasRemote: Bool = false
    @Published var aheadCount: Int = 0
    @Published var mergeTarget: String = "main"
    @Published var behindCount: Int = 0
    @Published var forkPointHash: String?
    @Published var totalCommitCount: Int = 0

    private var pollTimer: Timer?

    init(path: String) {
        self.path = path
        refresh()
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Refresh

    func refresh() {
        parseStatus()
        parseBranches()
        parseLog()
        parseRemoteStatus()
        parseMergeInfo()
    }

    // MARK: - Git Operations

    func stage(_ file: String) {
        _ = runGit(["add", "--", file])
        refresh()
    }

    func unstage(_ file: String) {
        _ = runGit(["reset", "HEAD", "--", file])
        refresh()
    }

    func stageAll() {
        _ = runGit(["add", "-A"])
        refresh()
    }

    func unstageAll() {
        _ = runGit(["reset", "HEAD"])
        refresh()
    }

    func commit(message: String) {
        _ = runGit(["commit", "-m", message])
        refresh()
    }

    func checkout(branch: String) {
        _ = runGit(["checkout", branch])
        refresh()
    }

    func createBranch(_ name: String) -> Bool {
        let result = runGit(["checkout", "-b", name])
        if result != nil {
            refresh()
            return true
        }
        return false
    }

    func diff(file: String, staged: Bool) -> String {
        var args = ["diff"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", file])
        return runGit(args) ?? ""
    }

    // MARK: - Push

    func push() async throws {
        let result = try await runGitAsync(["push", "-u", "origin", currentBranch])
        if result.contains("error") || result.contains("fatal") {
            throw GitError.commandFailed(result)
        }
        await MainActor.run { refresh() }
    }

    // MARK: - Merge

    func mergeIntoBase(_ baseBranch: String) async throws {
        // Switch to base branch
        let checkoutResult = try await runGitAsync(["checkout", baseBranch])
        if checkoutResult.contains("error") {
            throw GitError.commandFailed(checkoutResult)
        }

        // Merge current branch
        let branchToMerge = currentBranch
        let mergeResult = try await runGitAsync(["merge", "--no-ff", branchToMerge])
        if mergeResult.contains("CONFLICT") {
            // Restore original branch before throwing
            _ = try? await runGitAsync(["checkout", branchToMerge])
            throw GitError.mergeConflict
        }

        // Switch back
        _ = try? await runGitAsync(["checkout", branchToMerge])
        await MainActor.run { refresh() }
    }

    // MARK: - Open PR in Browser

    func openPullRequestURL(baseBranch: String) {
        guard let remoteURL = runGit(["remote", "get-url", "origin"]) else { return }

        // Convert SSH or HTTPS remote URL to GitHub web URL
        let webURL: String
        if remoteURL.hasPrefix("git@github.com:") {
            let repoPath = remoteURL
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            webURL = "https://github.com/\(repoPath)"
        } else if remoteURL.contains("github.com") {
            webURL = remoteURL
                .replacingOccurrences(of: ".git", with: "")
        } else {
            return // Not a GitHub remote
        }

        let compareURL = "\(webURL)/compare/\(baseBranch)...\(currentBranch)?expand=1"
        if let url = URL(string: compareURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Auto-generate Commit Message

    func generateCommitMessage() -> String {
        let added = stagedFiles.filter { $0.status == "A" || $0.status == "?" }
        let modified = stagedFiles.filter { $0.status == "M" }
        let deleted = stagedFiles.filter { $0.status == "D" }
        let renamed = stagedFiles.filter { $0.status == "R" }

        // If 3 or fewer total files, name them
        let total = stagedFiles.count
        if total == 0 { return "" }

        if total <= 3 {
            let names = stagedFiles.map { shortName($0.path) }
            let verb: String
            if !modified.isEmpty {
                verb = "Update"
            } else if !added.isEmpty {
                verb = "Add"
            } else if !deleted.isEmpty {
                verb = "Remove"
            } else {
                verb = "Update"
            }
            return "\(verb) \(names.joined(separator: ", "))"
        }

        // More than 3 files: group by operation
        var parts: [String] = []
        if !added.isEmpty { parts.append("add \(added.count) file\(added.count == 1 ? "" : "s")") }
        if !modified.isEmpty { parts.append("update \(modified.count) file\(modified.count == 1 ? "" : "s")") }
        if !deleted.isEmpty { parts.append("remove \(deleted.count) file\(deleted.count == 1 ? "" : "s")") }
        if !renamed.isEmpty { parts.append("rename \(renamed.count) file\(renamed.count == 1 ? "" : "s")") }

        let message = parts.joined(separator: ", ")
        return message.prefix(1).uppercased() + message.dropFirst()
    }

    private func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Parsing

    func parseStatus() {
        guard let output = runGit(["status", "--porcelain=v2"]) else {
            stagedFiles = []
            unstagedFiles = []
            return
        }

        var staged: [GitFileStatus] = []
        var unstaged: [GitFileStatus] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]
                let filePath: String
                if line.hasPrefix("2 ") {
                    let pathParts = parts[9...].joined(separator: " ")
                    filePath = pathParts.components(separatedBy: "\t").first ?? pathParts
                } else {
                    filePath = parts[8...].joined(separator: " ")
                }
                let xIndex = xy.startIndex
                let yIndex = xy.index(after: xIndex)
                let x = String(xy[xIndex])
                let y = String(xy[yIndex])

                if x != "." {
                    staged.append(GitFileStatus(status: mapStatusChar(x), path: filePath))
                }
                if y != "." {
                    unstaged.append(GitFileStatus(status: mapStatusChar(y), path: filePath))
                }
            } else if line.hasPrefix("? ") {
                let filePath = String(line.dropFirst(2))
                unstaged.append(GitFileStatus(status: "?", path: filePath))
            }
        }

        self.stagedFiles = staged
        self.unstagedFiles = unstaged
    }

    func parseBranches() {
        if let headOutput = runGit(["rev-parse", "--abbrev-ref", "HEAD"]) {
            currentBranch = headOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let output = runGit(["branch", "-a", "--sort=-committerdate"]) else {
            branches = []
            return
        }

        branches = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.contains("->") }
    }

    func parseLog() {
        guard let output = runGit(["log", "--oneline", "-10", "--format=%H|||%s|||%an|||%ar"]) else {
            recentCommits = []
            return
        }

        recentCommits = output
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

    func parseRemoteStatus() {
        // Check if remote exists
        hasRemote = runGit(["remote", "get-url", "origin"]) != nil

        // Count commits ahead of base
        if hasRemote, !currentBranch.isEmpty {
            if let output = runGit(["rev-list", "--count", "origin/\(currentBranch)..HEAD"]) {
                aheadCount = Int(output) ?? 0
            } else {
                // Branch may not exist on remote yet — all commits are "ahead"
                if let output = runGit(["rev-list", "--count", "HEAD"]) {
                    aheadCount = Int(output) ?? 0
                }
            }
        } else {
            aheadCount = 0
        }
    }

    // MARK: - Extended Parsing

    func parseMergeInfo() {
        if !mergeTarget.isEmpty, !currentBranch.isEmpty {
            if let output = runGit(["rev-list", "--count", "HEAD..\(mergeTarget)"]) {
                behindCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            } else {
                behindCount = 0
            }
        }

        if !mergeTarget.isEmpty {
            if let output = runGit(["merge-base", "HEAD", mergeTarget]) {
                forkPointHash = output.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                forkPointHash = nil
            }
        }

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

    // MARK: - Static Helpers

    /// Groups branches into "on GitHub" vs "local only".
    /// Queries the remote directly via ls-remote for accuracy — local tracking refs
    /// go stale until `git fetch --prune` is run, so we can't rely on them.
    /// Falls back to local-only listing if there is no remote or network is unavailable.
    static func listBranchesGrouped(at repoPath: String) async -> (local: [String], remote: [String]) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                func run(_ args: [String]) -> String {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    process.arguments = args
                    process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = Pipe()
                    try? process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(data: data, encoding: .utf8) ?? ""
                }

                // Local branches — always accurate
                let localOutput = run(["for-each-ref", "refs/heads/", "--format=%(refname:short)"])
                let localBranches = localOutput
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Live remote branches from GitHub — single lightweight network call
                // ls-remote output: "<hash>\trefs/heads/<name>"
                let remoteOutput = run(["ls-remote", "--heads", "origin"])
                let remoteBranches: Set<String> = Set(
                    remoteOutput
                        .components(separatedBy: .newlines)
                        .compactMap { line -> String? in
                            guard let tabIdx = line.firstIndex(of: "\t") else { return nil }
                            let ref = String(line[line.index(after: tabIdx)...])
                            let prefix = "refs/heads/"
                            guard ref.hasPrefix(prefix) else { return nil }
                            return String(ref.dropFirst(prefix.count))
                        }
                )

                if remoteBranches.isEmpty {
                    // No remote / offline — just show all local branches in one group
                    continuation.resume(returning: (
                        local: localBranches.isEmpty ? ["main"] : localBranches,
                        remote: []
                    ))
                    return
                }

                var onGitHub: [String] = []
                var localOnly: [String] = []
                for branch in localBranches {
                    if remoteBranches.contains(branch) {
                        onGitHub.append(branch)
                    } else {
                        localOnly.append(branch)
                    }
                }
                // Remote branches not checked out locally
                let localSet = Set(localBranches)
                let remoteOnly = remoteBranches.subtracting(localSet).sorted()

                continuation.resume(returning: (
                    local: onGitHub + remoteOnly,
                    remote: localOnly
                ))
            }
        }
    }

    static func listBranches(at repoPath: String) async -> [String] {
        let grouped = await listBranchesGrouped(at: repoPath)
        return grouped.local + grouped.remote
    }

    // MARK: - Private

    private func runGit(_ args: [String]) -> String? {
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
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGitAsync(_ args: [String]) async throws -> String {
        let repoPath = path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(throwing: GitError.commandFailed(error.localizedDescription))
                    return
                }

                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: GitError.commandFailed(stderr.isEmpty ? stdout : stderr))
                } else {
                    continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    func mapStatusChar(_ char: String) -> String {
        switch char {
        case "M": return "M"
        case "A": return "A"
        case "D": return "D"
        case "R": return "R"
        case "?": return "?"
        default: return char
        }
    }
}
