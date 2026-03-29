import Foundation

// MARK: - AgentModel Enum

enum AgentModel: String, CaseIterable, Identifiable, Codable {
    case haiku
    case sonnet
    case sonnet1m
    case opus

    var id: String { rawValue }

    var cliFlag: String {
        switch self {
        case .haiku:    return "haiku"
        case .sonnet:   return "sonnet"
        case .sonnet1m: return "sonnet" // TODO: update when Claude CLI exposes 1m-context model ID
        case .opus:     return "opus"
        }
    }

    var displayName: String {
        switch self {
        case .haiku:    return "Haiku"
        case .sonnet:   return "Sonnet"
        case .sonnet1m: return "Sonnet (1m context)"
        case .opus:     return "Opus 4.6"
        }
    }
}

// MARK: - AgentSessionStatus Enum

enum AgentSessionStatus: Equatable {
    case idle
    case connecting  // Subprocess launched, awaiting first output
    case streaming
    case done
    case error(String)
}

// MARK: - AgentSession Class

@MainActor
final class AgentSession: ObservableObject, Identifiable {
    let id: UUID
    var model: AgentModel
    let agentMode: AgentMode?
    let systemPrompt: String
    let workingDirectory: String
    let enableAgentTeams: Bool
    let disableMcp: Bool

    @Published var status: AgentSessionStatus = .idle
    @Published var messages: [ChatMessage] = []
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var claudeSessionId: String?
    @Published var currentStreamingText: String = ""
    /// Content staged via "Send to" from another agent, awaiting user instruction
    @Published var stagedContent: StagedContent?
    var process: Process?

    struct StagedContent {
        let content: String
        let fromAgent: String
    }

    init(
        id: UUID = UUID(),
        model: AgentModel,
        agentMode: AgentMode?,
        systemPrompt: String,
        workingDirectory: String,
        enableAgentTeams: Bool = false,
        disableMcp: Bool = false
    ) {
        self.id = id
        self.model = model
        self.agentMode = agentMode
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
        self.enableAgentTeams = enableAgentTeams
        self.disableMcp = disableMcp
    }

    // MARK: - Message Handling

    func addUserMessage(_ content: String) {
        let message = ChatMessage(
            role: .user,
            content: content
        )
        messages.append(message)
    }

    /// Tool calls accumulating during the current turn (before the text response)
    @Published var pendingToolCalls: [ToolCall] = []

    func handleAssistantMessage(_ event: StreamEvent.AssistantMessage) {
        // Use streamed text if the event content is empty (deltas accumulated it)
        let text = event.content.isEmpty ? currentStreamingText : event.content

        // Always track tokens
        totalInputTokens += event.inputTokens
        totalOutputTokens += event.outputTokens

        // Tool-only messages: accumulate into pendingToolCalls, don't create a bubble
        if text.isEmpty && event.toolCalls != nil {
            pendingToolCalls.append(contentsOf: event.toolCalls ?? [])
            return
        }

        // Skip completely empty messages (no text, no tools)
        guard !text.isEmpty else { return }

        // Real text response — flush pending tool calls as a single collapsible message,
        // then add the text message
        if !pendingToolCalls.isEmpty {
            let toolMessage = ChatMessage(
                role: .assistant,
                content: "",
                toolCalls: pendingToolCalls
            )
            messages.append(toolMessage)
            pendingToolCalls = []
        }

        let message = ChatMessage(
            role: event.role,
            content: text,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens
        )
        messages.append(message)
        currentStreamingText = ""
    }

    func handleContentDelta(_ text: String) {
        currentStreamingText += text
    }

    func handleSystemInit(_ info: StreamEvent.SystemInfo) {
        claudeSessionId = info.sessionId
    }

    func handleResult(_ result: StreamEvent.ResultInfo) {
        status = .done
        if claudeSessionId == nil, let sessionId = result.sessionId {
            claudeSessionId = sessionId
        }
    }

    // MARK: - Token Formatting

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    var formattedTokenCount: String {
        let total = totalTokens
        if total < 1000 {
            return "\(total)"
        } else {
            let formatted = Double(total) / 1000.0
            return String(format: "%.1f", formatted) + "k"
        }
    }

    // MARK: - Auto-Forward Support

    /// The last assistant text message (skipping tool-only messages)
    var lastAssistantText: String? {
        messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.content
    }

    /// Whether the last response is worth auto-forwarding to downstream tiles
    var lastResponseIsSubstantive: Bool {
        guard let text = lastAssistantText else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short — likely an acknowledgment
        if trimmed.count < 80 { return false }

        // Has structure (headers, code blocks, lists) — always substantive
        let hasStructure = trimmed.contains("## ")
            || trimmed.contains("```")
            || trimmed.contains("\n- ")
            || trimmed.contains("\n* ")
            || trimmed.contains("\n1. ")
        if hasStructure && trimmed.count > 150 { return true }

        // Long enough to be a real result
        if trimmed.count > 300 { return true }

        // Ends with a question — likely asking for clarification, not a result
        if trimmed.hasSuffix("?") { return false }

        return trimmed.count > 150
    }
}
