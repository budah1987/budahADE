import SwiftUI

// MARK: - Changes Toolbar

/// Attached to the builder content area.
/// Shows unstaged file count + diff stats. Tap opens git panel.
struct ChangesToolbar: View {
    let worktreePath: String
    var onTap: () -> Void

    @State private var changeCount: Int = 0
    @State private var insertions: Int = 0
    @State private var deletions: Int = 0
    @State private var pollTimer: Timer?

    var body: some View {
        if changeCount > 0 {
            VStack(spacing: 0) {
                Divider().opacity(0.3)

                HStack(spacing: 8) {
                    Text("CHANGES")
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.textMuted)
                        .tracking(0.5)

                    // Count badge
                    Text("\(changeCount)")
                        .font(Theme.code(10, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    // Diff stats
                    if insertions > 0 {
                        Text("+\(insertions)")
                            .font(Theme.code(10))
                            .foregroundStyle(Theme.success)
                    }
                    if deletions > 0 {
                        Text("-\(deletions)")
                            .font(Theme.code(10))
                            .foregroundStyle(Theme.error)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Theme.sidebar)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
            }
        }
    }

    // MARK: - Git Status Polling

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                await refreshGitStatus()
            }
        }
        Task { @MainActor in
            await refreshGitStatus()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @MainActor
    private func refreshGitStatus() async {
        let result = await GitStatusFetcher.fetch(in: worktreePath)
        changeCount = result.changedFiles
        insertions = result.insertions
        deletions = result.deletions
    }
}

// MARK: - Git Status Fetcher

enum GitStatusFetcher {
    struct Result {
        let changedFiles: Int
        let insertions: Int
        let deletions: Int
    }

    static func fetch(in directory: String) async -> Result {
        // git status --porcelain for file count
        let fileCount = await runGitCommand(["status", "--porcelain"], in: directory)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .count

        // git diff --stat for insertions/deletions
        let diffStat = await runGitCommand(["diff", "--shortstat"], in: directory)
        let (ins, dels) = parseDiffStat(diffStat)

        return Result(changedFiles: fileCount, insertions: ins, deletions: dels)
    }

    private static func parseDiffStat(_ output: String) -> (insertions: Int, deletions: Int) {
        var insertions = 0
        var deletions = 0

        if let match = output.range(of: #"(\d+) insertion"#, options: .regularExpression) {
            let numStr = output[match].components(separatedBy: " ").first ?? "0"
            insertions = Int(numStr) ?? 0
        }
        if let match = output.range(of: #"(\d+) deletion"#, options: .regularExpression) {
            let numStr = output[match].components(separatedBy: " ").first ?? "0"
            deletions = Int(numStr) ?? 0
        }

        return (insertions, deletions)
    }

    private static func runGitCommand(_ args: [String], in directory: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory] + args
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
