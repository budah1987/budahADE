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

    // MARK: - Init

    init(worktreePath: String, taskName: String, branchName: String, role: AgentMode = .researcher) {
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
