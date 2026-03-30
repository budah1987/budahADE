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

// MARK: - ActivityFeedEntry

struct ActivityFeedEntry: Identifiable, Equatable {
    let id: String
    let kind: ActivityKind
    let label: String
    var detail: String?
    let timestamp: Date
    var status: ActivityStatus

    enum ActivityStatus: Equatable {
        case inProgress
        case completed
        case failed
    }
}

enum ActivityKind: Equatable {
    case thinking
    case toolRead(filePath: String)
    case toolGrep(pattern: String)
    case toolGlob(pattern: String)
    case toolBash(command: String)
    case toolEdit(filePath: String)
    case toolWrite(filePath: String)
    case toolAgent(description: String)
    case toolWebSearch(query: String)
    case toolWebFetch(url: String)
    case toolOther(name: String)
    case rateLimit
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
    /// Live activity entries — tool calls in progress and completed
    @Published var activityFeed: [ActivityFeedEntry] = []
    /// Current rate limit status
    @Published var rateLimitStatus: RateLimitInfo?
    /// Whether Claude is in extended thinking
    @Published var isThinking: Bool = false
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
        optionsDismissed = false
    }

    func handleContentDelta(_ text: String) {
        currentStreamingText += text
    }

    /// Available slash commands from the CLI init event.
    @Published var availableCommands: [String] = []

    func handleSystemInit(_ info: StreamEvent.SystemInfo) {
        claudeSessionId = info.sessionId
        if let commands = info.slashCommands {
            availableCommands = commands
        }
    }

    func handleResult(_ result: StreamEvent.ResultInfo) {
        status = .done
        if claudeSessionId == nil, let sessionId = result.sessionId {
            claudeSessionId = sessionId
        }
        // Mark all in-progress activity entries as completed
        for i in activityFeed.indices where activityFeed[i].status == .inProgress {
            activityFeed[i].status = .completed
        }
        isThinking = false
    }

    // MARK: - Activity Feed Handlers

    func handleToolUse(_ event: ToolUseEvent) {
        isThinking = false
        let (label, kind) = activityLabel(for: event)
        let entry = ActivityFeedEntry(
            id: event.id,
            kind: kind,
            label: label,
            detail: nil,
            timestamp: Date(),
            status: .inProgress
        )
        activityFeed.append(entry)
    }

    func handleToolResult(_ event: ToolResultEvent) {
        guard let index = activityFeed.firstIndex(where: { $0.id == event.toolUseId }) else { return }
        activityFeed[index].status = event.isError ? .failed : .completed
        activityFeed[index].detail = summarizeToolResult(event, kind: activityFeed[index].kind)
    }

    func handleThinking(_ text: String) {
        if !isThinking {
            isThinking = true
            let entry = ActivityFeedEntry(
                id: "thinking-\(UUID().uuidString)",
                kind: .thinking,
                label: "Reasoning...",
                detail: nil,
                timestamp: Date(),
                status: .inProgress
            )
            activityFeed.append(entry)
        }
    }

    func handleRateLimit(_ info: RateLimitInfo) {
        rateLimitStatus = info
        if info.status == "throttled" {
            let entry = ActivityFeedEntry(
                id: UUID().uuidString,
                kind: .rateLimit,
                label: "Rate limited — waiting...",
                detail: info.resetsAt,
                timestamp: Date(),
                status: .inProgress
            )
            activityFeed.append(entry)
        }
    }

    private func activityLabel(for event: ToolUseEvent) -> (String, ActivityKind) {
        // Parse specific keys from inputJSON on demand
        let input = parseInputJSON(event.inputJSON)

        switch event.name {
        case "Read":
            let path = input["file_path"] ?? ""
            let filename = (path as NSString).lastPathComponent
            return ("Reading \(filename)", .toolRead(filePath: path))
        case "Grep":
            let pattern = input["pattern"] ?? ""
            return ("Searching for \(pattern)", .toolGrep(pattern: pattern))
        case "Glob":
            let pattern = input["pattern"] ?? ""
            return ("Finding files \(pattern)", .toolGlob(pattern: pattern))
        case "Bash":
            let command = input["command"] ?? ""
            let truncated = String(command.prefix(50))
            return ("Running \(truncated)", .toolBash(command: command))
        case "Edit":
            let path = input["file_path"] ?? ""
            let filename = (path as NSString).lastPathComponent
            return ("Editing \(filename)", .toolEdit(filePath: path))
        case "Write":
            let path = input["file_path"] ?? ""
            let filename = (path as NSString).lastPathComponent
            return ("Writing \(filename)", .toolWrite(filePath: path))
        case "Agent":
            let desc = input["description"] ?? input["prompt"] ?? ""
            let truncated = String(desc.prefix(40))
            return ("Researching: \(truncated)", .toolAgent(description: desc))
        case "WebSearch":
            let query = input["query"] ?? ""
            return ("Searching web: \(query)", .toolWebSearch(query: query))
        case "WebFetch":
            let url = input["url"] ?? ""
            let domain = URL(string: url)?.host ?? url
            return ("Fetching \(domain)", .toolWebFetch(url: url))
        default:
            return ("Using \(event.name)", .toolOther(name: event.name))
        }
    }

    private func parseInputJSON(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in obj {
            if let str = value as? String {
                result[key] = str
            }
        }
        return result
    }

    private func summarizeToolResult(_ event: ToolResultEvent, kind: ActivityKind) -> String {
        if event.isError {
            return String(event.content.prefix(40))
        }
        switch kind {
        case .toolRead:
            let lineCount = event.content.components(separatedBy: "\n").count
            return "\(lineCount) lines"
        case .toolGrep:
            let matchCount = event.content.components(separatedBy: "\n").count
            return "\(matchCount) matches"
        case .toolGlob:
            let fileCount = event.content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
            return "\(fileCount) files"
        case .toolBash:
            let firstLine = event.content.components(separatedBy: "\n").first ?? ""
            return String(firstLine.prefix(40))
        case .toolEdit, .toolWrite, .toolAgent:
            return "done"
        default:
            return String(event.content.prefix(40))
        }
    }

    // MARK: - Interactive Options

    /// Whether option buttons have been dismissed (reset on new assistant message)
    @Published var optionsDismissed: Bool = false

    struct DetectedOption: Identifiable {
        let id: Int
        let label: String
        let text: String
    }

    func detectOptions(in text: String) -> [DetectedOption]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return nil }

        // Check for a question — last non-empty line ends with ?, or contains a question pattern
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let hasQuestion: Bool = {
            if let last = nonEmptyLines.last, last.hasSuffix("?") { return true }
            let questionPattern = try? NSRegularExpression(pattern: "which.*prefer|would you like|should I|do you want|what approach|which option", options: .caseInsensitive)
            return nonEmptyLines.contains { line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return questionPattern?.firstMatch(in: line, range: range) != nil
            }
        }()
        guard hasQuestion else { return nil }

        // Find option lines — numbered, lettered, or bulleted
        let numberedPattern = try! NSRegularExpression(pattern: #"^(\d+)[.)]\s+(.+)$"#)
        let letteredPattern = try! NSRegularExpression(pattern: #"^([A-Za-z])[.)]\s+(.+)$"#)
        let bulletPattern = try! NSRegularExpression(pattern: #"^[-•]\s+\*{0,2}(.+?)\*{0,2}\s*(—.*)?$"#)
        // Bullet + lettered: "• **A) Label** — desc" or "- **B) Label** — desc"
        let bulletLetteredPattern = try! NSRegularExpression(pattern: #"^[-•]\s+\*{0,2}([A-Za-z])[.)]\s*(.+?)\*{0,2}\s*(—.*)?$"#)

        // Track which lines are inside code fences
        var inCodeBlock = false
        var options: [DetectedOption] = []

        for line in lines {
            if line.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let match = numberedPattern.firstMatch(in: line, range: range),
               let labelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText
                ))
            } else if let match = bulletLetteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                // Bullet-prefixed lettered option: "• **A) Label** — desc"
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText
                ))
            } else if let match = letteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText
                ))
            } else if let match = bulletPattern.firstMatch(in: line, range: range),
                      let textRange = Range(match.range(at: 1), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: "\(options.count + 1)",
                    text: rawText
                ))
            }
        }

        // Must have 2-6 options
        guard options.count >= 2 && options.count <= 6 else { return nil }

        return options
    }

    struct DetectedQuestion {
        let contextText: String         // The question + surrounding context
        let options: [DetectedOption]   // May be empty if no formatted options
    }

    /// Detects any question in the last assistant message, with or without options.
    func detectQuestion(in text: String) -> DetectedQuestion? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return nil }

        // Check for a question
        let hasQuestion: Bool = {
            // Last few non-empty lines end with ?
            let tail = nonEmptyLines.suffix(3)
            if tail.contains(where: { $0.hasSuffix("?") }) { return true }
            // Or contains a question pattern
            let questionPattern = try? NSRegularExpression(
                pattern: "which.*prefer|would you like|should I|do you want|what approach|which option|what do you think|how would you|let me know|your thoughts",
                options: .caseInsensitive
            )
            return tail.contains { line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return questionPattern?.firstMatch(in: line, range: range) != nil
            }
        }()
        guard hasQuestion else { return nil }

        // Extract question context — the last paragraph or last few meaningful lines
        let contextLines = extractQuestionContext(from: nonEmptyLines)
        let contextText = contextLines.joined(separator: "\n")

        // Try to detect formatted options (reuse existing logic)
        let options = detectOptions(in: text) ?? []

        return DetectedQuestion(contextText: contextText, options: options)
    }

    /// Extracts the question context — walks backward from the end to find the question paragraph.
    private func extractQuestionContext(from lines: [String]) -> [String] {
        // Walk backward from the end, collecting lines until we hit a blank-line gap
        // or collect up to 6 lines
        var result: [String] = []
        let allLines = lines
        var i = allLines.count - 1
        while i >= 0 && result.count < 6 {
            let line = allLines[i]
            // Stop if we hit a heading or horizontal rule (context boundary)
            if line.hasPrefix("##") || line.hasPrefix("---") { break }
            result.insert(line, at: 0)
            i -= 1
        }
        return result
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
