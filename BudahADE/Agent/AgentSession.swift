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

    /// Approximate context window size in tokens for each model
    var contextWindowTokens: Int {
        switch self {
        case .haiku:    return 200_000
        case .sonnet:   return 200_000
        case .sonnet1m: return 1_000_000
        case .opus:     return 200_000
        }
    }

    /// Whether this model supports fast thinking (via /fast toggle)
    var supportsFastThinking: Bool {
        switch self {
        case .opus: return true
        default:    return false
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

    // MARK: - Cached Regexes (compiled once at class load, not per call)

    private static let questionRegex = try! NSRegularExpression(
        pattern: "which.*prefer|would you like|should I|do you want|what approach|which option",
        options: .caseInsensitive
    )
    private static let numberedRegex = try! NSRegularExpression(
        pattern: #"^(\d+)[.)]\s+(.+)$"#
    )
    private static let letteredRegex = try! NSRegularExpression(
        pattern: #"^([A-Za-z])[.)]\s+(.+)$"#
    )
    private static let bulletLetteredRegex = try! NSRegularExpression(
        pattern: #"^[-•·‣›]\s+\*{0,2}([A-Za-z])[.)]\s*(.+?)\*{0,2}\s*(—.*)?$"#
    )
    private static let optionHeadingRegex = try! NSRegularExpression(
        pattern: #"^(?:#{1,6}\s+|[-•·‣›]\s+|\d+[.)]\s+)?\*{0,2}Option\s+([A-Za-z0-9]+)\s*[:.]\s*\*{0,2}\s*(.+)$"#,
        options: .caseInsensitive
    )
    private static let questionSeriesRegex = try! NSRegularExpression(
        pattern: #"^(\d+)[.)]\s+\*{2}(.+?)\*{2}\s*(.*)$"#
    )
    private static let choicePatternRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "which.*prefer", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "which.*choose", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "which.*option", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "which.*approach", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "what approach", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "what option", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "what would you prefer", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "how would you like to", options: .caseInsensitive),
    ]

    let id: UUID
    var model: AgentModel
    let agentMode: AgentMode?
    let systemPrompt: String
    let workingDirectory: String
    let enableAgentTeams: Bool
    let disableMcp: Bool
    /// Explicit tool restrictions (overrides agentMode.chatAllowedTools when set)
    var allowedToolsOverride: [String]?
    /// Explicit turn limit (overrides agentMode.chatMaxTurns when set)
    var maxTurnsOverride: Int?

    @Published var status: AgentSessionStatus = .idle
    @Published var messages: [ChatMessage] = []
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var claudeSessionId: String?
    @Published var currentStreamingText: String = ""
    /// Stable identifier for the in-progress streaming message. Assigned on the first
    /// content delta, reused when the message finalizes into `messages`, then cleared.
    /// Mid-stream prompt parsing uses this so queued prompts survive the transition
    /// from streaming text → final ChatMessage without duplicating.
    @Published var streamingMessageId: UUID?
    /// Content staged via "Send to" from another agent, awaiting user instruction
    @Published var stagedContent: StagedContent?
    /// Live activity entries — tool calls in progress and completed
    @Published var activityFeed: [ActivityFeedEntry] = []
    /// Current rate limit status
    @Published var rateLimitStatus: RateLimitInfo?
    /// Whether Claude is in extended thinking
    @Published var isThinking: Bool = false
    var process: Process?

    /// Loop detection: tracks repeated edits to the same file
    let loopDetector = LoopDetector()
    /// Tool escalation: surfaces denied tool requests for UI approval
    let toolEscalation = ToolEscalationManager()
    /// Whether this session has already completed a verification pass
    var hasVerified: Bool = false
    /// Whether this session has been marked complete (for adaptive turn limits)
    @Published var isVerifiedComplete: Bool = false
    /// Pending loop warning to inject on next turn (non-view, no @Published needed)
    var pendingLoopWarning: String?
    /// Last result event for cost/trace recording
    var lastResult: StreamEvent.ResultInfo?
    /// Monotonic counter — incremented on any scroll-worthy event (message, streaming text,
    /// activity feed, status change). Views observe this single value instead of 4-5 onChange watchers.
    /// NOT @Published — avoids double objectWillChange. onChange detects it during body re-evaluation
    /// triggered by other @Published changes (currentStreamingText, messages, status, etc).
    var scrollGeneration: UInt = 0

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

    /// Increment scroll generation — signals views to scroll to bottom
    func bumpScroll() { scrollGeneration &+= 1 }

    /// Cache of per-message confirm detection (computed once, reused on every render)
    private var confirmCache: [UUID: Bool] = [:]

    /// Returns whether a message contains a confirmation prompt (marker or regex).
    /// Result is cached — safe to call in ForEach body without per-render cost.
    func cachedHasConfirm(for message: ChatMessage) -> Bool {
        if let cached = confirmCache[message.id] { return cached }
        let markers = parseInteractiveMarkers(in: message.content)
        let hasMarkerConfirm = markers.contains(where: { if case .confirm = $0 { return true }; return false })
        let hasRegexConfirm = detectConfirmation(in: message.content) != nil
        let result = hasMarkerConfirm || hasRegexConfirm
        confirmCache[message.id] = result
        return result
    }

    func addUserMessage(_ content: String, attachments: [DocumentAttachment] = []) {
        // Strip <document> blocks from display when attachments are provided separately
        var displayContent = content
        if !attachments.isEmpty {
            let pattern = #"\n?<document path="[^"]*">\n[\s\S]*?\n</document>"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                displayContent = regex.stringByReplacingMatches(
                    in: displayContent,
                    range: NSRange(location: 0, length: (displayContent as NSString).length),
                    withTemplate: ""
                )
            }
            displayContent = displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let message = ChatMessage(
            role: .user,
            content: displayContent,
            attachments: attachments
        )
        messages.append(message)
        bumpScroll()
    }

    /// Tool calls accumulating during the current turn (before the text response)
    @Published var pendingToolCalls: [ToolCall] = []

    func handleAssistantMessage(_ event: StreamEvent.AssistantMessage) {
        // Flush any buffered streaming text before finalizing
        flushStreamingBuffer()
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
            id: streamingMessageId ?? UUID(),
            role: event.role,
            content: text,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens
        )
        messages.append(message)
        currentStreamingText = ""
        streamingMessageId = nil
        optionsDismissed = false
        confirmDismissed = false
        questionSeriesDismissed = false
        bumpScroll()
    }

    /// Pending streaming text that hasn't been flushed to @Published yet
    private var streamingBuffer: String = ""
    /// Whether a flush is already scheduled
    private var flushScheduled: Bool = false
    /// Throttle interval for streaming text updates (seconds)
    private let streamingFlushInterval: TimeInterval = 0.15

    func handleContentDelta(_ text: String) {
        if streamingMessageId == nil { streamingMessageId = UUID() }
        streamingBuffer += text
        scheduleStreamingFlush()
    }

    /// Batches rapid streaming deltas and flushes at a capped rate.
    /// Reduces objectWillChange invalidations from 30+/sec to ~12/sec.
    private func scheduleStreamingFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + streamingFlushInterval) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            guard !self.streamingBuffer.isEmpty else { return }
            self.currentStreamingText += self.streamingBuffer
            self.streamingBuffer = ""
            self.bumpScroll()
        }
    }

    /// Force-flush any pending streaming text (call before finalizing a message)
    private func flushStreamingBuffer() {
        flushScheduled = false
        guard !streamingBuffer.isEmpty else { return }
        currentStreamingText += streamingBuffer
        streamingBuffer = ""
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
        lastResult = result
        bumpScroll()
        if claudeSessionId == nil, let sessionId = result.sessionId {
            claudeSessionId = sessionId
        }
        // Mark all in-progress activity entries as completed
        for i in activityFeed.indices where activityFeed[i].status == .inProgress {
            activityFeed[i].status = .completed
        }
        isThinking = false

        // Adaptive turn limit: if verification pass completed, mark session as done
        if hasVerified {
            isVerifiedComplete = true
        }
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
        if activityFeed.count > 200 { activityFeed.removeFirst(activityFeed.count - 200) }
        bumpScroll()

        // Loop detection: track edits and flag doom loops
        if let filePath = loopDetector.filePathFromToolEvent(event),
           let warning = loopDetector.recordEdit(filePath: filePath) {
            pendingLoopWarning = warning
        }
    }

    func handleToolResult(_ event: ToolResultEvent) {
        guard let index = activityFeed.firstIndex(where: { $0.id == event.toolUseId }) else { return }
        activityFeed[index].status = event.isError ? .failed : .completed
        activityFeed[index].detail = summarizeToolResult(event, kind: activityFeed[index].kind)

        // Check for tool escalation (agent tried to use a tool it doesn't have)
        if event.isError {
            let toolName: String
            switch activityFeed[index].kind {
            case .toolRead: toolName = "Read"
            case .toolGrep: toolName = "Grep"
            case .toolGlob: toolName = "Glob"
            case .toolBash: toolName = "Bash"
            case .toolEdit: toolName = "Edit"
            case .toolWrite: toolName = "Write"
            case .toolWebSearch: toolName = "WebSearch"
            case .toolWebFetch: toolName = "WebFetch"
            case .toolOther(let name): toolName = name
            default: toolName = "Unknown"
            }
            toolEscalation.checkForEscalation(toolName: toolName, result: event)
        }
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
            if activityFeed.count > 200 { activityFeed.removeFirst(activityFeed.count - 200) }
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
            if activityFeed.count > 200 { activityFeed.removeFirst(activityFeed.count - 200) }
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
    /// Whether the confirmation button has been dismissed (reset on new assistant message)
    @Published var confirmDismissed: Bool = false

    /// Detects if the last assistant message is asking for a simple yes/no confirmation
    /// (not a multi-option question). Returns the question text if detected.
    // MARK: - Question Series Detection

    struct DetectedQuestionItem: Identifiable {
        let id: String
        let question: String        // Bold question text
        let context: String          // Regular text with suggested answers
        let suggestions: [String]    // Parsed answer suggestions from context
    }

    /// Generate a position-based prompt ID from a message ID and block index.
    /// Position is the right primitive for dedup: it survives rephrasing and keeps
    /// the same ID whether parsed mid-stream or from the finalized message.
    nonisolated static func promptId(messageId: UUID, blockIndex: Int) -> String {
        "\(messageId.uuidString):\(blockIndex)"
    }

    /// Detects a numbered series of questions (e.g. "Key Questions" list).
    /// Pattern: `1. **Bold question?** Regular text with Or alternatives`
    /// Also captures continuation lines (non-numbered, non-empty) as additional context.
    func detectQuestionSeries(in text: String) -> [DetectedQuestionItem]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        // First pass: find question header lines and their indices
        var questionIndices: [(index: Int, question: String, inlineContext: String)] = []
        for (idx, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = Self.questionSeriesRegex.firstMatch(in: line, range: range),
                  let questionRange = Range(match.range(at: 2), in: line) else { continue }

            let question = String(line[questionRange]).trimmingCharacters(in: .whitespaces)
            let inlineContext: String
            if let contextRange = Range(match.range(at: 3), in: line) {
                inlineContext = String(line[contextRange]).trimmingCharacters(in: .whitespaces)
            } else {
                inlineContext = ""
            }
            questionIndices.append((idx, question, inlineContext))
        }

        guard questionIndices.count >= 2 else { return nil }

        // Second pass: collect continuation lines between questions as context
        var items: [DetectedQuestionItem] = []
        for (qi, entry) in questionIndices.enumerated() {
            let nextStart = qi + 1 < questionIndices.count ? questionIndices[qi + 1].index : lines.count
            // Gather non-empty continuation lines after the question header
            var contextParts: [String] = []
            if !entry.inlineContext.isEmpty { contextParts.append(entry.inlineContext) }
            for li in (entry.index + 1)..<nextStart {
                let continuationLine = lines[li]
                if !continuationLine.isEmpty { contextParts.append(continuationLine) }
            }
            let fullContext = contextParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestions = parseAnswerSuggestions(from: fullContext)

            items.append(DetectedQuestionItem(
                id: "q-\(qi)",
                question: entry.question,
                context: fullContext,
                suggestions: suggestions
            ))
        }

        return items
    }

    /// Parse answer suggestions from regular text by splitting on "or" boundaries.
    private func parseAnswerSuggestions(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        // Split on " or " / "? Or " / ", or "
        let segments = text
            .replacingOccurrences(of: "? Or ", with: "|||")
            .replacingOccurrences(of: "? or ", with: "|||")
            .replacingOccurrences(of: ", or ", with: "|||")
            .replacingOccurrences(of: " or ", with: "|||")
            .components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { segment -> String in
                // Clean up: remove trailing "?" and leading connectors
                var s = segment
                while s.hasSuffix("?") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
                // Remove leading "do you", "does she", etc. for cleaner option text
                let prefixes = ["do you also want ", "are you ", "is she ", "does she "]
                for prefix in prefixes {
                    if s.lowercased().hasPrefix(prefix) {
                        s = String(s.dropFirst(prefix.count))
                        break
                    }
                }
                return s
            }
            .filter { !$0.isEmpty && $0.count > 3 && $0.count < 200 }

        // Cap at 4 suggestions per question
        return Array(segments.prefix(4))
    }

    /// Whether the message has been dismissed from the question stepper
    @Published var questionSeriesDismissed: Bool = false

    // MARK: - Interactive Marker Parsing

    enum InteractiveBlock {
        case questions([MarkerQuestionItem], question: String?)
        case choice(options: [String], question: String?, recommended: Int?)
        case confirm(question: String?)

        /// The embedded question text from the QUESTION: attribute
        var question: String? {
            switch self {
            case .questions(_, let q): return q
            case .choice(_, let q, _): return q
            case .confirm(let q): return q
            }
        }

        /// The recommended option index (1-indexed) for choice blocks
        var recommended: Int? {
            if case .choice(_, _, let r) = self { return r }
            return nil
        }

        /// Convert this interactive block to a structured `QueuedPrompt` for the unified queue.
        /// - Parameters:
        ///   - messageId: Stable id of the source message (mid-stream or finalized).
        ///   - blockIndex: Position of this block within `parseInteractiveMarkers` output.
        ///   - context: Prose preceding the marker (from `questionBeforeMarker`).
        ///   - isSpecReady: Whether the enclosing message reads as a spec (for choice approve flow).
        func asQueuedPrompt(
            messageId: UUID,
            blockIndex: Int,
            context: String,
            isSpecReady: Bool
        ) -> QueuedPrompt {
            let id = AgentSession.promptId(messageId: messageId, blockIndex: blockIndex)
            switch self {
            case .confirm(let q):
                return QueuedPrompt(
                    id: id,
                    messageId: messageId,
                    blockIndex: blockIndex,
                    kind: .confirm,
                    question: q ?? "Proceed?",
                    context: context
                )
            case .choice(let options, let q, let recommended):
                let choiceOptions = options.enumerated().map { idx, raw -> QueuedPrompt.ChoiceOption in
                    let parts = raw.components(separatedBy: " — ")
                    let text = (parts.first ?? raw).trimmingCharacters(in: .whitespaces)
                    let description = parts.count > 1
                        ? parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces)
                        : ""
                    return QueuedPrompt.ChoiceOption(id: idx, text: text, description: description)
                }
                // Marker uses 1-indexed RECOMMENDED:N, QueuedPrompt stores 0-indexed.
                let recIdx: Int? = recommended.flatMap { $0 > 0 ? $0 - 1 : nil }
                return QueuedPrompt(
                    id: id,
                    messageId: messageId,
                    blockIndex: blockIndex,
                    kind: .choice(options: choiceOptions, recommendedIndex: recIdx, isSpecReady: isSpecReady),
                    question: q ?? "Choose an option",
                    context: context
                )
            case .questions(let items, let q):
                if items.count == 1, let only = items.first {
                    return QueuedPrompt(
                        id: id,
                        messageId: messageId,
                        blockIndex: blockIndex,
                        kind: .question(suggestions: only.options),
                        question: only.question,
                        context: only.context.isEmpty ? context : only.context
                    )
                }
                let sub = items.enumerated().map { idx, item in
                    QueuedPrompt.SubQuestion(
                        id: "\(id).\(idx)",
                        question: item.question,
                        context: item.context,
                        suggestions: item.options
                    )
                }
                return QueuedPrompt(
                    id: id,
                    messageId: messageId,
                    blockIndex: blockIndex,
                    kind: .questionSeries(sub),
                    question: q ?? (items.first?.question ?? "Questions"),
                    context: context
                )
            }
        }
    }

    // MARK: - QueuedPrompt

    /// Structured prompt in the unified queue. Each renderer (confirm/choice/question/stepper)
    /// draws the same data in its own shape — confirms stay as confirms, choices keep their
    /// recommended index and approve-and-build affordance, steppers only appear when count >= 2.
    struct QueuedPrompt: Identifiable, Equatable {
        let id: String              // "messageId:blockIndex" — stable across re-parses
        let messageId: UUID
        let blockIndex: Int
        let kind: Kind
        let question: String        // The main question text (from QUESTION: attribute or bold line)
        let context: String         // Prose context preceding the marker, if any

        enum Kind: Equatable {
            case confirm
            case choice(options: [ChoiceOption], recommendedIndex: Int?, isSpecReady: Bool)
            case question(suggestions: [String])
            case questionSeries([SubQuestion])
        }

        struct ChoiceOption: Equatable, Identifiable {
            let id: Int
            let text: String         // Primary label (before " — ")
            let description: String  // Secondary detail (after " — "), may be empty
        }

        struct SubQuestion: Equatable, Identifiable {
            let id: String
            let question: String
            let context: String
            let suggestions: [String]
        }
    }

    /// Build a `QueuedPrompt` from a regex-detected question series. Used by the fallback
    /// path in PlanChatView when no interactive markers are present. Block index is `-1`
    /// to distinguish it from marker-based prompts in the same message.
    nonisolated static func queuedPromptFromRegexSeries(
        _ items: [DetectedQuestionItem],
        messageId: UUID
    ) -> QueuedPrompt {
        let id = promptId(messageId: messageId, blockIndex: -1)
        let sub = items.enumerated().map { idx, item in
            QueuedPrompt.SubQuestion(
                id: "\(id).\(idx)",
                question: item.question,
                context: item.context,
                suggestions: item.suggestions
            )
        }
        return QueuedPrompt(
            id: id,
            messageId: messageId,
            blockIndex: -1,
            kind: .questionSeries(sub),
            question: items.first?.question ?? "Questions",
            context: ""
        )
    }

    /// Parse QUESTION: and RECOMMENDED: attributes from the interactive marker opening tag.
    /// Attributes are order-independent: `QUESTION:text RECOMMENDED:1` or `RECOMMENDED:1 QUESTION:text`.
    private static func parseMarkerAttributes(_ raw: String) -> (question: String?, recommended: Int?) {
        // Extract RECOMMENDED first (simpler, always a single number)
        let recommended = raw.firstMatch(of: /RECOMMENDED:(\d+)/).flatMap { Int(String($0.1)) }

        // Extract QUESTION — strip any other known attribute keys, take the rest
        var question: String?
        if let qRange = raw.range(of: "QUESTION:") {
            var value = String(raw[qRange.upperBound...])
            // Remove any trailing RECOMMENDED:N that might be embedded
            value = value.replacing(/\s*RECOMMENDED:\d+/, with: "")
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { question = trimmed }
        }

        return (question, recommended)
    }

    struct MarkerQuestionItem {
        let question: String
        let context: String    // Non-bold, non-option lines between question and next question/options
        let options: [String]
    }

    // Regex patterns for interactive markers
    private static let interactiveOpenPattern = /<!-- INTERACTIVE:(questions|choice|confirm)(.*?) -->/
    private static let interactiveClosePattern = /<!-- \/INTERACTIVE -->/
    private static let optionMarkerPattern = /<!-- OPTION:(.+?) -->/
    private static let boldLinePattern = /\*\*(.+?)\*\*/

    /// Parse interactive markers from agent response text.
    /// Returns an array of blocks (usually 0 or 1, but a message may contain multiple).
    func parseInteractiveMarkers(in text: String) -> [InteractiveBlock] {
        var blocks: [InteractiveBlock] = []
        let lines = text.components(separatedBy: "\n")

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Look for opening marker
            if let match = line.firstMatch(of: Self.interactiveOpenPattern) {
                let type = String(match.1)
                let attrs = Self.parseMarkerAttributes(String(match.2))

                // Collect lines until closing marker
                var blockLines: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i].trimmingCharacters(in: .whitespaces)
                    if inner.contains("<!-- /INTERACTIVE -->") { break }
                    blockLines.append(inner)
                    i += 1
                }

                switch type {
                case "confirm":
                    blocks.append(.confirm(question: attrs.question))
                case "choice":
                    let options = blockLines.compactMap { l -> String? in
                        guard let m = l.firstMatch(of: Self.optionMarkerPattern) else { return nil }
                        return String(m.1)
                    }
                    if !options.isEmpty {
                        blocks.append(.choice(options: options, question: attrs.question, recommended: attrs.recommended))
                    }
                case "questions":
                    var items: [MarkerQuestionItem] = []
                    var currentQuestion: String?
                    var currentContext: [String] = []
                    var currentOptions: [String] = []

                    for bl in blockLines {
                        if let qMatch = bl.firstMatch(of: Self.boldLinePattern) {
                            // Save previous question group
                            if let q = currentQuestion {
                                items.append(MarkerQuestionItem(
                                    question: q,
                                    context: currentContext.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                                    options: currentOptions
                                ))
                            }
                            currentQuestion = String(qMatch.1)
                            currentContext = []
                            currentOptions = []
                        } else if let oMatch = bl.firstMatch(of: Self.optionMarkerPattern) {
                            currentOptions.append(String(oMatch.1))
                        } else if !bl.isEmpty && currentQuestion != nil {
                            // Non-bold, non-option line → context
                            currentContext.append(bl)
                        }
                    }
                    // Save last question group
                    if let q = currentQuestion {
                        items.append(MarkerQuestionItem(
                            question: q,
                            context: currentContext.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                            options: currentOptions
                        ))
                    }
                    if !items.isEmpty {
                        blocks.append(.questions(items, question: attrs.question))
                    }
                default:
                    break
                }
            }
            i += 1
        }

        return blocks
    }

    /// Extract the question text immediately preceding the first interactive marker block.
    /// Falls back to `detectQuestion` if no marker is found.
    func questionBeforeMarker(in text: String) -> String {
        // Find the first <!-- INTERACTIVE: marker
        guard let markerRange = text.range(of: "<!-- INTERACTIVE:", options: []) else {
            return detectQuestion(in: text)?.contextText ?? ""
        }

        // Get text before the marker, walk backward to find the question paragraph
        let before = String(text[text.startIndex..<markerRange.lowerBound])
        let lines = before.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Take the last few meaningful lines (up to 4) as the question context
        let contextLines = Array(lines.suffix(4))
        return contextLines.joined(separator: "\n")
    }

    /// Check if the last interactive block in the text was followed by a substantive response
    /// (indicating the agent answered its own question). Returns true if self-answered.
    func isLastBlockSelfAnswered(in text: String) -> Bool {
        // Find the last <!-- /INTERACTIVE --> marker
        guard let closeRange = text.range(of: "<!-- /INTERACTIVE -->", options: .backwards) else {
            return false
        }
        let afterClose = text[closeRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // If there's substantial text after the last close marker, agent answered itself
        // Threshold: more than 40 chars of non-whitespace content = substantive answer
        return afterClose.count > 40
    }

    /// Strip all interactive markers from text for clean display/storage.
    static func stripInteractiveMarkers(from text: String) -> String {
        var result = text
        // Remove INTERACTIVE open/close and OPTION markers
        let patterns: [Regex<AnyRegexOutput>] = [
            try! Regex(#"<!-- INTERACTIVE:\w+ -->"#),
            try! Regex(#"<!-- /INTERACTIVE -->"#),
            try! Regex(#"<!-- OPTION:.+? -->"#),
        ]
        for pattern in patterns {
            result = result.replacing(pattern, with: "")
        }
        // Clean up extra blank lines left by removal
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }

    func detectConfirmation(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmpty = lines.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        // Find the last line that ends with "?"
        guard let lastQuestion = nonEmpty.last(where: { $0.hasSuffix("?") }) else {
            // Also check for "if yes" / "if so" patterns without a question mark
            let tail = nonEmpty.suffix(3).joined(separator: " ").lowercased()
            let implicitConfirm = ["if yes", "if so", "ready to proceed", "ready to move on"]
            guard implicitConfirm.contains(where: { tail.contains($0) }) else { return nil }
            return nonEmpty.suffix(2).joined(separator: " ")
        }

        let q = lastQuestion.lowercased()
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")

        // Exclude questions that ask the user to CHOOSE between options
        // These are multi-choice and should get the option modal instead
        let qRange = NSRange(q.startIndex..<q.endIndex, in: q)
        for regex in Self.choicePatternRegexes {
            if regex.firstMatch(in: q, range: qRange) != nil {
                return nil
            }
        }

        // Exclude messages with a question series — those get the stepper modal
        if detectQuestionSeries(in: text) != nil { return nil }

        // Any remaining question ending in "?" is a confirmation/yes-no question
        return nonEmpty.suffix(2).joined(separator: " ")
    }

    struct DetectedOption: Identifiable {
        let id: Int
        let label: String
        let text: String
        let description: String  // Sub-lines between headings (pros/cons/description). Empty = compact variant.
    }

    func detectOptions(in text: String) -> [DetectedOption]? {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return nil }

        // Check for a question — last non-empty line ends with ?, or contains a question pattern
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let hasQuestion: Bool = {
            if let last = nonEmptyLines.last, last.hasSuffix("?") { return true }
            return nonEmptyLines.contains { line in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return Self.questionRegex.firstMatch(in: line, range: range) != nil
            }
        }()
        guard hasQuestion else {
            return nil
        }

        // Confirmation questions trump option detection — if the tail matches
        // a confirm pattern, the AI is asking for validation, not a choice.
        if detectConfirmation(in: text) != nil { return nil }

        // Find option lines — numbered, lettered, or explicit option headings
        let numberedPattern = Self.numberedRegex
        let letteredPattern = Self.letteredRegex
        let bulletLetteredPattern = Self.bulletLetteredRegex
        let optionHeadingPattern = Self.optionHeadingRegex

        // Track which lines are inside code fences
        var inCodeBlock = false
        var options: [DetectedOption] = []
        var foundOptionHeadings = false
        var headingIndices: [Int] = []

        // First pass: check if "Option N:" headings exist — if so, only use those
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if optionHeadingPattern.firstMatch(in: line, range: range) != nil {
                foundOptionHeadings = true
                break
            }
        }

        for (lineIdx, line) in lines.enumerated() {
            if line.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let match = optionHeadingPattern.firstMatch(in: line, range: range),
               let labelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                // "Option 1: Auth-as-a-Service" or "**Option 2:** OAuth"
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                headingIndices.append(lineIdx)
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if foundOptionHeadings {
                // Skip other patterns when Option headings are the structure
                continue
            } else if let match = numberedPattern.firstMatch(in: line, range: range),
               let labelRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if let match = bulletLetteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            } else if let match = letteredPattern.firstMatch(in: line, range: range),
                      let labelRange = Range(match.range(at: 1), in: line),
                      let textRange = Range(match.range(at: 2), in: line) {
                let rawText = String(line[textRange]).replacingOccurrences(of: "**", with: "")
                options.append(DetectedOption(
                    id: options.count,
                    label: String(line[labelRange]),
                    text: rawText,
                    description: ""
                ))
            }
        }

        // Second pass: collect description lines between option headings
        if foundOptionHeadings && !headingIndices.isEmpty {
            for (i, headingIdx) in headingIndices.enumerated() {
                let nextBound = (i + 1 < headingIndices.count) ? headingIndices[i + 1] : lines.count
                var descLines: [String] = []
                for lineIdx in (headingIdx + 1)..<nextBound {
                    let l = lines[lineIdx]
                    guard !l.isEmpty else { continue }
                    // Skip the question line (last non-empty line) — it's not part of a description
                    if l.hasSuffix("?") && lineIdx >= lines.count - 3 { continue }
                    // Clean markdown markers
                    let cleaned = l.replacingOccurrences(of: "**", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty {
                        // Strip leading bullet markers for cleaner display
                        var c = cleaned
                        for prefix in ["- ", "• ", "· ", "‣ ", "› "] {
                            if c.hasPrefix(prefix) { c = String(c.dropFirst(prefix.count)); break }
                        }
                        descLines.append(c)
                    }
                }
                if !descLines.isEmpty && i < options.count {
                    let desc = descLines.joined(separator: "\n")
                    options[i] = DetectedOption(
                        id: options[i].id,
                        label: options[i].label,
                        text: options[i].text,
                        description: desc
                    )
                }
            }
        }

        // Must have 2-6 options
        guard options.count >= 2 && options.count <= 6 else {
            return nil
        }

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

    // MARK: - Token Formatting & Context Window Tracking

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

    /// Fraction of the model's context window consumed (0.0–1.0), based on cumulative input tokens.
    /// Input tokens reflect the growing conversation context sent to the model each turn.
    var contextUtilization: Double {
        let limit = model.contextWindowTokens
        guard limit > 0 else { return 0 }
        return min(Double(totalInputTokens) / Double(limit), 1.0)
    }

    /// True when context usage exceeds 75% of the model's window
    var isContextWindowHigh: Bool {
        contextUtilization > 0.75
    }

    /// Human-readable context utilization string (e.g., "42% of 200k")
    var formattedContextUtilization: String {
        let pct = Int(contextUtilization * 100)
        let windowK = model.contextWindowTokens / 1000
        return "\(pct)% of \(windowK)k"
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
