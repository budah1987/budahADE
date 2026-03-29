import Foundation
import Combine

// MARK: - Plan Conversation State

enum PlanConversationState: Equatable {
    case idle
    case chatting
    case specGenerated
    case specEdited
    case building(specPath: String)
}

// MARK: - Plan Chat State

@MainActor
final class PlanChatState: ObservableObject {
    let worktreePath: String
    let taskName: String
    let branchName: String

    let chatManager = CLISubprocessManager()
    @Published var plannerSession: AgentSession? {
        didSet {
            sessionCancellable?.cancel()
            if let session = plannerSession {
                // Forward session's objectWillChange so PlanChatView re-renders
                // when session.status, session.messages, etc. change
                sessionCancellable = session.objectWillChange.sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
            }
        }
    }
    @Published var conversationState: PlanConversationState = .idle
    @Published var selectedModel: AgentModel = .sonnet
    private var sessionCancellable: AnyCancellable?

    // MARK: - Init

    init(worktreePath: String, taskName: String, branchName: String) {
        self.worktreePath = worktreePath
        self.taskName = taskName
        self.branchName = branchName
    }

    // MARK: - Session Lifecycle

    func ensureSession() -> AgentSession {
        if let existing = plannerSession {
            return existing
        }
        let prompt = plannerSystemPrompt()
        let session = chatManager.createSession(
            model: selectedModel,
            agentMode: nil,
            systemPrompt: prompt,
            workingDirectory: worktreePath,
            enableAgentTeams: true,
            disableMcp: true
        )
        plannerSession = session
        return session
    }

    func sendMessage(_ text: String) {
        let session = ensureSession()
        if conversationState == .idle {
            conversationState = .chatting
        }
        chatManager.send(sessionId: session.id, prompt: text, model: selectedModel)
    }

    func cancel() {
        guard let session = plannerSession else { return }
        chatManager.cancel(sessionId: session.id)
    }

    func newSession() {
        if let existing = plannerSession {
            chatManager.removeSession(sessionId: existing.id)
        }
        plannerSession = nil
        conversationState = .idle
    }

    // MARK: - Image Support

    func saveImage(data: Data) -> String? {
        let imageDir = "\(worktreePath)/.budahade/images"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: imageDir, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).png"
        let path = "\(imageDir)/\(filename)"
        guard fm.createFile(atPath: path, contents: data) else { return nil }
        return path
    }

    // MARK: - Planner Prompt

    private func plannerSystemPrompt() -> String {
        return """
        You are a planning collaborator for task "\(taskName)" on branch "\(branchName)".

        IMPORTANT: Respond to the user immediately with text. Do NOT use tools on your first response unless the user explicitly asks you to research or look something up. Do NOT read memory files or check session history before responding.

        ## Your approach
        Start by understanding. Ask questions. Be curious about the problem before jumping to solutions.

        - Listen first — understand what the user is trying to achieve and why
        - Ask clarifying questions before researching or proposing solutions
        - Think out loud — share your reasoning, surface tradeoffs
        - Only research the codebase or spawn agents when the user's intent is clear
        - Match the user's energy — brief questions get brief answers, deep exploration gets depth

        ## When the problem is clear, analyze through multiple lenses
        Use your teammate agents to explore the problem from several perspectives:
        - @researcher: Codebase analysis, existing patterns, dependencies
        - @architect: System design, code patterns, technical tradeoffs
        - @ideator: Creative solutions, alternative approaches, business impact
        - @qa: Edge cases, failure modes, testing strategy
        - @designer: UI/UX considerations, component design, user experience

        ## Workflow
        1. Listen — understand intent and constraints
        2. Research — use agents to explore the codebase and problem space
        3. Synthesize — combine perspectives into a coherent plan
        4. Spec — produce a structured spec with clear tasks and acceptance criteria

        ## Guidelines
        - Be concise and direct
        - Reference specific files and line numbers when discussing code
        - Don't over-engineer the conversation — simple questions deserve simple answers
        """
    }
}
