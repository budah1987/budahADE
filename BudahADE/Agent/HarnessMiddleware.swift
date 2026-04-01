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
    /// If a spec exists, includes unchecked items for targeted verification.
    static func verificationPrompt(taskName: String, role: AgentMode?, worktreePath: String? = nil) -> String? {
        // Only auto-verify roles that produce runnable artifacts (code)
        guard let role = role else { return nil }
        switch role {
        case .developer, .claude:
            break
        default:
            return nil  // Researcher, ideator, designer, specAuthor don't need artifact verification
        }

        var prompt = """
        VERIFICATION PASS — Before finishing, verify your work:
        1. Re-read the original task: "\(taskName)"
        2. Run any tests or build commands to confirm the code works
        3. Compare your output against what was asked — not against your own code
        4. Check edge cases: empty inputs, error paths, boundary conditions
        5. If you find issues, fix them now. If everything passes, confirm completion.
        Do NOT just re-read your code and say it looks good. Actually run it.
        """

        // Spec-aware: inject unchecked items so verification is targeted
        if let path = worktreePath {
            let specItems = uncheckedSpecItems(worktreePath: path)
            if !specItems.isEmpty {
                prompt += "\n\nVerify these specific spec requirements are met:\n"
                for item in specItems {
                    prompt += "- \(item)\n"
                }
            }
        }

        return prompt
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

    /// Reads unchecked items from the spec file for targeted verification
    private static func uncheckedSpecItems(worktreePath: String) -> [String] {
        let specPath = (worktreePath as NSString).appendingPathComponent(".budahade/spec.md")
        guard let content = try? String(contentsOfFile: specPath, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n")
            .filter { $0.contains("- [ ]") }
            .map { $0.trimmingCharacters(in: .whitespaces)
                     .replacingOccurrences(of: "- [ ] ", with: "") }
            .prefix(10)
            .map { String($0) }
    }
}

// MARK: - Reasoning Sandwich

/// Manages model switching per phase within a session.
/// Planning → high reasoning (Opus), Implementation → fast (Sonnet), Verification → high reasoning (Opus).
enum ReasoningSandwich {

    enum Phase {
        case planning       // First turn — understanding + planning
        case implementation // Middle turns — writing code
        case verification   // Final turn — checking work
    }

    /// Determines the current phase based on turn count and verification state
    static func currentPhase(turnCount: Int, hasVerified: Bool, maxTurns: Int?) -> Phase {
        if hasVerified { return .verification }
        if turnCount <= 1 { return .planning }
        return .implementation
    }

    /// Returns the recommended model for the current phase, given the role's default
    static func modelForPhase(_ phase: Phase, role: AgentMode?, defaultModel: AgentModel) -> AgentModel {
        // Only apply sandwich to roles that benefit from it
        guard let role = role else { return defaultModel }
        switch role {
        case .developer, .claude:
            break
        default:
            return defaultModel
        }

        switch phase {
        case .planning:
            return .opus       // High reasoning for understanding the problem
        case .implementation:
            return defaultModel // Use whatever the user/role selected (usually Sonnet)
        case .verification:
            return .opus       // High reasoning for catching mistakes
        }
    }
}

// MARK: - Turn Budget Warnings

/// Injects warnings when approaching the max turn limit so agents prioritize finishing.
enum TurnBudget {

    /// Returns a warning string if the agent is close to running out of turns, nil otherwise.
    static func warningIfNeeded(currentTurn: Int, maxTurns: Int?) -> String? {
        guard let max = maxTurns, max > 3 else { return nil }
        let remaining = max - currentTurn

        if remaining == 3 {
            return "[Turn Budget] You have 3 turns remaining. Prioritize finishing and verifying over starting new work."
        } else if remaining == 1 {
            return "[Turn Budget] LAST TURN. Submit your final, verified solution now."
        }
        return nil
    }
}

// MARK: - Failure Memory

/// Persists and loads lessons learned from agent failures across sessions.
/// Stored in `.budahade/failures.md` per worktree.
enum FailureMemory {

    /// Records a failure/lesson learned to persistent storage
    static func record(lesson: String, worktreePath: String) {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("[FailureMemory] ⚠️ Failed to create .budahade directory: \(error)")
        }
        let path = (dir as NSString).appendingPathComponent("failures.md")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "- [\(timestamp)] \(lesson)\n"

        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            do {
                try ("# Lessons Learned\n\n" + entry).write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                print("[FailureMemory] ⚠️ Failed to create failure log: \(error)")
            }
        }
    }

    /// Records a loop detection event as a failure lesson
    static func recordLoopDetected(file: String, editCount: Int, worktreePath: String) {
        record(
            lesson: "Doom loop on `\(file)` (\(editCount) edits). Consider a fundamentally different approach next time.",
            worktreePath: worktreePath
        )
    }

    /// Loads failure lessons for injection into system prompt.
    /// Returns empty string if no lessons exist.
    static func contextBlock(worktreePath: String) -> String {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/failures.md")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Only include the last 10 lessons to avoid bloat
        let lines = trimmed.components(separatedBy: "\n")
            .filter { $0.hasPrefix("- [") }
            .suffix(10)

        guard !lines.isEmpty else { return "" }

        var block = "\n## Lessons from Previous Attempts\n"
        block += "Avoid repeating these mistakes:\n"
        for line in lines {
            block += "\(line)\n"
        }
        return block
    }
}

