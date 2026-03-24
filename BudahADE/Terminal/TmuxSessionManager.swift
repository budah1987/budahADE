import Foundation

/// Manages tmux sessions for terminal persistence across app restarts.
/// When tmux is available, terminal sessions survive app quit — Claude keeps running.
enum TmuxSessionManager {

    // MARK: - Availability

    /// Resolved tmux binary path (nil if not installed).
    private static let resolvedPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                print("[TmuxSessionManager] Found tmux at: \(path)")
                return path
            }
        }
        print("[TmuxSessionManager] tmux not found")
        return nil
    }()

    /// Whether tmux is installed and available.
    static var isAvailable: Bool { resolvedPath != nil }

    private static var tmuxPath: String { resolvedPath ?? "/opt/homebrew/bin/tmux" }

    // MARK: - Session Names

    /// Generate a stable tmux session name for a tab.
    static func sessionName(for id: UUID) -> String {
        "budahade-\(id.uuidString.prefix(8).lowercased())"
    }

    // MARK: - Session State

    /// Check if a tmux session exists (still alive from a previous app run).
    static func sessionExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["has-session", "-t", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Commands (sent to Ghostty terminal as text)

    /// Command to attach to an existing tmux session.
    static func attachCommand(name: String) -> String {
        "\(tmuxPath) attach-session -t \(name)"
    }

    /// Command to create a new tmux session (stays attached).
    /// Uses a BudahADE-specific tmux config for extended-keys passthrough.
    static func newSessionCommand(name: String, workingDirectory: String) -> String {
        ensureTmuxConfig()
        return "\(tmuxPath) -f '\(tmuxConfigPath)' new-session -s \(name) -c '\(workingDirectory)'"
    }

    /// Path to BudahADE's tmux config file.
    private static var tmuxConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/budahade/tmux.conf")
    }

    /// Write BudahADE's tmux config if it doesn't exist.
    private static func ensureTmuxConfig() {
        let path = tmuxConfigPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let config = """
        # BudahADE tmux config — enables kitty keyboard protocol passthrough
        set -s extended-keys on
        set -s extended-keys-format csi-u
        set -g allow-passthrough on
        set -g default-terminal "xterm-256color"
        set -as terminal-features ",xterm-256color:clipboard"
        set -g mouse on
        set -g set-clipboard on

        # Don't show tmux status bar (BudahADE has its own tab bar)
        set -g status off
        """
        try? config.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Command to attach if exists, otherwise create new.
    static func attachOrCreateCommand(name: String, workingDirectory: String) -> String {
        "\(tmuxPath) attach-session -t \(name) 2>/dev/null || \(tmuxPath) new-session -s \(name) -c '\(workingDirectory)'"
    }

    // MARK: - Send Keys

    /// Send keys to a tmux session (bypasses terminal encoding issues).
    static func sendKeys(session: String, keys: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["send-keys", "-t", session, keys]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Cleanup

    /// Kill a tmux session (e.g. when user closes a tab).
    static func killSession(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["kill-session", "-t", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// List all budahade tmux sessions.
    static func listSessions() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.components(separatedBy: "\n")
                .filter { $0.hasPrefix("budahade-") }
        } catch {
            return []
        }
    }
}
