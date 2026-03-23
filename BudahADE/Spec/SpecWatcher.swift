import Foundation
import Combine

@MainActor
final class SpecWatcher {
    let specState: SpecState
    private var timer: Timer?
    private let worktreePath: String
    private var lastContents: [String: String] = [:]  // path → content

    // Adaptive polling
    private let normalInterval: TimeInterval = 2.0
    private let rapidInterval: TimeInterval = 0.5
    private let rapidPollMax = 20  // 20 × 0.5s = 10s of rapid polling
    private var rapidPollCount = 0

    init(worktreePath: String, specState: SpecState) {
        self.worktreePath = worktreePath
        self.specState = specState
    }

    func startWatching() {
        checkForChanges()
        scheduleTimer(interval: normalInterval)
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    private func checkForChanges() {
        let specFiles = SpecParser.findSpecFiles(in: worktreePath)

        guard !specFiles.isEmpty else {
            if specState.hasSpec {
                lastContents.removeAll()
                specState.updateAll(from: [])
            }
            tickRapidPoll(changed: false)
            return
        }

        // Read all spec files, check for content changes
        var changed = false
        var currentContents: [String: String] = [:]
        var results: [SpecParseResult] = []

        for path in specFiles {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            currentContents[path] = content

            if content != lastContents[path] {
                changed = true
            }

            if let result = SpecParser.parse(fileAt: path) {
                results.append(result)
            }
        }

        // Check for removed files
        if lastContents.keys.count != currentContents.keys.count {
            changed = true
        }

        if changed {
            lastContents = currentContents
            specState.updateAll(from: results)
        }

        tickRapidPoll(changed: changed)
    }

    // MARK: - Adaptive Polling

    private func tickRapidPoll(changed: Bool) {
        if changed {
            // Switch to rapid polling
            rapidPollCount = rapidPollMax
            scheduleTimer(interval: rapidInterval)
        } else if rapidPollCount > 0 {
            rapidPollCount -= 1
            if rapidPollCount == 0 {
                // Return to normal polling
                scheduleTimer(interval: normalInterval)
            }
        }
    }
}
