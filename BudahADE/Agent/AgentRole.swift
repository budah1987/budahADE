import SwiftUI

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
