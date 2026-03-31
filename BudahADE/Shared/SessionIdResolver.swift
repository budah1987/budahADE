import Foundation

// MARK: - SessionIdResolver

/// Locates the most recent Claude session ID for a given worktree path by scanning
/// the ~/.claude/projects/ directory. Claude CLI's --resume flag expects the UUID
/// filename of the most recently modified .jsonl session file, not the API session_XXXXX ID.
enum SessionIdResolver {

    static func findLatest(worktreePath: String) -> String? {
        // Claude project dir slug: path with / → -, space → -, dot → -
        // e.g. "/Users/amir/Documents/Cursor Projects/.budahade-worktrees/feat-test"
        //    → "-Users-amir-Documents-Cursor-Projects--budahade-worktrees-feat-test"
        let projectSlug = worktreePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let claudeProjectDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/projects/\(projectSlug)")

        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectDir) else { return nil }

        // Find the most recently modified .jsonl file
        guard let files = try? fm.contentsOfDirectory(atPath: claudeProjectDir) else { return nil }
        let jsonlFiles = files.filter { $0.hasSuffix(".jsonl") }
            .compactMap { filename -> (String, Date)? in
                let path = (claudeProjectDir as NSString).appendingPathComponent(filename)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return (path, modified)
            }
            .sorted { $0.1 > $1.1 }  // Most recent first

        guard let mostRecent = jsonlFiles.first else { return nil }

        let filename = ((mostRecent.0 as NSString).lastPathComponent as NSString).deletingPathExtension
        print("[SessionIdResolver] Found Claude session: \(filename) from \(mostRecent.0)")
        return filename
    }
}
