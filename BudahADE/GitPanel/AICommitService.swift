import Foundation

actor AICommitService {

    static let shared = AICommitService()

    private init() {}

    func generateMessage(repoPath: String) async -> String? {
        let diff = runGitSync(["diff", "--cached"], at: repoPath)
        guard let diff, !diff.isEmpty else { return nil }

        let truncatedDiff = String(diff.prefix(4000))

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
