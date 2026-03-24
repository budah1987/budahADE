import SwiftUI
import AppKit

struct AgentRole: Equatable, Identifiable {
    let id: String              // "ideator", "developer", etc.
    let name: String
    let systemPrompt: String
    let defaultModel: AgentModel
    let color: Color

    static func from(agent: AgentMode, taskName: String, branchName: String) -> AgentRole {
        AgentRole(
            id: agent.rawValue,
            name: agent.displayName,
            systemPrompt: AgentPrompts.chatSystemPrompt(
                agent: agent,
                taskName: taskName,
                branchName: branchName
            ),
            defaultModel: agent.defaultChatModel,
            color: agent.dotColor
        )
    }

    static let builtInRoles: [AgentMode] = AgentMode.allCases
}

// MARK: - Codable

extension AgentRole: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt, defaultModel, colorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        self.defaultModel = try c.decode(AgentModel.self, forKey: .defaultModel)
        let hex = try c.decode(UInt32.self, forKey: .colorHex)
        self.color = Color(hex: hex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(defaultModel, forKey: .defaultModel)
        let nsColor = NSColor(self.color).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = UInt32(nsColor.redComponent * 255) << 16
        let g = UInt32(nsColor.greenComponent * 255) << 8
        let b = UInt32(nsColor.blueComponent * 255)
        try c.encode(r | g | b, forKey: .colorHex)
    }
}
