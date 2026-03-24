import Foundation

// MARK: - CLISubprocessManager

@MainActor
final class CLISubprocessManager: ObservableObject {

    // MARK: - Published State

    @Published var sessions: [UUID: AgentSession] = [:]

    // MARK: - Session Lifecycle

    @discardableResult
    func createSession(
        model: AgentModel,
        agentMode: AgentMode? = nil,
        systemPrompt: String,
        workingDirectory: String
    ) -> AgentSession {
        let session = AgentSession(
            model: model,
            agentMode: agentMode,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        )
        sessions[session.id] = session
        return session
    }

    func send(sessionId: UUID, prompt: String, model: AgentModel? = nil) {
        guard let session = sessions[sessionId] else { return }

        if let model = model {
            session.model = model
        }

        session.addUserMessage(prompt)
        session.status = .streaming

        let systemPromptPath = writeSystemPrompt(session: session)
        let command = buildCommand(
            prompt: prompt,
            model: session.model,
            systemPromptPath: systemPromptPath,
            sessionId: session.claudeSessionId
        )

        Task {
            await runSubprocess(command: command, session: session)
        }
    }

    func cancel(sessionId: UUID) {
        guard let session = sessions[sessionId] else { return }
        session.process?.terminate()
        session.process = nil
        session.status = .idle
        session.currentStreamingText = ""
    }

    func removeSession(sessionId: UUID) {
        cancel(sessionId: sessionId)
        sessions.removeValue(forKey: sessionId)
    }

    // MARK: - Workspace-level Token Tracking

    var totalTokensAllSessions: Int {
        sessions.values.reduce(0) { $0 + $1.totalTokens }
    }

    var formattedTotalTokens: String {
        let total = totalTokensAllSessions
        if total < 1000 {
            return "\(total)"
        } else {
            let formatted = Double(total) / 1000.0
            return String(format: "%.1f", formatted) + "k"
        }
    }

    var activeSessionCount: Int {
        sessions.values.filter { $0.status == .streaming || $0.status == .done }.count
    }

    // MARK: - Command Building

    func buildCommand(
        prompt: String,
        model: AgentModel,
        systemPromptPath: String,
        sessionId: String?
    ) -> [String] {
        var command = [
            "claude",
            "-p", prompt,
            "--output-format", "stream-json",
            "--model", model.cliFlag,
            "--system-prompt-file", systemPromptPath,
            "--dangerously-skip-permissions"
        ]

        if let sessionId = sessionId {
            command += ["--resume", sessionId]
        }

        return command
    }

    // MARK: - Stream Processing

    func processStreamLine(_ line: String, session: AgentSession) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let event = try StreamEvent.parse(from: trimmed)
            switch event {
            case .system(let info):
                session.handleSystemInit(info)
            case .assistant(let msg):
                session.handleAssistantMessage(msg)
            case .contentDelta(let text):
                session.handleContentDelta(text)
            case .result(let result):
                session.handleResult(result)
            case .unknown:
                break
            }
        } catch {
            // Non-JSON lines (e.g., debug output) are silently ignored
        }
    }

    // MARK: - Private: Write System Prompt

    private func writeSystemPrompt(session: AgentSession) -> String {
        let dir = URL(fileURLWithPath: session.workingDirectory)
            .appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("chat-\(session.id.uuidString)-prompt.md")
        try? session.systemPrompt.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    // MARK: - Private: Find Claude Binary

    /// Resolve the `claude` executable path. GUI apps don't inherit shell PATH,
    /// so we search common install locations explicitly.
    private nonisolated(unsafe) static let claudePath: String = {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.superset/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                print("[CLISubprocessManager] Found claude at: \(path)")
                return path
            }
        }
        // Fallback — hope it's on PATH (works when launched from terminal)
        print("[CLISubprocessManager] claude not found at known paths, falling back to /usr/bin/env")
        return "/usr/bin/env"
    }()

    // MARK: - Private: Run Subprocess

    private nonisolated func runSubprocess(command: [String], session: AgentSession) async {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Use resolved claude path directly if found, otherwise /usr/bin/env
        let claudeBin = Self.claudePath
        if claudeBin == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        } else {
            process.executableURL = URL(fileURLWithPath: claudeBin)
            // Strip "claude" from command args (it's the executable now, not an arg)
            process.arguments = Array(command.dropFirst())
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Ensure PATH is set for child process (claude may need node, git, etc.)
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.superset/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = env

        let workDir = await session.workingDirectory
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)

        await MainActor.run { session.process = process }

        let fullCommand = ([claudeBin] + (process.arguments ?? [])).joined(separator: " ")
        print("[CLISubprocessManager] Launching: \(fullCommand)")
        print("[CLISubprocessManager] Working dir: \(workDir)")

        do {
            try process.run()
            print("[CLISubprocessManager] Process launched (pid: \(process.processIdentifier))")
        } catch {
            print("[CLISubprocessManager] Launch failed: \(error)")
            await MainActor.run {
                session.status = .error("Failed to launch: \(error.localizedDescription)")
                session.process = nil
            }
            return
        }

        // Read stderr in background for diagnostics
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached {
            let errData = stderrHandle.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                print("[CLISubprocessManager] STDERR: \(errStr.prefix(500))")
            }
        }

        // Read stdout line by line
        let handle = stdoutPipe.fileHandleForReading
        var buffer = Data()
        var lineCount = 0

        while process.isRunning || !buffer.isEmpty {
            let chunk = handle.availableData
            if chunk.isEmpty && !process.isRunning { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    lineCount += 1
                    if lineCount <= 3 {
                        print("[CLISubprocessManager] stdout line \(lineCount): \(line.prefix(200))")
                    }
                    await MainActor.run { [weak self] in
                        self?.processStreamLine(line, session: session)
                    }
                }
            }
        }

        // Remaining data
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            await MainActor.run { [weak self] in
                self?.processStreamLine(line, session: session)
            }
        }

        process.waitUntilExit()
        let exitCode = process.terminationStatus
        print("[CLISubprocessManager] Process exited (code: \(exitCode), lines read: \(lineCount))")

        await MainActor.run {
            session.process = nil
            if session.status == .streaming {
                if exitCode != 0 && lineCount == 0 {
                    session.status = .error("Process exited with code \(exitCode)")
                } else {
                    session.status = .done
                }
            }
        }
    }
}
