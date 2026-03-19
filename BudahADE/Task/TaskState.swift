import Foundation
import Combine

// MARK: - Task Status

enum TaskStatus {
    case active
    case completed
}

// MARK: - Task State

@MainActor
final class TaskState: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var branchName: String
    let worktreePath: String
    let repoPath: String
    @Published var status: TaskStatus = .active
    @Published var tabs: [TabInfo] = []
    @Published var selectedTabId: UUID?
    @Published var terminals: [UUID: TerminalPanel] = [:]

    private var cancellables = Set<AnyCancellable>()

    init(
        id: UUID = UUID(),
        name: String,
        branchName: String,
        worktreePath: String,
        repoPath: String
    ) {
        self.id = id
        self.name = name
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.repoPath = repoPath

        // Create first terminal in the worktree
        createTab()
        autoLaunchClaude()
        observeTitleChanges()
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab() -> UUID {
        let panel = TerminalPanel(workingDirectory: worktreePath)
        let id = panel.id
        let tab = TabInfo(id: id, title: "Terminal", isRunning: false)
        tabs.append(tab)
        terminals[id] = panel
        selectedTabId = id
        return id
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        terminals[id]?.close()
        terminals.removeValue(forKey: id)
        tabs.remove(at: index)

        if selectedTabId == id {
            if !tabs.isEmpty {
                selectedTabId = tabs[min(index, tabs.count - 1)].id
            } else {
                selectedTabId = nil
            }
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabId = id
    }

    func selectTabByIndex(_ index: Int) {
        guard !tabs.isEmpty else { return }
        if index == 9 {
            selectedTabId = tabs.last?.id
            return
        }
        let zeroIndex = index - 1
        guard zeroIndex >= 0, zeroIndex < tabs.count else { return }
        selectedTabId = tabs[zeroIndex].id
    }

    // MARK: - Focus Management

    func focusActiveTerminal() {
        if let id = selectedTabId, let panel = terminals[id] {
            panel.focus()
        }
    }

    func unfocusAllTerminals() {
        for panel in terminals.values {
            panel.unfocus()
        }
    }

    // MARK: - Close All

    func closeAllTerminals() {
        for panel in terminals.values {
            panel.close()
        }
        terminals.removeAll()
        tabs.removeAll()
        selectedTabId = nil
    }

    // MARK: - Private

    private func autoLaunchClaude() {
        guard let firstTabId = tabs.first?.id,
              let panel = terminals[firstTabId] else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            panel.sendCommand("claude")
        }
    }

    private func observeTitleChanges() {
        NotificationCenter.default.publisher(for: .terminalTitleChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let info = notification.userInfo,
                      let surfaceId = info["surfaceId"] as? UUID,
                      let title = info["title"] as? String,
                      let index = self.tabs.firstIndex(where: { $0.id == surfaceId }) else { return }
                self.tabs[index].title = title
            }
            .store(in: &cancellables)
    }
}
