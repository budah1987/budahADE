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
    let tabId: UUID
    let worktreePath: String
    let taskName: String
    let branchName: String
    let role: AgentMode

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
    @Published var selectedModel: AgentModel
    @Published var pendingSpec: String?
    @Published var editingMessageId: UUID?
    private var sessionCancellable: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?

    // MARK: - Init

    init(tabId: UUID = UUID(), worktreePath: String, taskName: String, branchName: String, role: AgentMode = .researcher) {
        self.tabId = tabId
        self.worktreePath = worktreePath
        self.taskName = taskName
        self.branchName = branchName
        self.role = role
        self.selectedModel = role.defaultChatModel
    }

    // MARK: - Session Lifecycle

    func ensureSession() -> AgentSession {
        if let existing = plannerSession {
            return existing
        }
        var prompt = plannerSystemPrompt()

        // Load sibling conversations for context injection
        let siblings = PlanConversationPersistence.loadAllExcluding(
            tabId: self.tabId,
            from: worktreePath
        )
        let siblingContext = AgentPrompts.siblingContextBlock(from: siblings)

        // Append sibling context to system prompt
        prompt += siblingContext

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
        persistConversation()
    }

    func persistConversation() {
        persistenceTask?.cancel()
        persistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let session = plannerSession else { return }
            let snapshot = ConversationSnapshot(
                tabId: self.tabId,
                role: self.role,
                messages: session.messages
            )
            PlanConversationPersistence.save(snapshot, to: worktreePath)
        }
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

    // MARK: - Spec Detection

    func looksLikeSpec(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let hasSpecHeading = lowered.contains("# spec") ||
            lowered.contains("# plan") ||
            lowered.contains("# implementation plan") ||
            lowered.contains("# design") ||
            lowered.contains("# architecture") ||
            lowered.contains("## spec") ||
            lowered.contains("## plan") ||
            lowered.contains("## implementation plan") ||
            lowered.contains("## design") ||
            lowered.contains("## architecture")

        let hasList = content.contains("\n- ") || content.contains("\n1. ") || content.contains("\n* ")

        return hasSpecHeading && hasList
    }

    // MARK: - Planner Prompt

    private func plannerSystemPrompt() -> String {
        return AgentPrompts.systemPrompt(
            agent: role,
            taskName: taskName,
            branchName: branchName
        )
    }
}
