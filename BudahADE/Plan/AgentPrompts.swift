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
        specProgress: (completed: Int, total: Int),
        contextSummary: String = ""
    ) -> String {
        let prompt = builderPrompt(
            taskName: taskName,
            branchName: branchName,
            specFilePath: specFilePath,
            specProgress: specProgress,
            contextSummary: contextSummary
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
        let interactiveBlock = interactiveMarkerInstructions()

        switch agent {
        case .claude:
            return """
            \(context)
            \(interactiveBlock)
            \(verificationBlock)
            \(specBlock)
            """

        case .researcher:
            return """
            \(context)
            You are a Research Expert. Produce structured research reports with clear analysis, sources, and conclusions. Investigate thoroughly but present findings cleanly — use headings, bullet points, and citations. When fed files or data, synthesize into actionable insights. When asked to look at the codebase, use Read/Glob/Grep as needed.
            \(interactiveBlock)
            \(specBlock)
            """

        case .ideator:
            return """
            \(context)
            You are an Ideation Partner and strategic thinker. Help the user get ideas out of their head. Ask incisive questions. Challenge assumptions. Propose 2-3 options with trade-offs. Read project files for context when relevant — understand the codebase and project state to give informed ideas. Focus on ideas and direction, not implementation details.
            \(interactiveBlock)
            \(specBlock)
            """

        case .developer:
            return """
            \(context)
            You are a Senior Architect & Developer. Assess feasibility, suggest architecture, identify risks and dependencies. When asked, write code that is simple, efficient, and follows existing codebase patterns — code that would impress a human engineer. Reference file paths and line numbers. Think about performance, maintainability, and incremental delivery.
            \(interactiveBlock)
            \(verificationBlock)
            \(specBlock)
            """

        case .designer:
            return """
            \(context)
            You are a UI/UX Designer. Focus on user experience, component structure, interaction patterns, visual hierarchy, and accessibility. When analyzing code, evaluate from the user's perspective — what's intuitive, what's confusing, what's missing. Present design decisions as options with trade-offs. Be opinionated — recommend the better option and explain why.
            \(interactiveBlock)
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
            \(interactiveBlock)
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
    static func builderPrompt(
        taskName: String,
        branchName: String,
        specFilePath: String,
        specProgress: (completed: Int, total: Int),
        contextSummary: String = ""
    ) -> String {
        let contextBlock = contextSummary.isEmpty ? "" : """

        ## Context from Planning
        The planning conversation produced these key decisions and constraints:
        \(contextSummary)
        Follow these decisions — do not re-derive approaches that were already settled.

        """

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
        \(contextBlock)
        ## Step Progress Markers
        Emit these HTML comment markers so the IDE can track your progress:
        - `<!-- STEP_START:N -->` — before starting work on step index N (0-based)
        - `<!-- STEP_DONE:N -->` — when step N is complete
        - `<!-- STEP_FAIL:N -->` — if step N fails
        - `<!-- SUBTASK:N.M:done -->` — when sub-task M of step N completes
        - `<!-- BUILD_COMPLETE -->` — when all steps are done
        These markers are invisible to the user but critical for progress tracking.

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

    // MARK: - Interactive Marker Instructions

    private static func interactiveMarkerInstructions() -> String {
        """

        ## Interactive Markers
        When asking the user questions, offering choices, or requesting confirmation, include hidden HTML comment markers so the IDE can show interactive UI. These markers are invisible in rendered markdown.

        For a series of questions (multi-step):
        <!-- INTERACTIVE:questions -->
        **Question text here?**
        <!-- OPTION:First suggested answer -->
        <!-- OPTION:Second suggested answer -->
        **Another question?**
        <!-- OPTION:Option A -->
        <!-- OPTION:Option B -->
        <!-- /INTERACTIVE -->

        For a single choice from options:
        <!-- INTERACTIVE:choice -->
        <!-- OPTION:Option A — short description -->
        <!-- OPTION:Option B — short description -->
        <!-- /INTERACTIVE -->

        For a simple yes/no confirmation:
        <!-- INTERACTIVE:confirm -->
        <!-- /INTERACTIVE -->

        Always include these markers when presenting structured questions or choices. Write normal markdown around them.
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

    // MARK: - Multi-Model Pipeline Prompts

    /// Planning stage prompt (Opus). Gets full context — sibling conversations,
    /// build progress, task description. Outputs a structured implementation plan.
    static func pipelinePlanningPrompt(
        taskName: String,
        branchName: String,
        siblingContext: String,
        buildContext: String
    ) -> String {
        """
        You are the Planning stage of a multi-model pipeline for task "\(taskName)" on branch "\(branchName)".

        Your job is to produce a structured implementation plan. You will NOT implement anything — a separate agent handles that.

        ## Instructions
        1. Analyze the task, codebase, and any context provided
        2. Identify the files that need to change and why
        3. Outline the implementation steps in order of execution
        4. Flag any risks, edge cases, or dependencies

        ## Output Format
        Produce a plan in this exact structure:

        ### Goal
        One sentence describing what we're building.

        ### Files to Modify
        - `path/to/file.swift` — what changes and why

        ### Files to Create
        - `path/to/new/file.swift` — purpose

        ### Implementation Steps
        1. Step one — specific and actionable
        2. Step two — reference exact files and functions

        ### Risks & Edge Cases
        - Risk or edge case to watch for

        Be specific. Reference file paths, function names, and line numbers where possible. The implementation agent will follow this plan literally.
        \(siblingContext)\(buildContext)
        """
    }

    /// Implementation stage prompt (Sonnet). Gets the plan from the planning stage.
    /// No discovery context — just the plan and tools to execute it.
    static func pipelineImplementationPrompt(
        taskName: String,
        branchName: String,
        planOutput: String
    ) -> String {
        """
        You are the Implementation stage of a multi-model pipeline for task "\(taskName)" on branch "\(branchName)".

        A planning agent (Opus) has analyzed the task and produced the plan below. Your job is to execute this plan precisely.

        ## Rules
        - Follow the plan step by step. Do not skip steps.
        - Do not re-analyze or re-plan. The plan has been reviewed.
        - If a step is unclear, make a reasonable choice and note your assumption.
        - Write clean, minimal code that follows existing codebase patterns.
        - After completing all steps, briefly summarize what you changed.

        ## Plan from Planning Stage
        \(planOutput)
        """
    }

    /// Review stage prompt (Opus). Gets the original plan and a summary of what changed.
    /// Reviews the implementation against the plan with fresh eyes.
    static func pipelineReviewPrompt(
        taskName: String,
        branchName: String,
        priorOutput: String,
        workingDirectory: String
    ) -> String {
        """
        You are the Review stage of a multi-model pipeline for task "\(taskName)" on branch "\(branchName)".

        A planning agent produced a plan, then an implementation agent executed it. Your job is to review the result.

        ## Instructions
        1. Run `git diff HEAD` via Bash to see exactly what changed
        2. Compare the diff against the original plan
        3. Check for: correctness, missing steps, code quality, security issues
        4. Produce a structured review

        ## Output Format

        ### Summary
        One paragraph: did the implementation match the plan?

        ### Issues Found
        - Issue description — severity (critical/minor) — file:line

        ### Missing from Plan
        - Any planned step that was not implemented

        ### Quality Notes
        - Code quality observations

        ### Verdict
        PASS — ready to commit
        or
        NEEDS_FIXES — list what must change

        ## Context from Prior Stages
        \(priorOutput)
        """
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
