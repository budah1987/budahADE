import Foundation

// MARK: - Dev Server Manager

/// Manages a per-task dev server process lifecycle.
@MainActor
final class DevServerManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var detectedURLs: [URL] = []

    /// Called on main actor for each stdout chunk — used by SmartReloader.
    var onStdoutChunk: ((String) -> Void)?

    /// Convenience: first detected URL (backwards compat with TaskState).
    var detectedURL: URL? { detectedURLs.first }

    let config: DevServerConfig
    let port: Int
    let worktreePath: String

    private var process: Process?
    private var outputPipe: Pipe?

    init(config: DevServerConfig, port: Int, worktreePath: String) {
        self.config = config
        self.port = port
        self.worktreePath = worktreePath
    }

    /// Start the dev server process.
    func start() {
        guard process == nil else { return }

        let command = config.shellCommand(port: port)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        // Create new process group for clean shutdown
        proc.qualityOfService = .utility

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        // Watch stdout for localhost URLs and relay to SmartReloader
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.parseForURLs(text)
                self?.onStdoutChunk?(text)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.isRunning = true

            // If port is injected (not detected from stdout), set URL immediately
            if config.portInjection != .stdout {
                if let url = URL(string: "http://localhost:\(port)") {
                    detectedURLs = [url]
                }
            }
        } catch {
            print("[DevServerManager] Failed to start: \(error)")
        }
    }

    /// Stop the dev server and its child processes.
    func stop() {
        guard let proc = process, proc.isRunning else {
            cleanup()
            return
        }

        // Kill entire process group
        let pgid = proc.processIdentifier
        kill(-pgid, SIGTERM)

        // Fallback: force kill after 5 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            if proc.isRunning {
                kill(-pgid, SIGKILL)
            }
            Task { @MainActor [weak self] in
                self?.cleanup()
            }
        }
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        isRunning = false
    }

    // MARK: - URL Detection

    private func parseForURLs(_ text: String) {
        let found = URLDetector.detect(in: text)
        for url in found where !detectedURLs.contains(url) {
            detectedURLs.append(url)
        }
    }
}
