import Foundation
import Combine

// MARK: - Pipeline Stage Definition

/// A single stage in a multi-model pipeline.
/// Each stage runs a fresh Claude subprocess with its own model, prompt, and constraints.
struct PipelineStage: Identifiable {
    let id: UUID = UUID()
    let name: String
    let model: AgentModel
    let systemPromptBuilder: (_ priorOutput: String) -> String
    let allowedTools: [String]?
    let maxTurns: Int?
}

// MARK: - Pipeline Stage Status

enum PipelineStageStatus: Equatable {
    case pending
    case running
    case completed(output: String)
    case failed(error: String)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

// MARK: - Pipeline Status

enum PipelineStatus: Equatable {
    case idle
    case running(stageIndex: Int)
    case completed
    case failed(stageIndex: Int, error: String)
}

// MARK: - Pipeline Stage Result

struct PipelineStageResult: Identifiable {
    let id: UUID
    let stageName: String
    let model: AgentModel
    var status: PipelineStageStatus
    var messages: [ChatMessage]
    var inputTokens: Int
    var outputTokens: Int
}

// MARK: - Multi-Model Pipeline

/// Orchestrates a sequence of Claude subprocess stages, each with its own model,
/// system prompt, and tool access. The output of stage N becomes input context
/// for stage N+1. Each stage gets a clean context window.
@MainActor
final class MultiModelPipeline: ObservableObject {

    let chatManager: CLISubprocessManager
    let workingDirectory: String
    let stages: [PipelineStage]

    @Published var status: PipelineStatus = .idle
    @Published var stageResults: [PipelineStageResult] = []
    @Published var currentStageIndex: Int = 0

    /// The active session for the current stage (observable for UI streaming)
    @Published var activeSession: AgentSession?

    private var completionCancellable: AnyCancellable?

    init(
        chatManager: CLISubprocessManager,
        workingDirectory: String,
        stages: [PipelineStage]
    ) {
        self.chatManager = chatManager
        self.workingDirectory = workingDirectory
        self.stages = stages
        self.stageResults = stages.map { stage in
            PipelineStageResult(
                id: stage.id,
                stageName: stage.name,
                model: stage.model,
                status: .pending,
                messages: [],
                inputTokens: 0,
                outputTokens: 0
            )
        }
    }

    // MARK: - Execution

    /// Kick off the pipeline with the user's initial prompt.
    /// The prompt is sent to stage 0; subsequent stages receive prior output.
    func execute(prompt: String) {
        guard !stages.isEmpty else { return }
        status = .running(stageIndex: 0)
        currentStageIndex = 0
        runStage(at: 0, userPrompt: prompt, priorOutput: "")
    }

    /// Cancel the running pipeline.
    func cancel() {
        if let session = activeSession {
            chatManager.cancel(sessionId: session.id)
            chatManager.removeSession(sessionId: session.id)
        }
        activeSession = nil
        completionCancellable?.cancel()
        let idx = currentStageIndex
        if idx < stageResults.count {
            stageResults[idx].status = .failed(error: "Cancelled")
        }
        status = .failed(stageIndex: idx, error: "Cancelled")
    }

    // MARK: - Private

    private func runStage(at index: Int, userPrompt: String, priorOutput: String) {
        guard index < stages.count else {
            status = .completed
            return
        }

        let stage = stages[index]
        currentStageIndex = index
        status = .running(stageIndex: index)
        stageResults[index].status = .running

        let systemPrompt = stage.systemPromptBuilder(priorOutput)

        let session = chatManager.createSession(
            model: stage.model,
            agentMode: nil,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory,
            enableAgentTeams: false,
            disableMcp: true
        )
        session.allowedToolsOverride = stage.allowedTools
        session.maxTurnsOverride = stage.maxTurns
        activeSession = session

        // Register per-session completion handler (doesn't interfere with global callback)
        chatManager.onComplete(sessionId: session.id) { [weak self] _ in
            self?.handleStageCompletion(stageIndex: index, session: session, userPrompt: userPrompt)
        }

        // Build the prompt for this stage
        let stagePrompt: String
        if index == 0 {
            stagePrompt = userPrompt
        } else {
            stagePrompt = "Execute this stage based on the prior context provided in your system prompt."
        }

        chatManager.send(sessionId: session.id, prompt: stagePrompt)
    }

