import Foundation

// MARK: - MessageRole

enum MessageRole: String, Codable, Equatable {
    case user
    case assistant
    case system
}

// MARK: - ToolCall

struct ToolCall: Equatable, Codable {
    let id: String
    let name: String
    let input: String // raw JSON
}

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let toolCalls: [ToolCall]?
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        timestamp: Date = Date(),
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - StreamEvent

// MARK: - New Event Structs

struct ToolUseEvent: Equatable {
    let id: String
    let name: String
    let inputJSON: String  // Raw JSON string — parse specific keys on demand
}

struct ToolResultEvent: Equatable {
    let toolUseId: String
    let content: String
    let isError: Bool
}

struct RateLimitInfo: Equatable {
    let status: String
    let resetsAt: String?
    let rateLimitType: String?
}

struct HookEvent: Equatable {
    let hookId: String
    let hookName: String
    let hookEvent: String
}

// MARK: - StreamEvent

enum StreamEvent: Equatable {
    case system(SystemInfo)
    case assistant(AssistantMessage)
    case contentDelta(String)
    case result(ResultInfo)
    case toolUse(ToolUseEvent)
    case toolResult(ToolResultEvent)
    case thinking(String)
    case rateLimitEvent(RateLimitInfo)
    case hookStarted(HookEvent)
    case hookResponse(HookEvent)
    case unknown

    var debugLabel: String {
        switch self {
        case .system: return "system"
        case .assistant: return "assistant"
        case .contentDelta: return "contentDelta"
        case .result: return "result"
        case .toolUse: return "toolUse"
        case .toolResult: return "toolResult"
        case .thinking: return "thinking"
        case .rateLimitEvent: return "rateLimitEvent"
        case .hookStarted: return "hookStarted"
        case .hookResponse: return "hookResponse"
        case .unknown: return "unknown"
        }
    }