// MARK: - Cost Tracking

/// Persists per-task cost data to `.budahade/cost-log.json` for analysis.
enum CostTracker {

    struct CostEntry: Codable {
        let timestamp: String
        let taskName: String
        let role: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let costUSD: Double
        let durationMs: Int?
        let numTurns: Int?
    }

    /// Records a completed session's cost to the persistent log
    static func record(
        taskName: String,
        role: AgentMode?,
        model: AgentModel,
        result: StreamEvent.ResultInfo,
        worktreePath: String
    ) {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("[CostTracker] ⚠️ Failed to create .budahade directory: \(error)")
        }
        let path = (dir as NSString).appendingPathComponent("cost-log.json")

        let entry = CostEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            taskName: taskName,
            role: role?.rawValue ?? "unknown",
            model: model.rawValue,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            costUSD: result.costUSD,
            durationMs: result.durationMs,
            numTurns: result.numTurns
        )

        // Load existing entries, append, and write back
        var entries: [CostEntry] = []
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONDecoder().decode([CostEntry].self, from: data) {
            entries = existing
        }
        entries.append(entry)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                print("[CostTracker] ⚠️ Failed to save cost log: \(error)")
            }
        }
    }

    /// Returns a summary of total cost for the current task
    static func summary(worktreePath: String) -> (totalCost: Double, totalTokens: Int, entryCount: Int) {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/cost-log.json")
        guard let data = FileManager.default.contents(atPath: path),
              let entries = try? JSONDecoder().decode([CostEntry].self, from: data) else {
            return (0, 0, 0)
        }
        let totalCost = entries.reduce(0) { $0 + $1.costUSD }
        let totalTokens = entries.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        return (totalCost, totalTokens, entries.count)
    }
}

// MARK: - Tool Escalation

/// Detects when an agent tries to use a tool it doesn't have access to,
/// and surfaces it as a pending escalation request for the UI to display.
@MainActor
final class ToolEscalationManager: ObservableObject {

    struct EscalationRequest: Identifiable, Equatable {
        let id: UUID
        let toolName: String
        let reason: String
        let timestamp: Date
        var granted: Bool = false
    }

    @Published var pendingRequests: [EscalationRequest] = []

    /// Known tool error patterns that indicate a permission issue
    private static let deniedPatterns = [
        "not allowed",
        "not in allowedTools",
        "tool is not available",
        "permission denied",
    ]

    /// Check a tool result for signs of a denied tool request
    func checkForEscalation(toolName: String, result: ToolResultEvent) {
        guard result.isError else { return }
        let lowered = result.content.lowercased()
        let isDenied = Self.deniedPatterns.contains { lowered.contains($0) }
        guard isDenied else { return }

        // Don't duplicate requests for the same tool
        guard !pendingRequests.contains(where: { $0.toolName == toolName && !$0.granted }) else { return }

        let request = EscalationRequest(
            id: UUID(),
            toolName: toolName,
            reason: String(result.content.prefix(200)),
            timestamp: Date()
        )
        pendingRequests.append(request)
    }

    /// Grant a tool escalation — returns the updated allowed tools list
    func grant(requestId: UUID, currentTools: [String]?) -> [String]? {
        guard let idx = pendingRequests.firstIndex(where: { $0.id == requestId }) else {
            return currentTools
        }
        pendingRequests[idx].granted = true
        let toolName = pendingRequests[idx].toolName

        // Add the tool to the allowed list
        if var tools = currentTools {
            if !tools.contains(toolName) {
                tools.append(toolName)
            }
            return tools
        }
        return nil // Already unrestricted
    }

