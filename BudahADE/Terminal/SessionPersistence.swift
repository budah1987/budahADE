import Foundation

struct TabSnapshot: Codable {
    let id: UUID
    let title: String
    let claudeSessionId: String?
    let agentMode: String?       // AgentMode rawValue or nil
    let isActive: Bool
    let scrollbackPath: String?  // relative path to scrollback text file
    let tmuxSession: String?     // tmux session name for reattach
}

struct SessionSnapshot: Codable {
    let tabs: [TabSnapshot]
    let selectedTabId: UUID?
}

enum SessionPersistence {
    private static let directory = "sessions"
    private static let filename = "tabs.json"

    static func save(_ snapshot: SessionSnapshot, to worktreePath: String) throws {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func load(from worktreePath: String) -> SessionSnapshot? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)/\(filename)")
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    static func saveScrollback(_ text: String, tabId: UUID, to worktreePath: String) throws -> String {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filename = "\(tabId.uuidString)-scrollback.txt"
        let path = (dir as NSString).appendingPathComponent(filename)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        return "\(directory)/\(filename)"
    }

    static func loadScrollback(relativePath: String, from worktreePath: String) -> String? {
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(relativePath)")
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
