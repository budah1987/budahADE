import Foundation

// MARK: - ConnectionSummaryManager

@MainActor
final class ConnectionSummaryManager: ObservableObject {
    static let maxConcurrentSummaries = 3

    @Published private(set) var activeSummaryCount: Int = 0
    private var pendingQueue: [(UUID, String)] = []  // (connectionId, inputText)
    private var inFlightIds: Set<UUID> = []
    weak var canvas: PlanCanvasState?

    /// Returns cached summary if fresh, nil if generating
    func resolvedSummary(for connection: inout TileConnection, output: TileOutput) -> String? {
        if connection.cachedSummary != nil { return connection.cachedSummary }
        if inFlightIds.contains(connection.id) { return nil }
        let text = output.textRepresentation
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        enqueue(connectionId: connection.id, inputText: text)
        return nil
    }

    func completeSummary(connectionId: UUID, summary: String) {
        inFlightIds.remove(connectionId)
        activeSummaryCount = inFlightIds.count
        if let canvas, let idx = canvas.connections.firstIndex(where: { $0.id == connectionId }) {
            canvas.connections[idx].cachedSummary = summary
            canvas.connections[idx].summaryTimestamp = Date()
        }
        drainQueue()
    }

    private func enqueue(connectionId: UUID, inputText: String) {
        if inFlightIds.count < Self.maxConcurrentSummaries {
            startGeneration(connectionId: connectionId, inputText: inputText)
        } else {
            pendingQueue.append((connectionId, inputText))
        }
    }

    private func drainQueue() {
        while inFlightIds.count < Self.maxConcurrentSummaries, !pendingQueue.isEmpty {
            let (id, text) = pendingQueue.removeFirst()
            guard canvas?.connections.contains(where: { $0.id == id }) == true else { continue }
            startGeneration(connectionId: id, inputText: text)
        }
    }

    private func startGeneration(connectionId: UUID, inputText: String) {
        inFlightIds.insert(connectionId)
        activeSummaryCount = inFlightIds.count
        let truncated = String(inputText.prefix(2000))
        let prompt = "Summarize this concisely for a developer in 2-3 sentences:\n\n\(truncated)"

        Task {
            let summary = await runHaikuSummary(prompt: prompt)
            await MainActor.run { [weak self] in
                self?.completeSummary(connectionId: connectionId, summary: summary)
            }
        }
    }

    nonisolated private func runHaikuSummary(prompt: String) async -> String {
        let claudeBin = CLISubprocessManager.claudePath
        let process = Process()
        if claudeBin == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "-p", prompt, "--model", "haiku", "--max-turns", "1"]
        } else {
            process.executableURL = URL(fileURLWithPath: claudeBin)
            process.arguments = ["-p", prompt, "--model", "haiku", "--max-turns", "1"]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(10.0)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                return String(prompt.prefix(200))
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? String(prompt.prefix(200)) : output
        } catch {
            return String(prompt.prefix(200))
        }
    }
}
