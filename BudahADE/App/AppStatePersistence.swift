import Foundation

// MARK: - Snapshots

struct WorkspaceSnapshot: Codable {
    let projectPath: String
    let tasks: [TaskSnapshot]
    let activeTaskIndex: Int?
}

struct TaskSnapshot: Codable {
    let name: String
    let branchName: String
    let baseBranch: String
    let mode: String  // "plan" or "build"
}

struct AppSnapshot: Codable {
    let workspaces: [WorkspaceSnapshot]
    let activeWorkspaceIndex: Int
}

// MARK: - Persistence

enum AppStatePersistence {
    private static var filePath: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("app-state.json")
    }

    static func save(_ snapshot: AppSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: filePath))
            print("[AppStatePersistence] Saved \(snapshot.workspaces.count) workspace(s)")
        } catch {
            print("[AppStatePersistence] Save failed: \(error)")
        }
    }

    static func load() -> AppSnapshot? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        return try? JSONDecoder().decode(AppSnapshot.self, from: data)
    }
}