    private func handleStageCompletion(stageIndex: Int, session: AgentSession, userPrompt: String) {
        // Capture values before cleanup
        let output = session.lastAssistantText ?? ""
        let messages = session.messages
        let inputTokens = session.totalInputTokens
        let outputTokens = session.totalOutputTokens
        let sessionStatus = session.status

        // Clean up the session
        chatManager.removeSession(sessionId: session.id)
        activeSession = nil

        // Update stage result
        stageResults[stageIndex].messages = messages
        stageResults[stageIndex].inputTokens = inputTokens
        stageResults[stageIndex].outputTokens = outputTokens

        // Check for error status
        if case .error(let err) = sessionStatus {
            stageResults[stageIndex].status = .failed(error: err)
            status = .failed(stageIndex: stageIndex, error: err)
            return
        }

        stageResults[stageIndex].status = .completed(output: output)

        // Accumulate output for next stage
        let accumulatedOutput = buildAccumulatedOutput(through: stageIndex)

        // Run next stage
        let nextIndex = stageIndex + 1
        if nextIndex < stages.count {
            runStage(at: nextIndex, userPrompt: userPrompt, priorOutput: accumulatedOutput)
        } else {
            status = .completed
        }
    }

    /// Build a combined output summary from all completed stages, for injection
    /// into the next stage's system prompt.
    private func buildAccumulatedOutput(through stageIndex: Int) -> String {
        var parts: [String] = []
        for i in 0...stageIndex {
            if case .completed(let output) = stageResults[i].status, !output.isEmpty {
                parts.append("## Output from \(stageResults[i].stageName) (\(stageResults[i].model.displayName))\n\n\(output)")
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Aggregate Stats

    var totalInputTokens: Int {
        stageResults.reduce(0) { $0 + $1.inputTokens }
    }

    var totalOutputTokens: Int {
        stageResults.reduce(0) { $0 + $1.outputTokens }
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    var formattedTokenCount: String {
        let total = totalTokens
        if total < 1000 { return "\(total)" }
        return String(format: "%.1f", Double(total) / 1000.0) + "k"
    }

    var currentStageName: String? {
        guard case .running(let idx) = status, idx < stages.count else { return nil }
        return stages[idx].name
    }
}

// MARK: - Pipeline Templates

extension MultiModelPipeline {

    /// The standard 3-stage pipeline: Plan (Opus) → Implement (Sonnet) → Review (Opus)
    static func standard(
        chatManager: CLISubprocessManager,
        workingDirectory: String,
        taskName: String,
        branchName: String,
        siblingContext: String = "",
        buildContext: String = ""
    ) -> MultiModelPipeline {
        let stages = [
            PipelineStage(
                name: "Planning",
                model: .opus,
                systemPromptBuilder: { _ in
                    AgentPrompts.pipelinePlanningPrompt(
                        taskName: taskName,
                        branchName: branchName,
                        siblingContext: siblingContext,
                        buildContext: buildContext
                    )
                },
                allowedTools: ["Read", "Glob", "Grep", "WebSearch", "WebFetch"],
                maxTurns: 3
            ),
            PipelineStage(
                name: "Implementation",
                model: .sonnet,
                systemPromptBuilder: { priorOutput in
                    AgentPrompts.pipelineImplementationPrompt(
                        taskName: taskName,
                        branchName: branchName,
                        planOutput: priorOutput
                    )
                },
                allowedTools: ["Read", "Glob", "Grep", "Edit", "Write", "Bash"],
                maxTurns: 15
            ),
            PipelineStage(
                name: "Review",
                model: .opus,
                systemPromptBuilder: { priorOutput in
                    AgentPrompts.pipelineReviewPrompt(
                        taskName: taskName,
                        branchName: branchName,
                        priorOutput: priorOutput,
                        workingDirectory: workingDirectory
                    )
                },
                allowedTools: ["Read", "Glob", "Grep", "Bash"],
                maxTurns: 3
            ),
        ]

        return MultiModelPipeline(
            chatManager: chatManager,
            workingDirectory: workingDirectory,
            stages: stages
        )
    }
}