    func dismiss(requestId: UUID) {
        pendingRequests.removeAll { $0.id == requestId }
    }
}

// MARK: - Spec Diff Verification

/// Generates a structural verification by comparing modified files against spec requirements.
enum SpecDiffVerification {

    /// Builds a verification prompt that diffs git changes against unchecked spec items.
    static func diffPrompt(worktreePath: String) -> String? {
        let specItems = uncheckedSpecItems(worktreePath: worktreePath)
        guard !specItems.isEmpty else { return nil }

        let modifiedFiles = gitModifiedFiles(worktreePath: worktreePath)
        guard !modifiedFiles.isEmpty else { return nil }

        var prompt = """
        STRUCTURAL VERIFICATION — Compare your changes against the spec:

        Files you modified:
        """
        for file in modifiedFiles.prefix(20) {
            prompt += "\n- `\(file)`"
        }

        prompt += "\n\nUnchecked spec requirements:\n"
        for item in specItems {
            prompt += "- \(item)\n"
        }

        prompt += """

        For each spec requirement:
        1. Which modified file(s) address it?
        2. Is the requirement fully satisfied, or only partially?
        3. Are there requirements that NO modified file addresses? If so, they may be missing.
        4. Are there modified files that don't map to any requirement? Explain why they were changed.
        Fix any gaps you find.
        """

        return prompt
    }

    private static func uncheckedSpecItems(worktreePath: String) -> [String] {
        let specPath = (worktreePath as NSString).appendingPathComponent(".budahade/spec.md")
        guard let content = try? String(contentsOfFile: specPath, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n")
            .filter { $0.contains("- [ ]") }
            .map { $0.trimmingCharacters(in: .whitespaces)
                     .replacingOccurrences(of: "- [ ] ", with: "") }
            .prefix(15)
            .map { String($0) }
    }

    private static func gitModifiedFiles(worktreePath: String) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "cd '\(worktreePath)' && git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached HEAD 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let files = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            // Deduplicate
            return Array(Set(files)).sorted()
        } catch {
            return []
        }
    }
}

// MARK: - Trace Analysis

/// Cross-session trace analysis: persists conversation traces and generates
/// analysis prompts to find systemic failure patterns across multiple task completions.
enum TraceAnalysis {

    struct TraceEntry: Codable {
        let timestamp: String
        let taskName: String
        let role: String
        let model: String
        let turnCount: Int
        let inputTokens: Int
        let outputTokens: Int
        let costUSD: Double
        let loopDetections: [String]    // Files that triggered loop warnings
        let toolErrors: [String]        // Tool names that errored
        let verified: Bool              // Whether verification pass ran
        let outcome: String             // "completed", "error", "timeout"
    }

    /// Records a completed session trace for later analysis
    @MainActor static func recordTrace(
        taskName: String,
        session: AgentSession,
        result: StreamEvent.ResultInfo,
        worktreePath: String
    ) {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("[TraceLog] ⚠️ Failed to create .budahade directory: \(error)")
        }
        let path = (dir as NSString).appendingPathComponent("traces.json")

        let loopFiles = session.loopDetector.fileEditCounts
            .filter { $0.value >= session.loopDetector.warningThreshold }
            .map { $0.key }

        let toolErrors = session.activityFeed
            .filter { $0.status == .failed }
            .map { entry -> String in
                switch entry.kind {
                case .toolBash(let cmd): return "Bash: \(String(cmd.prefix(50)))"
                case .toolEdit(let path): return "Edit: \(path)"
                case .toolWrite(let path): return "Write: \(path)"
                case .toolOther(let name): return name
                default: return entry.label
                }
            }

        let outcome: String
        if result.stopReason == "max_turns" {
            outcome = "timeout"
        } else if case .error = session.status {
            outcome = "error"
        } else {
            outcome = "completed"
        }

