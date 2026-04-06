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
    let repoPath: String
    let taskName: String
    let branchName: String
    let role: AgentMode

    let chatManager = CLISubprocessManager()
    @Published var plannerSession: AgentSession? {
        didSet {
            sessionCancellable?.cancel()
            if let session = plannerSession {
                // Forward session's objectWillChange so PlanChatView re-renders
                // when session.status, session.messages, etc. change.
                // Throttled to 100ms — caps at 10/sec during streaming (was 12.5/sec).
                sessionCancellable = session.objectWillChange
                    .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                    .sink { [weak self] _ in
                        Task { @MainActor [weak self] in self?.objectWillChange.send() }
                    }
            }
        }
    }
    @Published var conversationState: PlanConversationState = .idle
    @Published var selectedModel: AgentModel
    @Published var pendingSpec: String?
    @Published var editingMessageId: UUID?
    @Published var handedOffContext: [(role: AgentMode, content: String)] = []

    /// Tracks which spec-ready signals have already been dismissed
    @Published var dismissedSpecSignals: Set<String> = []

    /// Reactive spec-ready detection — same pattern as option/confirmation detection.
    /// Just checks "what did the agent say?" without status gates or latching.
    /// Returns a signal ID (for dismissal tracking) or nil if no spec is ready.
    var specReadySignalId: String? {
        guard let session = plannerSession,
              session.status != .streaming,
              session.status != .connecting else { return nil }

        // Signal 1: Agent wrote a spec file to disk
        for entry in session.activityFeed.reversed() {
            guard case .toolWrite(let filePath) = entry.kind,
                  entry.status == .completed else { continue }
            let lower = (filePath as NSString).lastPathComponent.lowercased()
            if lower.contains("spec") || lower.contains("plan") {
                let signalId = "write:\(entry.id)"
                if !dismissedSpecSignals.contains(signalId) { return signalId }
            }
        }

        // Signal 2: Recent assistant messages have spec content or declare completion.
        // Check last few (not just the very last) because verification/confirmation
        // responses can push the spec message down.
        let recentAssistant = session.messages
            .filter { $0.role == .assistant && !$0.content.isEmpty }
            .suffix(5)
        for msg in recentAssistant.reversed() {
            if looksLikeSpec(msg.content) || looksLikeSpecCompletion(msg.content) {
                let signalId = "msg:\(msg.id)"
                if !dismissedSpecSignals.contains(signalId) { return signalId }
            }
        }

        return nil
    }
    /// When true, messages are routed through the multi-model pipeline
    /// (Plan with Opus → Implement with Sonnet → Review with Opus)
    @Published var pipelineMode: Bool = false
    /// Active pipeline instance (non-nil while a pipeline is running)
    @Published var activePipeline: MultiModelPipeline?
    @Published var turnMarkers: [ChatTurnMarker] = []
    private var pipelineCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?

    // MARK: - Init

    init(tabId: UUID = UUID(), worktreePath: String, repoPath: String, taskName: String, branchName: String, role: AgentMode = .researcher) {
        self.tabId = tabId
        self.worktreePath = worktreePath
        self.repoPath = repoPath
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

        // Wire session completion: cost tracking, trace recording, verification, adaptive limits
        let taskNameCopy = taskName
        let roleCopy = role
        let worktreePathCopy = worktreePath
        chatManager.onSessionComplete = { [weak self] sessionId in
            guard let self = self,
                  let session = self.plannerSession,
                  session.id == sessionId else { return }

            // Record cost and trace data
            if let result = session.lastResult {
                CostTracker.record(
                    taskName: taskNameCopy,
                    role: roleCopy,
                    model: session.model,
                    result: result,
                    worktreePath: worktreePathCopy
                )
                TraceAnalysis.recordTrace(
                    taskName: taskNameCopy,
                    session: session,
                    result: result,
                    worktreePath: worktreePathCopy
                )
            }

            // Adaptive turn limit: if already verified, don't send more prompts
            guard !session.isVerifiedComplete else { return }

            // First completion → send spec-diff verification if spec exists, else standard verification
            if !session.hasVerified {
                if let diffPrompt = SpecDiffVerification.diffPrompt(worktreePath: worktreePathCopy) {
                    session.hasVerified = true
                    self.chatManager.send(sessionId: sessionId, prompt: diffPrompt, showInChat: false)
                } else if let verifyPrompt = SelfVerification.verificationPrompt(
                    taskName: taskNameCopy, role: roleCopy, worktreePath: worktreePathCopy
                ) {
                    session.hasVerified = true
                    self.chatManager.send(sessionId: sessionId, prompt: verifyPrompt, showInChat: false)
                }
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

        // Pipeline mode: route through multi-model pipeline
        if pipelineMode {
            startPipeline(prompt: text)
            return
        }

        let session = ensureSession()
        if conversationState == .idle {
            conversationState = .chatting
        }
        // Reset adaptive turn limit — user explicitly wants to continue
        session.isVerifiedComplete = false
        session.hasVerified = false
        chatManager.send(sessionId: session.id, prompt: text, model: selectedModel)

        // Track user turn for scrubber
        if let lastUserMsg = session.messages.last(where: { $0.role == .user }) {
            turnMarkers.append(ChatTurnMarker.from(lastUserMsg))
        }

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
        case "/pipeline":
            pipelineMode.toggle()
            return pipelineMode
                ? "Pipeline mode ON — messages will route through Plan (Opus) → Implement (Sonnet) → Review (Opus)."
                : "Pipeline mode OFF — messages go to a single session."
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

    // MARK: - Pipeline Lifecycle

    /// Start a multi-model pipeline for the given prompt.
    /// Creates a fresh pipeline with Plan → Implement → Review stages.
    private func startPipeline(prompt: String) {
        // Cancel any existing pipeline
        activePipeline?.cancel()
        pipelineCancellable?.cancel()

        if conversationState == .idle {
            conversationState = .chatting
        }

        // Build sibling + build context for the planning stage
        let siblings = PlanConversationPersistence.loadAllExcluding(
            tabId: self.tabId,
            from: worktreePath
        )
        let siblingContext = AgentPrompts.siblingContextBlock(from: siblings, worktreePath: worktreePath)
        let buildContext = AgentPrompts.buildContextBlock(worktreePath: worktreePath)

        let pipeline = MultiModelPipeline.standard(
            chatManager: chatManager,
            workingDirectory: worktreePath,
            taskName: taskName,
            branchName: branchName,
            siblingContext: siblingContext,
            buildContext: buildContext
        )
        activePipeline = pipeline

        // Forward pipeline's objectWillChange so the view re-renders
        pipelineCancellable = pipeline.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }

        // Add user message to the display session so it shows in chat
        let session = ensureSession()
        session.addUserMessage(prompt)

        pipeline.execute(prompt: prompt)
    }

    func cancelPipeline() {
        activePipeline?.cancel()
        activePipeline = nil
        pipelineCancellable?.cancel()
    }

    func persistConversation() {
        persistenceTask?.cancel()
        // Capture session reference before the async sleep — plannerSession may be
        // cleared (tab closed) during the 1-second debounce window.
        guard let session = plannerSession else { return }
        persistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let snapshot = ConversationSnapshot(
                tabId: self.tabId,
                role: self.role,
                messages: session.messages
            )
            PlanConversationPersistence.save(snapshot, to: worktreePath)
        }
    }

    func cancel() {
        if activePipeline != nil {
            cancelPipeline()
            return
        }
        guard let session = plannerSession else { return }
        chatManager.cancel(sessionId: session.id)
    }

    func newSession() {
        cancelPipeline()
        if let existing = plannerSession {
            chatManager.removeSession(sessionId: existing.id)
        }
        plannerSession = nil
        activePipeline = nil
        conversationState = .idle
    }

    // MARK: - Context Summary for Builder

    /// Generate a concise summary of key decisions from this plan conversation.
    /// Used to bridge context from plan → builder agent.
    func generateContextSummary() -> String {
        guard let session = plannerSession else { return "" }

        // Extract assistant messages that likely contain decisions
        let assistantMessages = session.messages
            .filter { $0.role == .assistant && !$0.content.isEmpty }
            .suffix(10) // Last 10 assistant messages — most relevant

        guard !assistantMessages.isEmpty else { return "" }

        // Build a condensed summary from conversation highlights
        var summary: [String] = []
        summary.append("- Role: \(role.displayName)")
        summary.append("- Task: \(taskName) on branch \(branchName)")

        // Include key messages (decisions tend to be in longer assistant messages)
        for msg in assistantMessages {
            let lines = msg.content.components(separatedBy: .newlines)
            // Look for decision-like patterns: bullet points, "we decided", headings
            let keyLines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ") ||
                       trimmed.hasPrefix("## ") ||
                       trimmed.hasPrefix("### ") ||
                       trimmed.lowercased().contains("decision") ||
                       trimmed.lowercased().contains("approach") ||
                       trimmed.lowercased().contains("constraint") ||
                       trimmed.lowercased().contains("important")
            }
            summary.append(contentsOf: keyLines.prefix(5))
        }

        // Cap at ~500 words
        let joined = summary.joined(separator: "\n")
        if joined.count > 2000 {
            return String(joined.prefix(2000)) + "\n[truncated]"
        }
        return joined
    }

    /// Generate context summary asynchronously by asking the plan agent to summarize.
    /// Falls back to local extraction if the agent is unavailable.
    func generateContextSummaryAsync() async -> String {
        // For now, use local extraction. Phase L+ could send a hidden prompt
        // to the plan agent for a richer summary.
        return generateContextSummary()
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
            lowered.contains("## architecture") ||
            lowered.contains("## overview") ||
            lowered.contains("## goals") ||
            lowered.contains("## requirements") ||
            lowered.contains("## components")

        let hasList = content.contains("\n- ") || content.contains("\n1. ") ||
            content.contains("\n* ") || content.contains("\n· ") ||
            content.contains("\n• ") || content.contains("\n→ ")

        return hasSpecHeading && hasList
    }

    /// Detects spec-completion phrases: the agent says "the spec is ready" with structured content.
    /// Catches cases where the agent doesn't use markdown headings but clearly declares completion.
    func looksLikeSpecCompletion(_ content: String) -> Bool {
        let lowered = content.lowercased()
        let completionPhrases = [
            "spec is complete",
            "specification is complete",
            "spec is ready",
            "specification is ready",
            "ready for implementation",
            "ready to implement",
            "ready to build",
            "ready to start building",
            "complete and approved",
            "approved and complete",
            "finalized the spec",
            "spec has been finalized",
            "here is the complete spec",
            "here's the complete spec",
            "here is the final spec",
            "here's the final spec",
        ]
        let hasCompletion = completionPhrases.contains { lowered.contains($0) }
        guard hasCompletion else { return false }

        // Must also have some structure (lists or multiple paragraphs)
        let hasList = content.contains("\n- ") || content.contains("\n1. ") ||
            content.contains("\n* ") || content.contains("\n· ") ||
            content.contains("\n• ") || content.contains("\n→ ")
        let hasMultipleParagraphs = content.components(separatedBy: "\n\n").count >= 3

        return hasList || hasMultipleParagraphs
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
