import Foundation

/// Watches `.budahade/build-status.json` for real-time build progress.
/// Event-driven via DispatchSourceFileSystemObject — zero CPU when idle.
@MainActor
final class BuildStatusWatcher {
    let buildStatus: BuildStatusState
    private let worktreePath: String
    private var lastContent: String = ""

    // Event-driven watching
    private var source: DispatchSourceFileSystemObject?
    private var dirFd: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private let debounceMs = 200

    // Fallback timer when .budahade/ doesn't exist yet
    private var fallbackTimer: Timer?
    private let fallbackInterval: TimeInterval = 5.0

    private var budahadeDir: String {
        (worktreePath as NSString).appendingPathComponent(".budahade")
    }

    private var statusPath: String {
        (worktreePath as NSString).appendingPathComponent(".budahade/build-status.json")
    }

    init(worktreePath: String, buildStatus: BuildStatusState) {
        self.worktreePath = worktreePath
        self.buildStatus = buildStatus
    }

    func startWatching() {
        checkForChanges()
        attemptDirectoryWatch()
    }

    func stopWatching() {
        stopSource()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    // MARK: - Private

    private func attemptDirectoryWatch() {
        let fd = open(budahadeDir, O_EVTONLY)
        if fd >= 0 {
            startSource(fd: fd)
        } else {
            startFallbackTimer()
        }
    }

    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: fallbackInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.checkForChanges()
                let fd = open(self.budahadeDir, O_EVTONLY)
                if fd >= 0 {
                    self.fallbackTimer?.invalidate()
                    self.fallbackTimer = nil
                    self.startSource(fd: fd)
                }
            }
        }
    }

    private func startSource(fd: Int32) {
        stopSource()
        dirFd = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            self?.scheduleCheck()
        }

        src.setCancelHandler { [weak self] in
            guard let self, self.dirFd >= 0 else { return }
            close(self.dirFd)
            self.dirFd = -1
        }

        src.resume()
        source = src
    }

    private func stopSource() {
        debounceWork?.cancel()
        debounceWork = nil
        if let src = source {
            src.cancel()
            source = nil
        } else if dirFd >= 0 {
            close(dirFd)
            dirFd = -1
        }
    }

    private func scheduleCheck() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.checkForChanges() }
        }
        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(debounceMs),
            execute: work
        )
    }

    private func checkForChanges() {
        guard let content = try? String(contentsOfFile: statusPath, encoding: .utf8) else { return }
        guard content != lastContent else { return }
        lastContent = content
        parseStatus(content)
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

        if buildStatus.currentTaskTitle != previousTask || (buildStatus.status == .working && buildStatus.taskStartedAt == nil) {
            buildStatus.taskStartedAt = Date()
        }
    }
}
