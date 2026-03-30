import SwiftUI

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
