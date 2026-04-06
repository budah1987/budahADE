import Foundation

@MainActor
final class SpecWatcher {
    let specState: SpecState
    private let worktreePath: String
    private var lastContents: [String: String] = [:]

    // Event-driven watching via DispatchSourceFileSystemObject
    private var source: DispatchSourceFileSystemObject?
    private var dirFd: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private let debounceMs = 500

    // Fallback timer when .budahade/ doesn't exist yet
    private var fallbackTimer: Timer?
    private let fallbackInterval: TimeInterval = 5.0

    private var budahadeDir: String {
        (worktreePath as NSString).appendingPathComponent(".budahade")
    }

    init(worktreePath: String, specState: SpecState) {
        self.worktreePath = worktreePath
        self.specState = specState
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
            // Directory doesn't exist yet — poll slowly until it appears
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
        let specFiles = SpecParser.findSpecFiles(in: worktreePath)

        guard !specFiles.isEmpty else {
            if specState.hasSpec {
                lastContents.removeAll()
                specState.updateAll(from: [])
            }
            return
        }

        var changed = false
        var currentContents: [String: String] = [:]
        var results: [SpecParseResult] = []

        for path in specFiles {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            currentContents[path] = content
            if content != lastContents[path] { changed = true }
            if let result = SpecParser.parse(fileAt: path) {
                results.append(result)
            }
        }

        if lastContents.keys.count != currentContents.keys.count { changed = true }

        if changed {
            lastContents = currentContents
            specState.updateAll(from: results)
        }
    }
}
