import Foundation
import Combine

@MainActor
final class SpecWatcher {
    let specState: SpecState
    private var timer: Timer?
    private let worktreePath: String
    private var lastContent: String?

    init(worktreePath: String, specState: SpecState) {
        self.worktreePath = worktreePath
        self.specState = specState
    }

    func startWatching() {
        // Initial check
        checkForChanges()

        // Poll every 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let specFiles = SpecParser.findSpecFiles(in: worktreePath)

        guard let firstSpec = specFiles.first else {
            if specState.hasSpec {
                specState.update(from: nil)
            }
            return
        }

        // Only re-parse if content changed
        if let content = try? String(contentsOfFile: firstSpec, encoding: .utf8) {
            if content != lastContent {
                lastContent = content
                let result = SpecParser.parse(fileAt: firstSpec)
                specState.update(from: result)
            }
        }
    }
}
