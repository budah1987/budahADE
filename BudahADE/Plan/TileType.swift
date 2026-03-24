import SwiftUI

// MARK: - Agent Mode

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case claude
    case researcher
    case ideator
    case developer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:     return "Claude"
        case .researcher: return "Researcher"
        case .ideator:    return "Ideator"
        case .developer:  return "Developer"
        }
    }

    var description: String {
        switch self {
        case .claude:     return "General agent"
        case .researcher: return "Investigate, analyze, synthesize"
        case .ideator:    return "Product thinking, problem discovery"
        case .developer:  return "Technical feasibility, architecture"
        }
    }

    var iconName: String {
        switch self {
        case .claude:     return "sparkle"
        case .researcher: return "magnifyingglass"
        case .ideator:    return "lightbulb"
        case .developer:  return "hammer"
        }
    }

    var dotColor: Color {
        switch self {
        case .claude:     return Theme.textSecondary
        case .researcher: return Color(hex: 0x7ab5a0)
        case .ideator:    return Color(hex: 0xc4a85c)
        case .developer:  return Theme.accent
        }
    }

    var defaultChatModel: AgentModel {
        switch self {
        case .claude:     return .sonnet
        case .researcher: return .sonnet
        case .ideator:    return .opus
        case .developer:  return .sonnet
        }
    }
}

// MARK: - Tile Type

enum TileType: Equatable {
    case terminal(panelId: UUID, agent: AgentMode)
    case stickyNote
    case markdown(path: String)
    case image(path: String)
    case browser(url: URL?)
    case chatAgent(sessionId: UUID, role: AgentRole)

    var displayName: String {
        switch self {
        case .terminal(_, let agent): return agent.displayName
        case .stickyNote:             return "Sticky Note"
        case .markdown:               return "Markdown"
        case .image:                  return "Image"
        case .browser:                return "Browser"
        case .chatAgent(_, let role): return role.name
        }
    }

    var iconName: String {
        switch self {
        case .terminal(_, let agent): return agent.iconName
        case .stickyNote:             return "note.text"
        case .markdown:               return "doc.text"
        case .image:                  return "photo"
        case .browser:                return "globe"
        case .chatAgent:              return "bubble.left.and.text.bubble.right"
        }
    }
}

// MARK: - Codable

extension TileType: Codable {
    enum CodingKeys: String, CodingKey {
        case type, panelId, agent, path, url, sessionId, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "terminal":
            self = .terminal(
                panelId: try c.decode(UUID.self, forKey: .panelId),
                agent: try c.decode(AgentMode.self, forKey: .agent)
            )
        case "stickyNote":
            self = .stickyNote
        case "markdown":
            self = .markdown(path: try c.decode(String.self, forKey: .path))
        case "image":
            self = .image(path: try c.decode(String.self, forKey: .path))
        case "browser":
            self = .browser(url: try c.decodeIfPresent(URL.self, forKey: .url))
        case "chatAgent":
            self = .chatAgent(
                sessionId: try c.decode(UUID.self, forKey: .sessionId),
                role: try c.decode(AgentRole.self, forKey: .role)
            )
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.type], debugDescription: "Unknown tile type: \(type)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let pid, let agent):
            try c.encode("terminal", forKey: .type)
            try c.encode(pid, forKey: .panelId)
            try c.encode(agent, forKey: .agent)
        case .stickyNote:
            try c.encode("stickyNote", forKey: .type)
        case .markdown(let p):
            try c.encode("markdown", forKey: .type)
            try c.encode(p, forKey: .path)
        case .image(let p):
            try c.encode("image", forKey: .type)
            try c.encode(p, forKey: .path)
        case .browser(let u):
            try c.encode("browser", forKey: .type)
            try c.encodeIfPresent(u, forKey: .url)
        case .chatAgent(let sid, let role):
            try c.encode("chatAgent", forKey: .type)
            try c.encode(sid, forKey: .sessionId)
            try c.encode(role, forKey: .role)
        }
    }
}
