import Foundation

/// Utility for managing git worktrees for task isolation.
enum GitWorktreeManager {

    // MARK: - Create

    /// Creates a new git worktree for a task branch.
    /// - Returns: Absolute path to the created worktree directory.
    @discardableResult
    static func createWorktree(
        repoPath: String,
        branchName: String,
        baseBranch: String = "main"
    ) async throws -> String {
        let worktreePath = worktreeDirectory(repoPath: repoPath, branchName: branchName)

        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            atPath: (worktreePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        // Clean up stale worktree directory if it exists
        if FileManager.default.fileExists(atPath: worktreePath) {
            // Prune stale worktree entries first, then remove directory
            _ = try? await runGit(args: ["worktree", "prune"], repoPath: repoPath)
            try? FileManager.default.removeItem(atPath: worktreePath)
        }

        // Try creating with new branch first; if branch already exists, just check it out
        do {
            try await runGit(
                args: ["worktree", "add", "-b", branchName, worktreePath, baseBranch],
                repoPath: repoPath
            )
        } catch {
            // Branch may already exist — try without -b
            try await runGit(
                args: ["worktree", "add", worktreePath, branchName],
                repoPath: repoPath
            )
        }

        return worktreePath
    }

    // MARK: - Remove

    static func removeWorktree(repoPath: String, worktreePath: String) async throws {
        try await runGit(
            args: ["worktree", "remove", worktreePath, "--force"],
            repoPath: repoPath
        )
        _ = try? await runGit(args: ["worktree", "prune"], repoPath: repoPath)
    }

    // MARK: - List

    static func listWorktrees(repoPath: String) async -> [(path: String, branch: String)] {
        guard let output = try? await runGit(args: ["worktree", "list", "--porcelain"], repoPath: repoPath) else {
            return []
        }

        var results: [(path: String, branch: String)] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                // refs/heads/main → main
                currentBranch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line.isEmpty {
                if let path = currentPath, let branch = currentBranch {
                    results.append((path: path, branch: branch))
                }
                currentPath = nil
                currentBranch = nil
            }
        }

        if let path = currentPath, let branch = currentBranch {
            results.append((path: path, branch: branch))
        }

        return results
    }

    // MARK: - Helpers

    static func worktreeDirectory(repoPath: String, branchName: String) -> String {
        let repoParent = (repoPath as NSString).deletingLastPathComponent
        let projectName = (repoPath as NSString).lastPathComponent
        let slug = branchName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        return "\(repoParent)/.budahade-worktrees/\(projectName)/\(slug)"
    }

    @discardableResult
    static func runGit(args: [String], repoPath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if process.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "git error"
                    continuation.resume(throwing: NSError(
                        domain: "GitWorktreeManager",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: errMsg.trimmingCharacters(in: .whitespacesAndNewlines)]
                    ))
                    return
                }

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }
        }
    }
}
