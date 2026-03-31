import Foundation

private func logTiming(_ msg: String) {
    let line = "[\(Date().timeIntervalSince1970)] \(msg)\n"
    print(msg)
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: "/tmp/budahade-timing.log") {
            if let fh = FileHandle(forWritingAtPath: "/tmp/budahade-timing.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: "/tmp/budahade-timing.log", contents: data)
        }
    }
}

// MARK: - CLISubprocessManager

@MainActor
final class CLISubprocessManager: ObservableObject {

    // MARK: - Published State

    @Published var sessions: [UUID: AgentSession] = [:]

    /// Called when a session finishes a turn (status → .done). Used for auto-forwarding.
    var onSessionComplete: ((UUID) -> Void)?

    // MARK: - Session Lifecycle

    @discardableResult
    func createSession(
        model: AgentModel,
        agentMode: AgentMode? = nil,
        systemPrompt: String,
        workingDirectory: String,
        enableAgentTeams: Bool = false,
        disableMcp: Bool = false
    ) -> AgentSession {
        let session = AgentSession(
            model: model,
            agentMode: agentMode,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory,
            enableAgentTeams: enableAgentTeams,
            disableMcp: disableMcp
        )
        sessions[session.id] = session
        return session
    }

    func send(sessionId: UUID, prompt: String, model: AgentModel? = nil) {
        let t0 = CFAbsoluteTimeGetCurrent()
        logTiming("[TIMING] T0 send() called")

        guard let session = sessions[sessionId] else {
            print("[CLISubprocessManager] ⚠️ No session found for \(sessionId)")
            return
        }

        if let model = model {
            session.model = model
        }

        // Guard: don't send while already running
        if session.status == .connecting || session.status == .streaming {
            print("[CLISubprocessManager] ⚠️ Ignoring send while \(session.status)")
            return
        }

        session.addUserMessage(prompt)
        session.status = .connecting
        session.currentStreamingText = ""

        let systemPromptPath = writeSystemPrompt(session: session)
        let resumeId = session.claudeSessionId
        let command = buildCommand(
            prompt: prompt,
            model: session.model,
            systemPromptPath: systemPromptPath,
            sessionId: resumeId,
            allowedTools: session.agentMode?.chatAllowedTools,
            maxTurns: session.agentMode?.chatMaxTurns,
            disableMcp: session.disableMcp
        )

        logTiming("[TIMING] T1 command built, resume=\(resumeId?.prefix(8) ?? "nil") (+\(CFAbsoluteTimeGetCurrent() - t0)s)")

        let workDir = session.workingDirectory
        let agentTeamsEnabled = session.enableAgentTeams
        Task {
            await self.runSubprocess(command: command, workingDirectory: workDir, session: session, agentTeamsEnabled: agentTeamsEnabled, t0: t0)
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
        systemPromptCache.removeValue(forKey: sessionId)
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
        sessions.values.filter { $0.status == .connecting || $0.status == .streaming || $0.status == .done }.count
    }

    // MARK: - Command Building

    func buildCommand(
        prompt: String,
        model: AgentModel,
        systemPromptPath: String,
        sessionId: String?,
        allowedTools: [String]? = nil,
        maxTurns: Int? = nil,
        disableMcp: Bool = false
    ) -> [String] {
        var command = [
            "claude",
            "-p", prompt,
            "--output-format", "stream-json", "--verbose",
            "--model", model.cliFlag,
            "--system-prompt-file", systemPromptPath,
            "--dangerously-skip-permissions",
        ]

        if disableMcp {
            command += ["--strict-mcp-config"]
        }

        if let tools = allowedTools {
            if tools.isEmpty {
                command += ["--allowedTools", ""]
            } else {
                command += ["--allowedTools"] + tools
            }
        }

        if let maxTurns {
            command += ["--max-turns", "\(maxTurns)"]
        }

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
                if info.tools != nil {
                    logTiming("[TIMING] T4 system init received")
                }
                session.handleSystemInit(info)
            case .assistant(let msg):
                session.handleAssistantMessage(msg)
                // Emit tool use events from assistant content blocks
                if let tools = msg.toolCalls {
                    for tool in tools {
                        let toolEvent = ToolUseEvent(id: tool.id, name: tool.name, inputJSON: tool.input)
                        session.handleToolUse(toolEvent)
                    }
                }
            case .contentDelta(let text):
                if session.currentStreamingText.isEmpty {
                    logTiming("[TIMING] T6 first contentDelta received")
                }
                session.handleContentDelta(text)
            case .result(let result):
                logTiming("[TIMING] T7 result event received")
                session.handleResult(result)
                onSessionComplete?(session.id)
            case .toolUse(let event):
                session.handleToolUse(event)
            case .toolResult(let event):
                session.handleToolResult(event)
            case .thinking(let text):
                session.handleThinking(text)
            case .rateLimitEvent(let info):
                session.handleRateLimit(info)
            case .hookStarted, .hookResponse:
                break  // Log only, no UI action
            case .unknown:
                break
            }
        } catch {
            // Silently skip unparseable lines (hook events, etc.)
        }
    }

    // MARK: - Private: Write System Prompt

    /// Cache of system prompt file paths — only rewrite when content changes
    private var systemPromptCache: [UUID: (path: String, hash: Int)] = [:]

    private func writeSystemPrompt(session: AgentSession) -> String {
        let dir = URL(fileURLWithPath: session.workingDirectory)
            .appendingPathComponent(".budahade")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("chat-\(session.id.uuidString)-prompt.md")
        let path = fileURL.path

        // Only write to disk if the prompt content has changed
        let contentHash = session.systemPrompt.hashValue
        if let cached = systemPromptCache[session.id], cached.hash == contentHash {
            return cached.path
        }

        try? session.systemPrompt.write(to: fileURL, atomically: true, encoding: .utf8)
        systemPromptCache[session.id] = (path: path, hash: contentHash)
        return path
    }

    // MARK: - Private: Find Claude Binary

    nonisolated(unsafe) static let claudePath: String = {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.superset/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/env"
    }()

    // MARK: - Private: Run Subprocess

    /// Launches a claude subprocess for a single message turn.
    /// Uses -p mode with the prompt as argument. For follow-up messages,
    /// --resume is used to continue the conversation.
    /// readabilityHandler provides non-blocking stdout processing.
    private nonisolated func runSubprocess(command: [String], workingDirectory: String, session: AgentSession, agentTeamsEnabled: Bool, t0: CFAbsoluteTime) async {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let claudeBin = Self.claudePath
        if claudeBin == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        } else {
            process.executableURL = URL(fileURLWithPath: claudeBin)
            process.arguments = Array(command.dropFirst())
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice  // No stdin needed — prompt is in -p arg

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.superset/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")

        if agentTeamsEnabled {
            env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        }

        process.environment = env

        let fm = FileManager.default
        guard fm.fileExists(atPath: workingDirectory) else {
            await MainActor.run {
                session.status = .error("Working directory not found: \(workingDirectory)")
            }
            return
        }

        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        await MainActor.run { session.process = process }

        logTiming("[TIMING] T2 about to process.run() (+\(CFAbsoluteTimeGetCurrent() - t0)s)")

        do {
            try process.run()
            logTiming("[TIMING] T2b process launched (pid: \(process.processIdentifier)) (+\(CFAbsoluteTimeGetCurrent() - t0)s)")
        } catch {
            await MainActor.run {
                session.status = .error("Failed to launch: \(error.localizedDescription)")
                session.process = nil
            }
            return
        }

        // Read stderr in background
        Task.detached {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                print("[CLISubprocessManager] STDERR: \(errStr.prefix(500))")
            }
        }

        // Non-blocking stdout reading via readabilityHandler
        let handle = stdoutPipe.fileHandleForReading
        nonisolated(unsafe) var buffer = Data()
        nonisolated(unsafe) var firstChunkLogged = false
        weak var weakSelf = self
        let capturedT0 = t0

        handle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData

            if !firstChunkLogged && !chunk.isEmpty {
                firstChunkLogged = true
                logTiming("[TIMING] T3 first stdout chunk (\(chunk.count) bytes) (+\(CFAbsoluteTimeGetCurrent() - capturedT0)s)")
            }

            if chunk.isEmpty {
                // EOF — process closed stdout
                fileHandle.readabilityHandler = nil
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    let capturedLine = line
                    DispatchQueue.main.async {
                        guard let mgr = weakSelf else { return }
                        mgr.processStreamLine(capturedLine, session: session)
                    }
                }
                return
            }

            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                if let line = String(data: lineData, encoding: .utf8) {
                    let capturedLine = line
                    DispatchQueue.main.async {
                        guard let mgr = weakSelf else { return }
                        if session.status == .connecting {
                            session.status = .streaming
                        }
                        mgr.processStreamLine(capturedLine, session: session)
                    }
                }
            }
        }

        // Handle process termination
        process.terminationHandler = { proc in
            let exitCode = proc.terminationStatus
            logTiming("[TIMING] Process exited (code: \(exitCode))")
            DispatchQueue.main.async {
                session.process = nil
                if session.status == .streaming || session.status == .connecting {
                    if exitCode != 0 {
                        session.status = .error("Process exited with code \(exitCode)")
                    } else {
                        // Normal exit — mark as done if result event didn't already
                        if session.status != .done {
                            session.status = .done
                        }
                    }
                }
            }
        }
    }
}
