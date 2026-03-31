import Foundation

// MARK: - Environment Context Discovery

/// Discovers working directory structure and available tooling on session start.
/// Injects this as context so agents don't waste turns on environment discovery.
enum EnvironmentContext {

    /// Runs discovery commands and returns a formatted context block for system prompt injection.
    static func discover(workingDirectory: String) -> String {
        let fm = FileManager.default
        var sections: [String] = []

        // --- Directory structure (top 2 levels, max 40 entries) ---
        let tree = directoryTree(at: workingDirectory, maxDepth: 2, maxEntries: 40)
        if !tree.isEmpty {
            sections.append("### Directory Structure\n```\n\(tree)\n```")
        }

        // --- Key files detection ---
        var keyFiles: [String] = []
        let markers: [(String, String)] = [
            ("Package.swift", "Swift Package"),
            ("project.yml", "XcodeGen project"),
            ("Podfile", "CocoaPods"),
            ("package.json", "Node.js"),
            ("Cargo.toml", "Rust"),
            ("pyproject.toml", "Python"),
            ("requirements.txt", "Python"),
            ("go.mod", "Go"),
            ("Makefile", "Make"),
            ("Dockerfile", "Docker"),
            (".github/workflows", "GitHub Actions"),
            ("tsconfig.json", "TypeScript"),
        ]
        for (file, label) in markers {
            let path = (workingDirectory as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: path) {
                keyFiles.append("- \(label) (`\(file)`)")
            }
        }
        if !keyFiles.isEmpty {
            sections.append("### Detected Tooling\n" + keyFiles.joined(separator: "\n"))
        }

        // --- Git branch ---
        if let branch = shellOutput("git -C '\(workingDirectory)' branch --show-current") {
            sections.append("### Git\nCurrent branch: `\(branch)`")
        }

        guard !sections.isEmpty else { return "" }
        return "\n## Environment\n\n" + sections.joined(separator: "\n\n")
    }

    // MARK: - Private Helpers

    private static func directoryTree(at path: String, maxDepth: Int, maxEntries: Int) -> String {
        let fm = FileManager.default
        var lines: [String] = []
        let rootName = (path as NSString).lastPathComponent
        lines.append(rootName + "/")
        collectEntries(at: path, prefix: "", depth: 0, maxDepth: maxDepth, maxEntries: &lines, limit: maxEntries, fm: fm)
        return lines.joined(separator: "\n")
    }

    private static func collectEntries(
        at path: String, prefix: String, depth: Int, maxDepth: Int,
        maxEntries: inout [String], limit: Int, fm: FileManager
    ) {
        guard depth < maxDepth, maxEntries.count < limit else { return }

        guard let contents = try? fm.contentsOfDirectory(atPath: path).sorted() else { return }

        // Filter out hidden files, build artifacts, and dependency dirs
        let skip: Set<String> = [
            ".git", ".build", "node_modules", "Pods", ".budahade",
            "DerivedData", ".swiftpm", "__pycache__", ".DS_Store",
            "target", "dist", "build",
        ]
        let filtered = contents.filter { !skip.contains($0) && !$0.hasPrefix(".") }

        for (i, entry) in filtered.enumerated() {
            guard maxEntries.count < limit else { return }
            let fullPath = (path as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            let isLast = (i == filtered.count - 1)
            let connector = isLast ? "└── " : "├── "
            let childPrefix = isLast ? "    " : "│   "
            let suffix = isDir.boolValue ? "/" : ""

            maxEntries.append(prefix + connector + entry + suffix)

            if isDir.boolValue {
                collectEntries(
                    at: fullPath, prefix: prefix + childPrefix,
                    depth: depth + 1, maxDepth: maxDepth,
                    maxEntries: &maxEntries, limit: limit, fm: fm
                )
            }
        }
    }

    private static func shellOutput(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }
}

// MARK: - Loop Detection

/// Tracks per-file edit counts and detects doom loops where an agent repeatedly edits the same file.
@MainActor
final class LoopDetector {
    /// File path → number of edits in this session
    private(set) var fileEditCounts: [String: Int] = [:]

