import Foundation

struct CanvasSnapshot: Codable {
    let elements: [CanvasElement]
    let zoom: CGFloat
    let panOffsetWidth: CGFloat
    let panOffsetHeight: CGFloat
    let chatMessages: [UUID: [ChatMessage]]  // sessionId → messages
    let claudeSessionIds: [UUID: String]?  // sessionId → claude session ID for --resume
    let terminalTmuxSessions: [UUID: String]?  // panelId → tmux session name
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
