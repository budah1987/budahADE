import Foundation
import CoreServices

/// Watches a worktree for file changes and reloads the browser after dev server
/// rebuilds. Primary signal: build-complete message in stdout. Fallback: 3-second
/// timer after any file change.
final class SmartReloader {

    /// Called on main queue when a reload should happen.
    var onReloadNeeded: (() -> Void)?

    private(set) var isWatching = false

    private var eventStream: FSEventStreamRef?
    private var pendingReload: DispatchWorkItem?

    // Build-complete patterns across common dev servers (vite, next, webpack, parcel, turbopack)
    private static let buildCompletePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"compiled\s+(?:\S+\s+)*successfully"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"ready\s+in\s+\d+"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"built\s+in\s+\d+"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"webpack\s+compiled"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"hmr\s+update"#, options: .caseInsensitive),
        try! NSRegularExpression(pattern: #"✓\s+\d+\s+module"#),
    ]

    // MARK: - Public

    func startWatching(worktreePath: String) {
        stopWatching()

        let paths = [worktreePath] as CFArray
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(version: 0, info: selfPtr, retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let reloader = Unmanaged<SmartReloader>.fromOpaque(info).takeUnretainedValue()
            reloader.handleFileChange()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,    // coalesce events within 300ms window
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        eventStream = stream
        isWatching = true
    }

    func stopWatching() {
        pendingReload?.cancel()
        pendingReload = nil
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isWatching = false
    }

    /// Called by DevServerManager for each stdout chunk.
    /// If a build-complete message is detected, cancels the fallback timer and reloads immediately.
    func handleStdoutChunk(_ text: String) {
        let range = NSRange(text.startIndex..., in: text)
        let matched = Self.buildCompletePatterns.contains { $0.firstMatch(in: text, range: range) != nil }
        if matched {
            reloadNow()
        }
    }

    // MARK: - Private

    private func handleFileChange() {
        // Only arm the fallback if not already armed — first change starts the clock
        guard pendingReload == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingReload = nil
            self?.onReloadNeeded?()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func reloadNow() {
        pendingReload?.cancel()
        pendingReload = nil
        DispatchQueue.main.async { [weak self] in self?.onReloadNeeded?() }
    }

    deinit {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
