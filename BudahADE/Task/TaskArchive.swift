import Foundation

// MARK: - ArchivedTask

struct ArchivedTask: Codable, Identifiable {
    let id: UUID
    let name: String
    let branchName: String
    let worktreePath: String
    let completedAt: Date
    let specVersionCount: Int
    let conversationCount: Int
}

// MARK: - TaskArchive

final class TaskArchive: ObservableObject, Codable {
    @Published var tasks: [ArchivedTask] = []

    private static let fileName = "task-archive.json"

    init() {}

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([ArchivedTask].self, forKey: .tasks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tasks, forKey: .tasks)
    }

    // MARK: - Mutation

    func add(_ task: ArchivedTask) {
        tasks.insert(task, at: 0)
    }

    // MARK: - Persistence

    static func save(_ archive: TaskArchive, to projectPath: String) {
        let dir = (projectPath as NSString).appendingPathComponent(".budahade")
        let path = (dir as NSString).appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(archive)
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            print("[TaskArchive] Save failed: \(error)")
        }
    }

    static func load(from projectPath: String) -> TaskArchive? {
        let path = (projectPath as NSString)
            .appendingPathComponent(".budahade")
            .appending("/\(fileName)")

        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TaskArchive.self, from: data)
    }
}
