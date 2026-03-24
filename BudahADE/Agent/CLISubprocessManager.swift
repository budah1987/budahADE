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

    // MARK: - Private: Run Subprocess

    private nonisolated func runSubprocess(command: [String], session: AgentSession) async {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let workDir = await session.workingDirectory
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)

        await MainActor.run { session.process = process }

        do {
            try process.run()
        } catch {
            await MainActor.run {
                session.status = .error("Failed to launch: \(error.localizedDescription)")
                session.process = nil
            }
            return
        }

        // Read stdout line by line
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while process.isRunning || !buffer.isEmpty {
            let chunk = handle.availableData
            if chunk.isEmpty && !process.isRunning { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                if let line = String(data: lineData, encoding: .utf8) {
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
        await MainActor.run {
            session.process = nil
            if session.status == .streaming { session.status = .done }
        }
    }
}
