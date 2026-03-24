import Foundation

// MARK: - AgentModel Enum

enum AgentModel: String, CaseIterable, Identifiable, Codable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }

    var cliFlag: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku:
            return "Haiku"
        case .sonnet:
            return "Sonnet"
        case .opus:
            return "Opus"
        }
    }
}

// MARK: - AgentSessionStatus Enum

enum AgentSessionStatus: Equatable {
    case idle
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
        workingDirectory: String
    ) {
        self.id = id
        self.model = model
        self.agentMode = agentMode
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
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
}
