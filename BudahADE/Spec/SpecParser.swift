import Foundation

// MARK: - Spec Task

struct SpecTask: Identifiable, Equatable {
    let id: Int
    let title: String
    let isCompleted: Bool
}

// MARK: - Spec Parse Result

struct SpecParseResult: Equatable {
    let title: String?
    let tasks: [SpecTask]
    let filePath: String

    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var totalCount: Int { tasks.count }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

// MARK: - Spec Parser

enum SpecParser {

    /// Parse a markdown spec file for title and checkbox tasks
    static func parse(fileAt path: String) -> SpecParseResult? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var title: String?
        var tasks: [SpecTask] = []
        var index = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // First H1 is the title
            if title == nil && trimmed.hasPrefix("# ") {
                title = String(trimmed.dropFirst(2))
                continue
            }

            // Checkbox tasks: - [x] or - [ ]
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                tasks.append(SpecTask(id: index, title: taskTitle, isCompleted: true))
                index += 1
            } else if trimmed.hasPrefix("- [ ] ") {
                let taskTitle = String(trimmed.dropFirst(6))
                tasks.append(SpecTask(id: index, title: taskTitle, isCompleted: false))
                index += 1
            }
        }

        guard !tasks.isEmpty else { return nil }

        return SpecParseResult(title: title, tasks: tasks, filePath: path)
    }

    /// Find spec files in a directory
    static func findSpecFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else {
            return []
        }

        let specPatterns = ["-spec.md", "-plan.md", ".spec.md"]
        return contents
            .filter { name in specPatterns.contains(where: { name.lowercased().hasSuffix($0) }) }
            .map { (directory as NSString).appendingPathComponent($0) }
    }
}
