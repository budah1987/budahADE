import Foundation

struct CanvasSnapshot: Codable {
    let elements: [CanvasElement]
    let zoom: CGFloat
    let panOffsetWidth: CGFloat
    let panOffsetHeight: CGFloat
    let chatMessages: [UUID: [ChatMessage]]  // sessionId → messages
    let claudeSessionIds: [UUID: String]?  // sessionId → claude session ID for --resume
    let terminalTmuxSessions: [UUID: String]?  // panelId → tmux session name
    let connections: [TileConnection]

    init(
        elements: [CanvasElement],
        zoom: CGFloat,
        panOffsetWidth: CGFloat,
        panOffsetHeight: CGFloat,
        chatMessages: [UUID: [ChatMessage]],
        claudeSessionIds: [UUID: String]?,
        terminalTmuxSessions: [UUID: String]?,
        connections: [TileConnection] = []
    ) {
        self.elements = elements
        self.zoom = zoom
        self.panOffsetWidth = panOffsetWidth
        self.panOffsetHeight = panOffsetHeight
        self.chatMessages = chatMessages
        self.claudeSessionIds = claudeSessionIds
        self.terminalTmuxSessions = terminalTmuxSessions
        self.connections = connections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elements = try container.decode([CanvasElement].self, forKey: .elements)
        zoom = try container.decode(CGFloat.self, forKey: .zoom)
        panOffsetWidth = try container.decode(CGFloat.self, forKey: .panOffsetWidth)
        panOffsetHeight = try container.decode(CGFloat.self, forKey: .panOffsetHeight)
        chatMessages = try container.decode([UUID: [ChatMessage]].self, forKey: .chatMessages)
        claudeSessionIds = try container.decodeIfPresent([UUID: String].self, forKey: .claudeSessionIds)
        terminalTmuxSessions = try container.decodeIfPresent([UUID: String].self, forKey: .terminalTmuxSessions)
        connections = try container.decodeIfPresent([TileConnection].self, forKey: .connections) ?? []
    }
}

enum CanvasPersistence {
    private static let filename = "canvas.json"

    static func save(_ snapshot: CanvasSnapshot, to worktreePath: String) throws {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func load(from worktreePath: String) -> CanvasSnapshot? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(filename)")
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(CanvasSnapshot.self, from: data)
    }
}