    /// Threshold before we warn the agent
    let warningThreshold: Int

    /// Files that have already triggered a warning (to avoid spamming)
    private var warnedFiles: Set<String> = []

    init(warningThreshold: Int = 5) {
        self.warningThreshold = warningThreshold
    }

    /// Record an edit to a file. Returns a warning message if threshold exceeded, nil otherwise.
    func recordEdit(filePath: String) -> String? {
        let normalized = (filePath as NSString).lastPathComponent
        fileEditCounts[normalized, default: 0] += 1
        let count = fileEditCounts[normalized]!

        if count >= warningThreshold && !warnedFiles.contains(normalized) {
            warnedFiles.insert(normalized)
            return buildWarning(file: normalized, count: count)
        }

        // Re-warn at 2x threshold if still going
        if count >= warningThreshold * 2 && count.isMultiple(of: warningThreshold) {
            return buildWarning(file: normalized, count: count)
        }

        return nil
    }

    /// Extract file path from a tool use event if it's an Edit or Write operation
    func filePathFromToolEvent(_ event: ToolUseEvent) -> String? {
        guard event.name == "Edit" || event.name == "Write" else { return nil }
        guard let data = event.inputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = obj["file_path"] as? String else { return nil }
        return path
    }

    func reset() {
        fileEditCounts.removeAll()
        warnedFiles.removeAll()
    }

    private func buildWarning(file: String, count: Int) -> String {
        return """
        [Loop Detection] You have edited `\(file)` \(count) times this session. \
        This may indicate a doom loop. Step back and reconsider your approach: \
        Is there a fundamentally different solution? Are you fixing symptoms instead of the root cause? \
        Consider re-reading the original task requirements before your next edit.
        """
    }
}

// MARK: - Self-Verification

/// Generates verification prompts that force agents to check their work against the task spec.
enum SelfVerification {

    /// Returns a verification prompt to send after the agent's initial completion.
    static func verificationPrompt(taskName: String, role: AgentMode?) -> String? {
        // Only auto-verify roles that produce artifacts (code, specs)
        guard let role = role else { return nil }
        switch role {
        case .developer, .specAuthor:
            break
        case .claude:
            // Claude mode gets verification too — it's unrestricted and does everything
            break
        default:
            return nil  // Researcher, ideator, designer don't need artifact verification
        }

        return """
        VERIFICATION PASS — Before finishing, verify your work:
        1. Re-read the original task: "\(taskName)"
        2. Run any tests or build commands to confirm the code works
        3. Compare your output against what was asked — not against your own code
        4. Check edge cases: empty inputs, error paths, boundary conditions
        5. If you find issues, fix them now. If everything passes, confirm completion.
        Do NOT just re-read your code and say it looks good. Actually run it.
        """
    }

    /// System prompt addition that encourages build-verify-fix loops
    static func verificationGuidance(for role: AgentMode) -> String {
        switch role {
        case .developer, .claude:
            return """

            ## Problem-Solving Approach
            Follow this workflow for every task:
            1. **Plan & Discover**: Read the task, scan the codebase, understand what success looks like and how to verify it.
            2. **Build**: Implement with verification in mind. Write tests if they don't exist — cover both happy paths and edge cases.
            3. **Verify**: Run tests, read the FULL output, compare against the original task spec (not your own code).
            4. **Fix**: If anything fails, analyze the error, revisit the spec, and fix. Repeat verify-fix until passing.
            Never stop after writing code. Always run it. A solution that hasn't been tested is not complete.
            """
        case .specAuthor:
            return """

            ## Verification
            Before finalizing the spec, verify:
            - Every requirement from the original task is addressed
            - The implementation checklist is complete and actionable
            - No ambiguous items — each task should have a clear "done" definition
            """
        default:
            return ""
        }
    }
}
