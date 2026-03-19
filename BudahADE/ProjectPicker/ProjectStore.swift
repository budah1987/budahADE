import Foundation
import Combine

class ProjectStore: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var searchText: String = ""

    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/workspace/config").path
    private let lastProjectPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/workspace/last_project").path
    private let fallbackProjectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Developer").path

    var filteredProjects: [ProjectInfo] {
        let sorted = sortedProjects(projects)
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    init() {
        loadProjects()
    }

    // MARK: - Project Discovery

    func loadProjects() {
        let projectsDir = resolveProjectsDir()
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectsDir) else {
            projects = []
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(atPath: projectsDir)
            var result: [ProjectInfo] = []

            for name in contents {
                // Skip hidden directories
                guard !name.hasPrefix(".") else { continue }

                let fullPath = (projectsDir as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let lastModified = attrs?[.modificationDate] as? Date

                result.append(ProjectInfo(
                    name: name,
                    path: fullPath,
                    lastModified: lastModified
                ))
            }

            projects = result
        } catch {
            projects = []
        }
    }

    // MARK: - Last Project

    func saveLastProject(_ path: String) {
        let fm = FileManager.default
        let dir = (lastProjectPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? path.write(toFile: lastProjectPath, atomically: true, encoding: .utf8)
    }

    func loadLastProject() -> String? {
        try? String(contentsOfFile: lastProjectPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private func resolveProjectsDir() -> String {
        guard FileManager.default.fileExists(atPath: configPath),
              let configContents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return fallbackProjectsDir
        }

        for line in configContents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("PROJECTS_DIR=") {
                var value = String(trimmed.dropFirst("PROJECTS_DIR=".count))
                // Strip surrounding quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                // Expand ~ to home directory
                if value.hasPrefix("~") {
                    value = (value as NSString).expandingTildeInPath
                }
                return value
            }
        }

        return fallbackProjectsDir
    }

    private func sortedProjects(_ list: [ProjectInfo]) -> [ProjectInfo] {
        let lastUsedPath = loadLastProject()

        return list.sorted { a, b in
            // Last-used project comes first
            if a.path == lastUsedPath { return true }
            if b.path == lastUsedPath { return false }
            // Then alphabetical by name
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
