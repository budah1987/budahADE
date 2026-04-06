import Foundation
import Combine
import AppKit

// MARK: - Models

struct GitFileStatus: Identifiable, Equatable, Hashable {
    var id: String { "\(status):\(path)" }
    let status: String // M, A, D, R, ?
    let path: String
}

struct GitCommit: Identifiable {
    let id: String // commit hash
    let message: String
    let author: String
    let date: String
}

struct CommitDetail {
    let hash: String
    let subject: String
    let body: String
    let author: String
    let date: String
    let parentCount: Int
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

@MainActor
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
    private var refreshDebounceTask: Task<Void, Never>?
    private var lastActivityTime = Date()

    // Diff cache: keyed by "staged:filepath" or "hash:filepath"
    private var diffCache: [String: (result: String, timestamp: Date)] = [:]
    private let diffCacheTTL: TimeInterval = 10 // seconds

    // Polling intervals
    private let activeInterval: TimeInterval = 3.0
    private let idleInterval: TimeInterval = 8.0
    private let idleThreshold: TimeInterval = 30.0 // seconds of no user action before going idle

    init(path: String) {
        self.path = path
        refresh()
    }

    // MARK: - Polling (adaptive)

    func startPolling() {
        stopPolling()
        scheduleNextPoll()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        let interval = Date().timeIntervalSince(lastActivityTime) > idleThreshold ? idleInterval : activeInterval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.scheduleNextPoll()
            }
        }
    }

    /// Mark the repo as actively used (resets idle timer, invalidates diff cache)
    private func markActive() {
        lastActivityTime = Date()
        diffCache.removeAll()
    }

    // MARK: - Refresh (debounced)

    func refresh() {
        parseStatus()
        parseBranches()
        parseLog()
        parseRemoteStatus()
        parseMergeInfo()
    }

    /// Debounced refresh — collapses rapid sequential calls (e.g. staging 10 files)
    private func debouncedRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Git Operations

    func stage(_ file: String) {
        _ = runGit(["add", "--", file])
        markActive()
        debouncedRefresh()
    }

    func unstage(_ file: String) {
        _ = runGit(["reset", "HEAD", "--", file])
        markActive()
        debouncedRefresh()
    }

    func stageAll() {
        _ = runGit(["add", "-A"])
        markActive()
        debouncedRefresh()
    }

    func unstageAll() {
        _ = runGit(["reset", "HEAD"])
        markActive()
        debouncedRefresh()
    }

    func commit(message: String) {
        _ = runGit(["commit", "-m", message])
        markActive()
        refresh()
    }

    func checkout(branch: String) {
        _ = runGit(["checkout", branch])
        markActive()
        refresh()
    }

    func createBranch(_ name: String) -> Bool {
        let result = runGit(["checkout", "-b", name])
        if result != nil {
            markActive()
            refresh()
            return true
        }
        return false
    }

    func diff(file: String, staged: Bool) -> String {
        let cacheKey = "\(staged ? "staged" : "unstaged"):\(file)"
        if let cached = diffCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < diffCacheTTL {
            return cached.result
        }
        var args = ["diff"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", file])
        let result = runGit(args) ?? ""
        diffCache[cacheKey] = (result, Date())
        return result
    }

    // MARK: - Push

    func push() async throws {
        markActive()
        let result = try await runGitAsync(["push", "-u", "origin", currentBranch])
        if result.contains("error") || result.contains("fatal") {
            throw GitError.commandFailed(result)
        }
        await MainActor.run { refresh() }
    }

    // MARK: - Merge

    func mergeIntoBase(_ baseBranch: String) async throws {
        markActive()
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

        if self.stagedFiles != staged { self.stagedFiles = staged }
        if self.unstagedFiles != unstaged { self.unstagedFiles = unstaged }
    }

    func parseBranches() {
        if let headOutput = runGit(["rev-parse", "--abbrev-ref", "HEAD"]) {
            let newBranch = headOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentBranch != newBranch { currentBranch = newBranch }
        }

        guard let output = runGit(["branch", "-a", "--sort=-committerdate"]) else {
            if !branches.isEmpty { branches = [] }
            return
        }

        let newBranches = output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.contains("->") }
        if branches != newBranches { branches = newBranches }
    }

    func parseLog() {
        guard let output = runGit(["log", "--oneline", "-10", "--format=%H|||%s|||%an|||%ar"]) else {
            if !recentCommits.isEmpty { recentCommits = [] }
            return
        }

        let newCommits = output
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
        // Compare by commit hashes to avoid unnecessary publishes
        if recentCommits.map(\.id) != newCommits.map(\.id) {
            recentCommits = newCommits
        }
    }

    func parseRemoteStatus() {
        // Check if remote exists
        let newHasRemote = runGit(["remote", "get-url", "origin"]) != nil
        if hasRemote != newHasRemote { hasRemote = newHasRemote }

        // Count commits ahead of base
        if newHasRemote, !currentBranch.isEmpty {
            if let output = runGit(["rev-list", "--count", "origin/\(currentBranch)..HEAD"]) {
                let newCount = Int(output) ?? 0
                if aheadCount != newCount { aheadCount = newCount }
            } else {
                // Branch may not exist on remote yet — all commits are "ahead"
                if let output = runGit(["rev-list", "--count", "HEAD"]) {
                    let newCount = Int(output) ?? 0
                    if aheadCount != newCount { aheadCount = newCount }
                }
            }
        } else {
            if aheadCount != 0 { aheadCount = 0 }
        }
    }

    // MARK: - Extended Parsing

    func parseMergeInfo() {
        if !mergeTarget.isEmpty, !currentBranch.isEmpty {
            if let output = runGit(["rev-list", "--count", "HEAD..\(mergeTarget)"]) {
                let newCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                if behindCount != newCount { behindCount = newCount }
            } else {
                if behindCount != 0 { behindCount = 0 }
            }
        }

        if !mergeTarget.isEmpty {
            if let output = runGit(["merge-base", "HEAD", mergeTarget]) {
                let newHash = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if forkPointHash != newHash { forkPointHash = newHash }
            } else {
                if forkPointHash != nil { forkPointHash = nil }
            }
        }

        if let output = runGit(["rev-list", "--count", "HEAD"]) {
            let newCount = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if totalCommitCount != newCount { totalCommitCount = newCount }
        }
    }

    func renameBranch(from oldName: String, to newName: String) -> Bool {
        let result = runGit(["branch", "-m", oldName, newName])
        if result != nil {
            markActive()
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

    func commitDetail(_ hash: String) -> CommitDetail? {
        // %H=hash, %s=subject, %b=body, %an=author, %ar=relative date, %P=parent hashes
        guard let output = runGit(["show", "-s", "--format=%H|||%s|||%b|||%an|||%ar|||%P", hash]) else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }
        let parentHashes = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let parentCount = parentHashes.isEmpty ? 0 : parentHashes.components(separatedBy: " ").count
        return CommitDetail(
            hash: parts[0],
            subject: parts[1],
            body: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
            author: parts[3],
            date: parts[4],
            parentCount: parentCount
        )
    }

    func diffForCommit(_ hash: String) -> String {
        return runGit(["show", "--format=", hash]) ?? ""
    }

    func diffForCommitFile(_ hash: String, file: String) -> String {
        let cacheKey = "\(hash):\(file)"
        if let cached = diffCache[cacheKey] {
            return cached.result // commit diffs are immutable, no TTL needed
        }
        let result = runGit(["show", "--format=", hash, "--", file]) ?? ""
        diffCache[cacheKey] = (result, Date())
        return result
    }

    func githubURLForCommit(_ hash: String) -> URL? {
        guard let remoteURL = runGit(["remote", "get-url", "origin"]) else { return nil }
        let webURL: String
        if remoteURL.hasPrefix("git@github.com:") {
            let repoPath = remoteURL
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            webURL = "https://github.com/\(repoPath)"
        } else if remoteURL.contains("github.com") {
            webURL = remoteURL.replacingOccurrences(of: ".git", with: "")
        } else {
            return nil
        }
        return URL(string: "\(webURL)/commit/\(hash)")
    }

    func revertCommit(_ hash: String) async throws {
        markActive()
        let result = try await runGitAsync(["revert", "--no-edit", hash])
        if result.contains("error") || result.contains("CONFLICT") {
            throw GitError.commandFailed(result)
        }
        await MainActor.run { refresh() }
    }

    func cherryPickCommit(_ hash: String, onto branch: String) async throws {
        markActive()
        let originalBranch = currentBranch
        let _ = try await runGitAsync(["checkout", branch])
        do {
            let result = try await runGitAsync(["cherry-pick", hash])
            if result.contains("CONFLICT") {
                _ = try? await runGitAsync(["cherry-pick", "--abort"])
                _ = try? await runGitAsync(["checkout", originalBranch])
                throw GitError.mergeConflict
            }
        } catch {
            _ = try? await runGitAsync(["checkout", originalBranch])
            throw error
        }
        _ = try? await runGitAsync(["checkout", originalBranch])
        await MainActor.run { refresh() }
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
