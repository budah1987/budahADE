import Foundation

enum AgentPrompts {

    /// Build the full `claude` launch command for an agent mode
    static func launchCommand(
        agent: AgentMode,
        taskName: String,
        branchName: String,
        worktreePath: String
    ) -> String {
        guard let prompt = systemPrompt(
            agent: agent,
            taskName: taskName,
            branchName: branchName
        ) else {
            return "claude"
        }

        // Write prompt to temp file, pass via cat to avoid shell escaping issues
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let filename = ".budahade/\(agent.rawValue)-prompt.md"
        let path = (worktreePath as NSString).appendingPathComponent(filename)
        try? prompt.write(toFile: path, atomically: true, encoding: .utf8)

        return "claude --system-prompt \"$(cat '\(path)')\""
    }

    // MARK: - Prompts

    private static func systemPrompt(
        agent: AgentMode,
        taskName: String,
        branchName: String
    ) -> String? {
        let context = """
        You are helping plan task "\(taskName)" on branch "\(branchName)".
        Read `.budahade/plan-context.md` for reference materials on the canvas (images, documents, URLs).
        """

        switch agent {
        case .claude:
            return """
            \(context)
            Help the user iterate on ideas. Be concise. Ask clarifying questions.
            When the plan is solid, write it to a spec file (e.g. `\(slugify(taskName))-spec.md`) with checkbox tasks (`- [ ] Task`).
            Keep the spec updated as scope evolves.
            """

        case .researcher:
            return """
            \(context)
            You are a Research Expert. Investigate topics thoroughly, synthesize findings, and present clear analysis.
            Check multiple sources, consider opposing viewpoints, and distinguish facts from speculation.
            When findings are solid, suggest updates to the spec.
            """

        case .ideator:
            return """
            \(context)
            You are a Product Thinker and Ideation Partner. Help form ideas by asking incisive questions.
            You know product frameworks (Jobs-to-be-Done, Design Thinking, First Principles).
            Challenge assumptions. Get to the truth of the problem before jumping to solutions.
            Help refine ideas before committing to implementation.
            """

        case .developer:
            return """
            \(context)
            You are a Technical Architect. Assess feasibility, suggest architecture, identify risks and dependencies.
            Think about performance, maintainability, and what can be built incrementally.
            When the approach is clear, help structure the spec with concrete implementation tasks.
            """
        }
    }

    private static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
