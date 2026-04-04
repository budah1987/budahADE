import Foundation
import Combine

// MARK: - Builder Agent

/// Coordinates between CLISubprocessManager and BuilderSession.
/// Creates an agent session, routes messages through BuildStepTracker,
/// and keeps BuilderSession in sync with agent state.
@MainActor
final class BuilderAgent: ObservableObject {
    let builderSession: BuilderSession
    let chatManager: CLISubprocessManager
    let stepTracker = BuildStepTracker()

    private(set) var agentSession: AgentSession?
    private var statusObserver: AnyCancellable?

    init(builderSession: BuilderSession, chatManager: CLISubprocessManager) {
        self.builderSession = builderSession
        self.chatManager = chatManager
        self.stepTracker.session = builderSession
    }

    // MARK: - Launch

    /// Launch the builder agent with the spec and context.
    func launch(
        worktreePath: String,
        specFilePath: String,
        specProgress: (completed: Int, total: Int),
        taskName: String,
        branchName: String
    ) {
        // Create the agent session with the raw builder prompt
        let systemPrompt = AgentPrompts.builderPrompt(
            taskName: taskName,
            branchName: branchName,
            specFilePath: specFilePath,
            specProgress: specProgress,
            contextSummary: builderSession.contextSummary
        )

        let session = chatManager.createSession(
            model: .sonnet,
            agentMode: .developer,
            systemPrompt: systemPrompt,
            workingDirectory: worktreePath,
            enableAgentTeams: true
        )

        self.agentSession = session
        builderSession.agentSessionId = session.id

        // Observe agent session status — throttled to 5/sec to prevent main-thread saturation
        statusObserver = session.objectWillChange
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.syncState()
            }

        // Ensure at least one step exists
        if builderSession.steps.isEmpty {
            builderSession.steps.append(BuildStep(title: "Implement spec"))
        }

        // Start first queued step
        if let firstQueued = builderSession.steps.indices.first(where: { builderSession.steps[$0].state == .queued }) {
            builderSession.startStep(at: firstQueued)
        } else {
            builderSession.buildState = .building
        }

        // Send initial prompt to begin building
        chatManager.send(sessionId: session.id, prompt: "Begin building. Start with step 0.")
    }

    // MARK: - Send User Message

    /// Send a message from the user to the builder agent.
    func sendMessage(_ text: String) {
        guard let session = agentSession else { return }

        // Add to builder session messages
        let userMessage = ChatMessage(role: .user, content: text)
        builderSession.messages.append(userMessage)
        builderSession.addTurnMarker(for: userMessage)

        // Forward to agent
        chatManager.send(sessionId: session.id, prompt: text)
    }

    // MARK: - Pause / Resume / Cancel

    func pause() {
        guard let session = agentSession else { return }
        builderSession.buildState = .paused
        chatManager.cancel(sessionId: session.id)
    }

    func resume() {
        guard let session = agentSession else { return }
        builderSession.buildState = .building
        resetLoopFlag()
        let stepIdx = builderSession.activeStepIndex ?? 0
        chatManager.send(sessionId: session.id, prompt: "Resume building. Continue from step \(stepIdx).")
    }

    func cancel() {
        guard let session = agentSession else { return }
        chatManager.cancel(sessionId: session.id)
        builderSession.buildState = .ready
    }

    // MARK: - State Sync

    /// Sync agent session state → builder session state
    private func syncState() {
        guard let session = agentSession else { return }

        builderSession.isStreaming = session.status == .streaming

        // Process new messages through step tracker
        let existingIds = Set(builderSession.messages.map(\.id))
        let newMessages = session.messages.filter { !existingIds.contains($0.id) && $0.role != .user }

        for message in newMessages {
            if message.role == .assistant {
                // Process through step tracker to detect markers
                let cleanContent = stepTracker.processText(message.content)
                if !cleanContent.isEmpty {
                    let cleanMessage = ChatMessage(
                        id: message.id,
                        role: message.role,
                        content: cleanContent,
                        toolCalls: message.toolCalls,
                        timestamp: message.timestamp,
                        inputTokens: message.inputTokens,
                        outputTokens: message.outputTokens
                    )
                    builderSession.messages.append(cleanMessage)
                }
            } else {
                builderSession.messages.append(message)
            }
        }

        // Check for loop detection warnings
        checkLoopDetection()

        // Sync streaming text (strip markers for display)
        if session.status == .streaming && !session.currentStreamingText.isEmpty {
            builderSession.currentActivity = stripMarkers(session.currentStreamingText)
        } else {
            builderSession.currentActivity = nil
        }

        // Detect completion
        if session.status == .done && builderSession.buildState == .building {
            // Agent finished a turn — check if all steps done
            if builderSession.steps.allSatisfy({ $0.state == .done || $0.state == .skipped }) {
                builderSession.buildState = .done
            }
        }
    }

    // MARK: - Loop Detection

    /// Check if the agent's loop detector has fired, and if so, force pause with coaching.
    private func checkLoopDetection() {
        guard let session = agentSession, builderSession.buildState == .building else { return }

        // Check if loop detector has any files at or above threshold
        let loopedFiles = session.loopDetector.fileEditCounts.filter { $0.value >= session.loopDetector.warningThreshold }
        guard !loopedFiles.isEmpty else { return }

        // Only trigger once per pause cycle
        guard !hasTriggeredLoopPause else { return }
        hasTriggeredLoopPause = true

        // Force pause
        pause()

        // Insert coaching message
        let fileName = loopedFiles.max(by: { $0.value < $1.value })?.key ?? "a file"
        let editCount = loopedFiles.max(by: { $0.value < $1.value })?.value ?? 5

        let coachingMessage = ChatMessage(
            role: .system,
            content: """
            ⚠ I've edited **\(fileName)** \(editCount) times on this step. I may be stuck.

            What would you like to do?
            → **Edit the spec step** — clarify what's needed
            → **Skip this step** — move to the next one
            → **Let me try a different approach** — resume with alternative strategy
            """
        )
        builderSession.messages.append(coachingMessage)
    }

    private var hasTriggeredLoopPause = false

    /// Reset loop pause flag when resuming
    private func resetLoopFlag() {
        hasTriggeredLoopPause = false
    }

    /// Strip step markers from text for display
    private func stripMarkers(_ text: String) -> String {
        var result = text
        let patterns = [
            "<!-- STEP_START:\\d+ -->",
            "<!-- STEP_DONE:\\d+ -->",
            "<!-- STEP_FAIL:\\d+ -->",
            "<!-- SUBTASK:\\d+\\.\\d+:\\w+ -->",
            "<!-- BUILD_COMPLETE -->"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
