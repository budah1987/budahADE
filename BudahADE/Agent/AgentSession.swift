import Foundation

// MARK: - AgentModel Enum

enum AgentModel: String, CaseIterable, Identifiable {
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
    var process: Process?

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

    func handleAssistantMessage(_ event: StreamEvent.AssistantMessage) {
        let message = ChatMessage(
            role: event.role,
            content: event.content,
            toolCalls: event.toolCalls,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens
        )
        messages.append(message)
        totalInputTokens += event.inputTokens
        totalOutputTokens += event.outputTokens
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