    struct SystemInfo: Equatable, Codable {
        let sessionId: String
        let tools: [String]?
        let model: String?
        let slashCommands: [String]?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case tools
            case model
            case slashCommands = "slash_commands"
        }
    }

    struct AssistantMessage: Equatable, Codable {
        let content: String
        let role: MessageRole
        let toolCalls: [ToolCall]?
        let inputTokens: Int
        let outputTokens: Int
        let model: String?

        enum CodingKeys: String, CodingKey {
            case content, role, toolCalls, inputTokens, outputTokens, model
        }

        init(content: String, role: MessageRole, toolCalls: [ToolCall]? = nil, inputTokens: Int = 0, outputTokens: Int = 0, model: String? = nil) {
            self.content = content
            self.role = role
            self.toolCalls = toolCalls
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.model = model
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.role = try container.decode(MessageRole.self, forKey: .role)
            self.model = try container.decodeIfPresent(String.self, forKey: .model)
            self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(content, forKey: .content)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            try container.encode(inputTokens, forKey: .inputTokens)
            try container.encode(outputTokens, forKey: .outputTokens)
            try container.encodeIfPresent(model, forKey: .model)
        }
    }

    struct ResultInfo: Equatable, Codable {
        let costUSD: Double
        let durationMs: Int?
        let durationApiMs: Int?
        let sessionId: String?
        let numTurns: Int?
        let stopReason: String?
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case costUSD = "total_cost_usd"
            case durationMs = "duration_ms"
            case durationApiMs = "duration_api_ms"
            case sessionId = "session_id"
            case numTurns = "num_turns"
            case stopReason = "stop_reason"
            case inputTokens, outputTokens
        }

        init(costUSD: Double, durationMs: Int? = nil, durationApiMs: Int? = nil, sessionId: String? = nil, numTurns: Int? = nil, stopReason: String? = nil, inputTokens: Int = 0, outputTokens: Int = 0) {
            self.costUSD = costUSD
            self.durationMs = durationMs
            self.durationApiMs = durationApiMs
            self.sessionId = sessionId
            self.numTurns = numTurns
            self.stopReason = stopReason
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.costUSD = try container.decode(Double.self, forKey: .costUSD)
            self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
            self.durationApiMs = try container.decodeIfPresent(Int.self, forKey: .durationApiMs)
            self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            self.numTurns = try container.decodeIfPresent(Int.self, forKey: .numTurns)
            self.stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)

            // Parse usage object
            let usage = try container.nestedContainer(keyedBy: UsageCodingKeys.self, forKey: .inputTokens)
            self.inputTokens = try usage.decode(Int.self, forKey: .inputTokens)
            self.outputTokens = try usage.decode(Int.self, forKey: .outputTokens)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(costUSD, forKey: .costUSD)
            try container.encodeIfPresent(durationMs, forKey: .durationMs)
            try container.encodeIfPresent(durationApiMs, forKey: .durationApiMs)
            try container.encodeIfPresent(sessionId, forKey: .sessionId)
            try container.encodeIfPresent(numTurns, forKey: .numTurns)
            try container.encodeIfPresent(stopReason, forKey: .stopReason)

            var usage = container.nestedContainer(keyedBy: UsageCodingKeys.self, forKey: .inputTokens)
            try usage.encode(inputTokens, forKey: .inputTokens)
            try usage.encode(outputTokens, forKey: .outputTokens)
        }

        enum UsageCodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    static func parse(from json: String) throws -> StreamEvent {
        let data = json.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()

        do {
            let decoded = try decoder.decode([String: AnyCodable].self, from: data)

            guard let typeStr = decoded["type"]?.stringValue else {
                throw StreamParseError.missingType
            }

            switch typeStr {
            case "system":
                // Check subtype for hooks vs init
                let subtype = decoded["subtype"]?.stringValue
                if subtype == "hook_started" || subtype == "hook_response" {
                    let hook = HookEvent(
                        hookId: decoded["hook_id"]?.stringValue ?? "",
                        hookName: decoded["hook_name"]?.stringValue ?? "",
                        hookEvent: decoded["hook_event"]?.stringValue ?? ""
                    )
                    return subtype == "hook_started" ? .hookStarted(hook) : .hookResponse(hook)
                }
                let info = SystemInfo(
                    sessionId: decoded["session_id"]?.stringValue ?? "",
                    tools: decoded["tools"]?.arrayValue?.compactMap { $0.stringValue },
                    model: decoded["model"]?.stringValue,
                    slashCommands: decoded["slash_commands"]?.arrayValue?.compactMap { $0.stringValue }
                )
                return .system(info)

            case "assistant":
                guard let messageObj = decoded["message"]?.objectValue else {
                    throw StreamParseError.invalidData
                }

                var textContent = ""
                var toolCalls: [ToolCall]?
                var toolUseEvents: [ToolUseEvent] = []
                var thinkingText = ""

                if let contentArray = messageObj["content"]?.arrayValue {
                    var tools: [ToolCall] = []

                    for item in contentArray {
                        guard let itemObj = item.objectValue else { continue }
                        let blockType = itemObj["type"]?.stringValue

                        if blockType == "text" {
                            if let text = itemObj["text"]?.stringValue {
                                if !textContent.isEmpty { textContent += "\n" }
                                textContent += text
                            }
                        } else if blockType == "tool_use" {
                            if let id = itemObj["id"]?.stringValue,
                               let name = itemObj["name"]?.stringValue {
                                let inputObj = itemObj["input"] ?? AnyCodable(value: [:] as [String: String])
                                let inputStr = try formatJSON(inputObj)
                                tools.append(ToolCall(id: id, name: name, input: inputStr))
                                toolUseEvents.append(ToolUseEvent(id: id, name: name, inputJSON: inputStr))
                            }
                        } else if blockType == "thinking" {
                            if let text = itemObj["thinking"]?.stringValue {
                                thinkingText += text
                            }
                        }
                    }

                    if !tools.isEmpty { toolCalls = tools }
                }

                let usage = messageObj["usage"]?.objectValue ?? [:]
                let inputTokens = usage["input_tokens"]?.intValue ?? 0
                let outputTokens = usage["output_tokens"]?.intValue ?? 0
                let role = MessageRole(rawValue: messageObj["role"]?.stringValue ?? "assistant") ?? .assistant
                let model = messageObj["model"]?.stringValue

                let assistantMsg = AssistantMessage(
                    content: textContent,
                    role: role,
                    toolCalls: toolCalls,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    model: model
                )
                // Note: toolUseEvents and thinkingText are emitted separately
                // by processStreamLine after handling the assistant message
                return .assistant(assistantMsg)

            case "user":
                // Tool result events
                if let contentArray = decoded["content"]?.arrayValue {
                    for item in contentArray {
                        guard let itemObj = item.objectValue else { continue }
                        if itemObj["type"]?.stringValue == "tool_result" {
                            let toolUseId = itemObj["tool_use_id"]?.stringValue ?? ""
                            let isError = itemObj["is_error"]?.boolValue ?? false
                            // Content can be string or array of blocks
                            let content: String
                            if let str = itemObj["content"]?.stringValue {
                                content = str
                            } else if let arr = itemObj["content"]?.arrayValue {
                                content = arr.compactMap { block in
                                    block.objectValue?["text"]?.stringValue
                                }.joined(separator: "\n")
                            } else {
                                content = ""
                            }
                            return .toolResult(ToolResultEvent(
                                toolUseId: toolUseId, content: content, isError: isError
                            ))
                        }
                    }
                }
                return .unknown

            case "content_block_delta":
                guard let delta = decoded["delta"]?.objectValue else {
                    throw StreamParseError.invalidData
                }
                let deltaType = delta["type"]?.stringValue ?? ""
                if deltaType == "thinking_delta" {
                    let text = delta["thinking"]?.stringValue ?? ""
                    return .thinking(text)
                }
                let text = delta["text"]?.stringValue ?? ""
                return .contentDelta(text)

            case "rate_limit_event":
                let info = RateLimitInfo(
                    status: decoded["status"]?.stringValue ?? "",
                    resetsAt: decoded["resets_at"]?.stringValue,
                    rateLimitType: decoded["rate_limit_type"]?.stringValue
                )
                return .rateLimitEvent(info)

            case "result":
                let costUSD = decoded["total_cost_usd"]?.doubleValue ?? decoded["cost_usd"]?.doubleValue ?? 0.0
                let durationMs = decoded["duration_ms"]?.intValue
                let durationApiMs = decoded["duration_api_ms"]?.intValue
                let sessionId = decoded["session_id"]?.stringValue
                let numTurns = decoded["num_turns"]?.intValue
                let stopReason = decoded["stop_reason"]?.stringValue

                let usage = decoded["usage"]?.objectValue ?? [:]
                let inputTokens = usage["input_tokens"]?.intValue ?? 0
                let outputTokens = usage["output_tokens"]?.intValue ?? 0

                let resultInfo = ResultInfo(
                    costUSD: costUSD,
                    durationMs: durationMs,
                    durationApiMs: durationApiMs,
                    sessionId: sessionId,
                    numTurns: numTurns,
                    stopReason: stopReason,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                )
                return .result(resultInfo)

            default:
                return .unknown
            }
        } catch let error as StreamParseError {
            throw error
        } catch is DecodingError {
            throw StreamParseError.invalidJSON
        } catch {
            throw StreamParseError.invalidData
        }
    }

    private static func formatJSON(_ codable: AnyCodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(codable)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - StreamParseError

enum StreamParseError: Error, Equatable {
    case invalidData
    case invalidJSON
    case missingType
}

// MARK: - AnyCodable Helper

enum AnyCodable: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(value: Any) {
        if value is NSNull {
            self = .null
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let string = value as? String {
            self = .string(string)
        } else if let array = value as? [Any] {
            self = .array(array.map { AnyCodable(value: $0) })
        } else if let dict = value as? [String: Any] {
            self = .object(dict.mapValues { AnyCodable(value: $0) })
        } else {
            self = .null
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .double(let value) = self else { return nil }
        return value
    }

    var arrayValue: [AnyCodable]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: AnyCodable]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
