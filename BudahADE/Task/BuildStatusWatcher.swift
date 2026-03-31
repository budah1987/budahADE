import Foundation
import Combine

/// Polls `.budahade/build-status.json` for real-time build progress
@MainActor
final class BuildStatusWatcher {
    let buildStatus: BuildStatusState
    private var timer: Timer?
    private let worktreePath: String
    private var lastContent: String = ""

    // Adaptive polling (same pattern as SpecWatcher)
    private let normalInterval: TimeInterval = 2.0
    private let rapidInterval: TimeInterval = 0.5
    private let rapidPollMax = 20
    private var rapidPollCount = 0

    init(worktreePath: String, buildStatus: BuildStatusState) {
        self.worktreePath = worktreePath
        self.buildStatus = buildStatus
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
        let statusPath = (worktreePath as NSString)
            .appendingPathComponent(".budahade/build-status.json")

        guard let content = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            tickRapidPoll(changed: false)
            return
        }

        let changed = content != lastContent
        if changed {
            lastContent = content
            parseStatus(content)
        }

        tickRapidPoll(changed: changed)
    }

    private func parseStatus(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let previousTask = buildStatus.currentTaskTitle
        buildStatus.currentTaskTitle = dict["currentTask"] as? String
        buildStatus.currentTaskIndex = dict["taskIndex"] as? Int
        buildStatus.lastAction = dict["lastAction"] as? String
        buildStatus.blockers = dict["blockers"] as? String

        if let statusStr = dict["status"] as? String {
            switch statusStr {
            case "working":   buildStatus.status = .working
            case "blocked":   buildStatus.status = .blocked
            case "completed": buildStatus.status = .completed
            default:          buildStatus.status = .idle
            }
        }

        // Track elapsed time per task
        if buildStatus.currentTaskTitle != previousTask {
            buildStatus.taskStartedAt = Date()
        }
    }

    // MARK: - Adaptive Polling

    private func tickRapidPoll(changed: Bool) {
        if changed {
            rapidPollCount = rapidPollMax
            scheduleTimer(interval: rapidInterval)
        } else if rapidPollCount > 0 {
            rapidPollCount -= 1
            if rapidPollCount == 0 {
                scheduleTimer(interval: normalInterval)
            }
        }
    }
}
