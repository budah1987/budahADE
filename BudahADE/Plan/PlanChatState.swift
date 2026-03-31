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
    @Published var handedOffContext: [(role: AgentMode, content: String)] = []
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

        // Inject environment context (directory structure, tooling, git branch)
        let envContext = EnvironmentContext.discover(workingDirectory: worktreePath)
        prompt += envContext

        // Inject failure memory from previous sessions
        let failureContext = FailureMemory.contextBlock(worktreePath: worktreePath)
        prompt += failureContext

        // Load sibling conversations — use truncated fallback initially,
        // then upgrade to Haiku summaries asynchronously
        let siblings = PlanConversationPersistence.loadAllExcluding(
            tabId: self.tabId,
            from: worktreePath
        )
        let siblingContext = AgentPrompts.siblingContextBlock(from: siblings, worktreePath: worktreePath)
        let buildContext = AgentPrompts.buildContextBlock(worktreePath: worktreePath)

        // Append sibling context and build context to system prompt
        prompt += siblingContext
        prompt += buildContext

        // Append any handed-off content from other tabs
        if !handedOffContext.isEmpty {
            prompt += "\n## Handed-off context\n"
            for item in handedOffContext {
                prompt += "\n### From \(item.role.displayName)\n\(item.content)\n"
            }
        }

        let session = chatManager.createSession(
            model: selectedModel,
            agentMode: role,
            systemPrompt: prompt,
            workingDirectory: worktreePath,
            enableAgentTeams: true,
            disableMcp: true
        )

        // Wire auto-verification: when the agent finishes, send a spec-aware verification prompt
        let taskNameCopy = taskName
        let roleCopy = role
        let worktreePathCopy = worktreePath
        chatManager.onSessionComplete = { [weak self] sessionId in
            guard let self = self,
                  let session = self.plannerSession,
                  session.id == sessionId,
                  !session.hasVerified else { return }

            if let verifyPrompt = SelfVerification.verificationPrompt(
                taskName: taskNameCopy, role: roleCopy, worktreePath: worktreePathCopy
            ) {
                session.hasVerified = true
                self.chatManager.send(sessionId: sessionId, prompt: verifyPrompt)
            }
        }

        // Fire-and-forget: generate Haiku summaries for sibling context.
        // These will be available for the next session creation.
        if !siblings.isEmpty {
            let siblingsCopy = siblings
            let pathCopy = worktreePath
            Task {
                let summaryBlock = await SiblingSummarizer.summarizeAll(siblingsCopy)
                if !summaryBlock.isEmpty {
                    // Persist summaries so next session picks them up without re-summarizing
                    let cachePath = (pathCopy as NSString)
                        .appendingPathComponent(".budahade/sibling-summaries.md")
                    try? summaryBlock.write(toFile: cachePath, atomically: true, encoding: .utf8)
                }
            }
        }

        plannerSession = session
        return session
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle /commands
        if trimmed.hasPrefix("/") {
            if let handled = handleLocalCommand(trimmed) {
                // Command handled locally — don't send to agent
                if !handled.isEmpty {
                    // Add as system message for feedback
                    plannerSession?.messages.append(ChatMessage(role: .system, content: handled))
                }
                return
            }
            // Not a local command — convert to skill invocation
            let expanded = expandSlashCommand(trimmed)
            let session = ensureSession()
            if conversationState == .idle { conversationState = .chatting }
            chatManager.send(sessionId: session.id, prompt: expanded, model: selectedModel)
            persistConversation()
            return
        }

        let session = ensureSession()
        if conversationState == .idle {
            conversationState = .chatting
        }
        chatManager.send(sessionId: session.id, prompt: text, model: selectedModel)
        persistConversation()
    }

    /// Handle commands that should be processed locally, not sent to the agent.
    /// Returns a feedback message, or nil if the command is not a local command.
    private func handleLocalCommand(_ command: String) -> String? {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = parts.first.map(String.init) ?? command

        switch cmd {
        case "/clear":
            newSession()
            return "Conversation cleared."
        case "/model":
            // Cycle to next model
            let models = AgentModel.allCases
            if let idx = models.firstIndex(of: selectedModel) {
                selectedModel = models[(idx + 1) % models.count]
            }
            return "Switched to \(selectedModel.displayName)."
        default:
            return nil // Not a local command
        }
    }

    /// Convert a slash command into a natural language prompt that invokes the skill.
    private func expandSlashCommand(_ command: String) -> String {
        let parts = command.split(separator: " ", maxSplits: 1)
        let skillName = String(parts[0].dropFirst()) // Remove leading /
        let args = parts.count > 1 ? String(parts[1]) : ""

        if args.isEmpty {
            return "Use the \(skillName) skill."
        } else {
            return "Use the \(skillName) skill with: \(args)"
        }
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

    // MARK: - Hand Off

    /// Receives handed-off content from another tab.
    /// If a session already exists, sends it as a message (NOT duplicated in system prompt).
    /// If no session yet, stores it for system prompt injection on session creation.
    func receiveHandOff(from role: AgentMode, content: String) {
        // If session already exists, send as user message only (not stored for system prompt)
        if plannerSession != nil {
            let handOffMessage = "[Handed off from \(role.displayName)]\n\n\(content)"
            sendMessage(handOffMessage)
        } else {
            // No session yet — store for system prompt injection on creation
            handedOffContext.append((role: role, content: content))
        }
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
