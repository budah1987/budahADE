import Foundation

// MARK: - ConversationSnapshot

struct ConversationSnapshot: Codable {
    let tabId: UUID
    let role: AgentMode
    let messages: [ChatMessage]
}

// MARK: - PlanConversationPersistence

enum PlanConversationPersistence {
    private static let directory = "conversations"

    /// Save a conversation snapshot to .budahade/conversations/{tabId}.json
    static func save(_ snapshot: ConversationSnapshot, to worktreePath: String) {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let filename = "\(snapshot.tabId.uuidString).json"
            let path = (dir as NSString).appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("Failed to save conversation snapshot: \(error)")
        }
    }

    /// Load a single conversation by tabId
    static func load(tabId: UUID, from worktreePath: String) -> ConversationSnapshot? {
        let filename = "\(tabId.uuidString).json"
        let path = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)/\(filename)")

        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(ConversationSnapshot.self, from: data)
    }

    /// Load all conversations from the conversations directory
    static func loadAll(from worktreePath: String) -> [ConversationSnapshot] {
        let dir = (worktreePath as NSString).appendingPathComponent(".budahade/\(directory)")

        guard FileManager.default.fileExists(atPath: dir),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshots = contents
            .filter { $0.hasSuffix(".json") }
            .compactMap { filename -> ConversationSnapshot? in
                let path = (dir as NSString).appendingPathComponent(filename)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    return nil
                }
                return try? decoder.decode(ConversationSnapshot.self, from: data)
            }

        return snapshots.sorted { $0.tabId.uuidString < $1.tabId.uuidString }
    }

    /// Load all conversations except the specified tabId (for sibling context)
    static func loadAllExcluding(tabId: UUID, from worktreePath: String) -> [ConversationSnapshot] {
        let all = loadAll(from: worktreePath)
        return all.filter { $0.tabId != tabId }
    }
}
