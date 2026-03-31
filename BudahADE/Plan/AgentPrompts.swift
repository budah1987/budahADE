import Foundation

enum AgentPrompts {

    /// Build the full `claude` launch command for an agent mode
    static func launchCommand(
        agent: AgentMode,
        taskName: String,
        branchName: String,
        worktreePath: String,
        panelId: UUID? = nil,
        specFilePath: String? = nil,
        specProgress: (completed: Int, total: Int)? = nil
    ) -> String {
        var prompt = systemPrompt(
            agent: agent,
            taskName: taskName,
            branchName: branchName,
            specFilePath: specFilePath,
            specProgress: specProgress
        )

        // Add output capture instructions if we have a panel ID
        if let panelId {
            prompt += agentOutputInstructions(panelId: panelId)
        }

        // Write prompt to temp file, pass via cat to avoid shell escaping issues
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )

        // Also create the agent-output directory
        let outputDir = (worktreePath as NSString).appendingPathComponent(".budahade/agent-output")
        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true
        )

        let filename = ".budahade/\(agent.rawValue)-prompt.md"
        let path = (worktreePath as NSString).appendingPathComponent(filename)
        try? prompt.write(toFile: path, atomically: true, encoding: .utf8)

        return "claude --system-prompt \"$(cat '\(path)')\""
    }

    /// Build a launch command for a builder agent (spec execution focused)
    static func builderLaunchCommand(
        taskName: String,
        branchName: String,
        worktreePath: String,
        specFilePath: String,
        specProgress: (completed: Int, total: Int)
    ) -> String {
        let prompt = builderPrompt(
            taskName: taskName,
            branchName: branchName,
            specFilePath: specFilePath,
            specProgress: specProgress
        )

        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/builder-prompt.md")
        try? prompt.write(toFile: path, atomically: true, encoding: .utf8)

        return "claude --system-prompt \"$(cat '\(path)')\""
    }

    // MARK: - Prompts

    static func systemPrompt(
        agent: AgentMode,
        taskName: String,
        branchName: String,
        specFilePath: String? = nil,
        specProgress: (completed: Int, total: Int)? = nil
    ) -> String {
        let context = """
        You are helping with task "\(taskName)" on branch "\(branchName)".
        """

        let specBlock = specInstructions(filePath: specFilePath, progress: specProgress)
        let verificationBlock = SelfVerification.verificationGuidance(for: agent)

        switch agent {
        case .claude:
            return """
            \(context)
            \(verificationBlock)
            \(specBlock)
            """

        case .researcher:
            return """
            \(context)
            You are a Research Expert. Produce structured research reports with clear analysis, sources, and conclusions. Investigate thoroughly but present findings cleanly — use headings, bullet points, and citations. When fed files or data, synthesize into actionable insights. When asked to look at the codebase, use Read/Glob/Grep as needed.
            \(specBlock)
            """

        case .ideator:
            return """
            \(context)
            You are an Ideation Partner and strategic thinker. Help the user get ideas out of their head. Ask incisive questions. Challenge assumptions. Propose 2-3 options with trade-offs. Read project files for context when relevant — understand the codebase and project state to give informed ideas. Focus on ideas and direction, not implementation details.
            \(specBlock)
            """

        case .developer:
            return """
            \(context)
            You are a Senior Architect & Developer. Assess feasibility, suggest architecture, identify risks and dependencies. When asked, write code that is simple, efficient, and follows existing codebase patterns — code that would impress a human engineer. Reference file paths and line numbers. Think about performance, maintainability, and incremental delivery.
            \(verificationBlock)
            \(specBlock)
            """

        case .designer:
            return """
            \(context)
            You are a UI/UX Designer. Focus on user experience, component structure, interaction patterns, visual hierarchy, and accessibility. When analyzing code, evaluate from the user's perspective — what's intuitive, what's confusing, what's missing. Present design decisions as options with trade-offs. Be opinionated — recommend the better option and explain why.
            \(specBlock)
            """

        case .specAuthor:
            return """
            \(context)
            You are a Spec Author — your job is to synthesize findings from planning conversations into a clear, actionable specification document.

            Your workflow:
            1. Review the context from sibling conversations (research findings, design decisions, architectural proposals)
            2. Present the spec ONE SECTION AT A TIME for user review
            3. For each section, ask "Does this look right?" before moving to the next
            4. Once all sections are approved, assemble the full document
            5. Present the complete spec for final review

            Spec format: Problem statement, goals, architecture, components, data flow, edge cases, implementation checklist.
            Be concise. Every sentence should earn its place.
            \(verificationBlock)
            \(specBlock)
            """
        }
    }

    static func chatSystemPrompt(
        agent: AgentMode,
        taskName: String,
        branchName: String,
        specFilePath: String? = nil,
        specProgress: (completed: Int, total: Int)? = nil
    ) -> String {
        systemPrompt(
            agent: agent,
            taskName: taskName,
            branchName: branchName,
            specFilePath: specFilePath,
            specProgress: specProgress
        )
    }

    /// Execution-focused prompt for builder agents
    private static func builderPrompt(
        taskName: String,
        branchName: String,
        specFilePath: String,
        specProgress: (completed: Int, total: Int)
    ) -> String {
        return """
        You are a Builder executing task "\(taskName)" on branch "\(branchName)".
        Your job is to implement the spec, one task at a time.

        ## Active Spec
        A spec file exists at `\(specFilePath)`. Read it now.
        Each `- [ ]` item is a task to complete. Work on the next unchecked item.
        When you complete a task, update the spec file: change `- [ ]` to `- [x]` for that item.
        Then proceed to the next unchecked item.
        Do not skip items. Do not reorder items. If you are blocked on a task, say so.
        Current progress: \(specProgress.completed)/\(specProgress.total) tasks complete.

        ## Status Reporting
        After starting each task, update `.budahade/build-status.json` with your current status:
        ```json
        {
          "currentTask": "The task title you are working on",
          "taskIndex": 0,
          "status": "working",
          "lastAction": "Brief description of what you just did",
          "blockers": null
        }
        ```
        Valid status values: "working", "blocked", "completed".
        When blocked, set status to "blocked" and describe the blocker in the blockers field.
        When you finish ALL tasks, set status to "completed".
        Update this file whenever your status changes significantly.

        ## Guidelines
        - Read the full spec before starting to understand the overall scope.
        - Focus on one task at a time. Complete it fully before moving on.
        - After marking a task complete, briefly state what you did.
        - If a task is ambiguous, make a reasonable choice and note your assumption.
        """
    }

    // MARK: - Agent Output Capture

    private static func agentOutputInstructions(panelId: UUID) -> String {
        return """

        ## Output Capture
        When you have a substantive finding, conclusion, or recommendation, also write it to
        `.budahade/agent-output/\(panelId.uuidString).md` as structured markdown.
        This allows your output to be collected into the spec document.
        """
    }

    // MARK: - Spec Instructions Block

    private static func specInstructions(
        filePath: String?,
        progress: (completed: Int, total: Int)?
    ) -> String {
        guard let path = filePath else { return "" }

        let progressLine: String
        if let p = progress {
            progressLine = "Current progress: \(p.completed)/\(p.total) tasks complete."
        } else {
            progressLine = ""
        }

        return """

        ## Active Spec
        A spec file exists at `\(path)`. Read it for context.
        Each `- [ ]` item is a task. When you complete a task, update the file: change `- [ ]` to `- [x]`.
        \(progressLine)
        """
    }

    // MARK: - Build Context Injection

    /// Reads spec progress and agent output from the worktree's .budahade directory
    /// and returns a formatted markdown block, or empty string if nothing exists.
    static func buildContextBlock(worktreePath: String) -> String {
        let fm = FileManager.default
        var sections: [String] = []

        // --- Spec progress (counts only — agent can read the file for details) ---
        let specPath = (worktreePath as NSString)
            .appendingPathComponent(".budahade/spec.md")
        if let specContent = try? String(contentsOfFile: specPath, encoding: .utf8) {
            let lines = specContent.components(separatedBy: "\n")
            let completed = lines.filter { $0.contains("- [x]") || $0.contains("- [X]") }
            let remaining = lines.filter { $0.contains("- [ ]") }
            let total = completed.count + remaining.count
            if total > 0 {
                var specSection = "### Spec Progress\n"
                specSection += "\(completed.count) of \(total) tasks completed.\n"
                specSection += "Read `.budahade/spec.md` for full task details."
                sections.append(specSection)
            }
        }

        // --- Agent output (truncated to last 500 chars each for efficiency) ---
        let agentOutputDir = (worktreePath as NSString)
            .appendingPathComponent(".budahade/agent-output")
        if let files = try? fm.contentsOfDirectory(atPath: agentOutputDir) {
            let mdFiles = files.filter { $0.hasSuffix(".md") }.sorted()
            var outputParts: [String] = []
            let maxCharsPerFile = 500
            let maxTotalChars = 3000
            var totalChars = 0
            for filename in mdFiles {
                guard totalChars < maxTotalChars else { break }
                let filePath = (agentOutputDir as NSString).appendingPathComponent(filename)
                if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    // Take the tail (conclusion) of each file
                    let truncated = trimmed.count > maxCharsPerFile
                        ? "…" + String(trimmed.suffix(maxCharsPerFile))
                        : trimmed
                    outputParts.append(truncated)
                    totalChars += truncated.count
                }
            }
            if !outputParts.isEmpty {
                sections.append("### Agent Output (summaries)\n" + outputParts.joined(separator: "\n\n---\n\n"))
            }
        }

        guard !sections.isEmpty else { return "" }
        return "\n## Build Progress\n\n" + sections.joined(separator: "\n\n")
    }

    // MARK: - Sibling Context Injection

    /// Build a context block from sibling conversations to inject into system prompt.
    /// Prefers cached Haiku summaries when available, falls back to truncated raw messages.
    static func siblingContextBlock(from siblings: [ConversationSnapshot], worktreePath: String? = nil) -> String {
        guard !siblings.isEmpty else { return "" }

        // Prefer cached Haiku summaries if available (generated by SiblingSummarizer)
        if let path = worktreePath {
            let cachePath = (path as NSString).appendingPathComponent(".budahade/sibling-summaries.md")
            if let cached = try? String(contentsOfFile: cachePath, encoding: .utf8),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cached
            }
        }

        // Fallback: truncated raw messages
        let maxCharsPerSibling = 2000
        let maxTotalChars = 4000
        var totalChars = 0

        var block = "\n## Context from other planning conversations\n"

        for sibling in siblings {
            guard totalChars < maxTotalChars else { break }

            // Only include the last 3 assistant messages (skip user prompts — they're noise)
            let assistantMessages = sibling.messages
                .filter { $0.role == .assistant && !$0.content.isEmpty }
                .suffix(3)

            guard !assistantMessages.isEmpty else { continue }

            var siblingBlock = "\n### \(sibling.role.displayName)\n"
            var siblingChars = 0

            for message in assistantMessages {
                let remaining = min(maxCharsPerSibling - siblingChars, maxTotalChars - totalChars)
                guard remaining > 0 else { break }

                let content = message.content
                let truncated = content.count > remaining
                    ? String(content.prefix(remaining)) + "…"
                    : content
                siblingBlock += "\(truncated)\n\n"
                siblingChars += truncated.count
                totalChars += truncated.count
            }

            block += siblingBlock
        }

        return block
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
