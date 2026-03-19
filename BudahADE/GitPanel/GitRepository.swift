import Foundation
import Combine

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

final class GitRepository: ObservableObject {
    let path: String

    @Published var currentBranch: String = ""
    @Published var branches: [String] = []
    @Published var stagedFiles: [GitFileStatus] = []
    @Published var unstagedFiles: [GitFileStatus] = []
    @Published var recentCommits: [GitCommit] = []

    private var pollTimer: Timer?

    init(path: String) {
        self.path = path
        refresh()
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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

    func diff(file: String, staged: Bool) -> String {
        var args = ["diff"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", file])
        return runGit(args) ?? ""
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
                // Ordinary or rename entry: "1 XY sub mH mI mW hH hI path"
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 9 else { continue }
                let xy = parts[1]
                let filePath: String
                if line.hasPrefix("2 ") {
                    // Rename entry has path\ttab\torigPath
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
                // Untracked file
                let filePath = String(line.dropFirst(2))
                unstaged.append(GitFileStatus(status: "?", path: filePath))
            }
        }

        self.stagedFiles = staged
        self.unstagedFiles = unstaged
    }

    func parseBranches() {
        // Current branch
        if let headOutput = runGit(["rev-parse", "--abbrev-ref", "HEAD"]) {
            currentBranch = headOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // All branches
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

    private func mapStatusChar(_ char: String) -> String {
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