        let entry = TraceEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            taskName: taskName,
            role: session.agentMode?.rawValue ?? "unknown",
            model: session.model.rawValue,
            turnCount: result.numTurns ?? session.messages.filter { $0.role == .user }.count,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            costUSD: result.costUSD,
            loopDetections: loopFiles,
            toolErrors: toolErrors,
            verified: session.hasVerified,
            outcome: outcome
        )

        var entries: [TraceEntry] = []
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONDecoder().decode([TraceEntry].self, from: data) {
            entries = existing
        }
        entries.append(entry)

        // Keep last 50 traces to avoid unbounded growth
        if entries.count > 50 {
            entries = Array(entries.suffix(50))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                print("[TraceLog] ⚠️ Failed to save traces: \(error)")
            }
        }
    }

    /// Generates an analysis prompt from accumulated traces for pattern detection
    static func analysisPrompt(worktreePath: String) -> String? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/traces.json")
        guard let data = FileManager.default.contents(atPath: path),
              let entries = try? JSONDecoder().decode([TraceEntry].self, from: data),
              entries.count >= 3 else {
            return nil  // Need at least 3 traces for meaningful analysis
        }

        var prompt = """
        Analyze these \(entries.count) agent session traces and identify systemic patterns:

        """

        for (i, entry) in entries.enumerated() {
            prompt += """
            ### Trace \(i + 1): \(entry.taskName) (\(entry.role), \(entry.model))
            - Outcome: \(entry.outcome) | Turns: \(entry.turnCount) | Cost: $\(String(format: "%.4f", entry.costUSD))
            - Tokens: \(entry.inputTokens) in / \(entry.outputTokens) out
            - Verified: \(entry.verified) | Loop detections: \(entry.loopDetections.joined(separator: ", ").isEmpty ? "none" : entry.loopDetections.joined(separator: ", "))
            - Tool errors: \(entry.toolErrors.joined(separator: ", ").isEmpty ? "none" : entry.toolErrors.joined(separator: ", "))

            """
        }

        prompt += """
        Identify:
        1. Which roles/models have the highest failure rates?
        2. Are there common tool errors that suggest missing capabilities?
        3. Which tasks trigger loop detections? What do they have in common?
        4. Are sessions that run verification more likely to succeed?
        5. What's the cost efficiency (cost per successful completion)?
        6. Concrete recommendations to improve the harness (system prompts, tool access, turn limits).
        """

        return prompt
    }
}

// MARK: - Sibling Summary (Haiku-powered)

/// Generates concise Haiku summaries of sibling conversations instead of raw truncation.
enum SiblingSummarizer {

    /// Summarizes a sibling conversation's assistant messages using Haiku.
    /// Falls back to truncation if Haiku is unavailable.
    static func summarize(snapshot: ConversationSnapshot) async -> String {
        let assistantText = snapshot.messages
            .filter { $0.role == .assistant && !$0.content.isEmpty }
            .suffix(5)
            .map { $0.content }
            .joined(separator: "\n\n")

        guard !assistantText.isEmpty else { return "" }

        let truncated = String(assistantText.prefix(3000))
        let prompt = """
        Summarize this \(snapshot.role.displayName) agent's findings in 2-3 sentences for a developer. \
        Focus on decisions made, key findings, and actionable conclusions:\n\n\(truncated)
        """

        return await runHaikuSummary(prompt: prompt)
    }

    /// Summarizes all siblings in parallel and returns a formatted context block.
    static func summarizeAll(_ siblings: [ConversationSnapshot]) async -> String {
        guard !siblings.isEmpty else { return "" }

        let summaries = await withTaskGroup(of: (AgentMode, String).self) { group in
            for sibling in siblings {
                group.addTask {
                    let summary = await summarize(snapshot: sibling)
                    return (sibling.role, summary)
                }
            }
            var results: [(AgentMode, String)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let nonEmpty = summaries.filter { !$0.1.isEmpty }
        guard !nonEmpty.isEmpty else { return "" }

        var block = "\n## Context from other planning conversations\n"
        for (role, summary) in nonEmpty {
            block += "\n### \(role.displayName)\n\(summary)\n"
        }
        return block
    }

    private static nonisolated func runHaikuSummary(prompt: String) async -> String {
        let claudeBin = CLISubprocessManager.claudePath
        let process = Process()
        if claudeBin == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "-p", prompt, "--model", "haiku", "--max-turns", "1"]
        } else {
            process.executableURL = URL(fileURLWithPath: claudeBin)
            process.arguments = ["-p", prompt, "--model", "haiku", "--max-turns", "1"]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Fallback to truncation if Haiku fails
            return output.isEmpty ? String(prompt.prefix(200)) : output
        } catch {
            return String(prompt.prefix(200))
        }
    }
}
