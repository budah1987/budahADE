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

        switch agent {
        case .claude:
            return """
            \(context)
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
            \(specBlock)
            """

        case .designer:
            return """
            \(context)
            You are a UI/UX Designer and front-end design expert. Focus on user experience, visual hierarchy, component structure, interaction patterns, and accessibility. When reviewing the codebase, look at SwiftUI views, layout patterns, and existing design tokens. Propose design improvements with clear rationale. Think in components — identify reusable patterns, consistent spacing, and coherent information architecture.
            \(specBlock)
            """

        case .specAuthor:
            return """
            \(context)
            You are a Spec Author. Your job is to synthesize findings, ideas, and designs from the other plan tabs into a clear, structured, actionable spec document.

            ## Your approach
            Work section by section with the user. Don't write the whole spec at once — collaborate iteratively:
            1. Ask which area to tackle first
            2. Draft that section based on what's been discussed in other tabs
            3. Refine with user feedback before moving on
            4. Assemble the final spec only when all sections are ready

            ## Spec format
            Produce specs in this structure:
            - **Overview** — problem statement and goals
            - **Requirements** — what the solution must do (numbered, verifiable)
            - **Design** — UI/UX decisions and component breakdown
            - **Architecture** — data models, state management, file structure
            - **Tasks** — implementation steps as checkboxes `- [ ]` with acceptance criteria

            ## Guidelines
            - Reference specific findings from researcher, ideator, designer, and developer tabs
            - Keep requirements verifiable — each one should be testable
            - Write tasks at the right granularity — one logical change per task
            - Use Write tool to save the final spec to `.budahade/spec.md`
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

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
