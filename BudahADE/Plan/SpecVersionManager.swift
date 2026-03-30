import Foundation

// MARK: - SpecVersion

struct SpecVersion {
    let version: Int
    let path: String
    let content: String
}

// MARK: - SpecVersionManager

enum SpecVersionManager {

    private static let specsDir = ".budahade/specs"
    private static let activeSpecPath = ".budahade/spec.md"

    /// Approves content as a new versioned spec.
    /// Creates .budahade/specs/spec-vN.md and updates .budahade/spec.md.
    /// Returns the version number written.
    @discardableResult
    static func approve(content: String, in worktreePath: String) -> Int {
        let fm = FileManager.default
        let specsDirPath = (worktreePath as NSString).appendingPathComponent(specsDir)

        // Ensure specs directory exists
        try? fm.createDirectory(atPath: specsDirPath, withIntermediateDirectories: true)

        // Determine next version number
        let existingVersions = listVersions(in: worktreePath)
        let nextVersion = (existingVersions.map(\.version).max() ?? 0) + 1

        // Write versioned copy
        let versionedFileName = "spec-v\(nextVersion).md"
        let versionedPath = (specsDirPath as NSString).appendingPathComponent(versionedFileName)
        try? content.write(toFile: versionedPath, atomically: true, encoding: .utf8)

        // Write active copy
        let activePath = (worktreePath as NSString).appendingPathComponent(activeSpecPath)
        // Ensure .budahade directory exists
        let budahadePath = (worktreePath as NSString).appendingPathComponent(".budahade")
        try? fm.createDirectory(atPath: budahadePath, withIntermediateDirectories: true)
        try? content.write(toFile: activePath, atomically: true, encoding: .utf8)

        return nextVersion
    }

    /// Lists all versioned specs in ascending order by version number.
    static func listVersions(in worktreePath: String) -> [SpecVersion] {
        let fm = FileManager.default
        let specsDirPath = (worktreePath as NSString).appendingPathComponent(specsDir)

        guard let files = try? fm.contentsOfDirectory(atPath: specsDirPath) else {
            return []
        }

        return files
            .compactMap { filename -> SpecVersion? in
                guard filename.hasPrefix("spec-v"), filename.hasSuffix(".md") else { return nil }
                let versionStr = filename
                    .dropFirst("spec-v".count)
                    .dropLast(".md".count)
                guard let version = Int(versionStr) else { return nil }
                let path = (specsDirPath as NSString).appendingPathComponent(filename)
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                return SpecVersion(version: version, path: path, content: content)
            }
            .sorted { $0.version < $1.version }
    }

    /// Reads the active spec from .budahade/spec.md, if it exists.
    static func activeSpec(in worktreePath: String) -> String? {
        let activePath = (worktreePath as NSString).appendingPathComponent(activeSpecPath)
        return try? String(contentsOfFile: activePath, encoding: .utf8)
    }
}
