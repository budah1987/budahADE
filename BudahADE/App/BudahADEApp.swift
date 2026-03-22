import SwiftUI

@main
struct BudahADEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .background(Theme.appBackground)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Agent Tab") {
                    NotificationCenter.default.post(name: .newTerminalTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeTerminalTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Rename Tab") {
                    NotificationCenter.default.post(name: .renameTab, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Rename Task") {
                    NotificationCenter.default.post(name: .renameTask, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Toggle Plan/Build") {
                    NotificationCenter.default.post(name: .toggleTaskMode, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Reset Zoom") {
                    NotificationCenter.default.post(name: .canvasResetZoom, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Zoom to Fit") {
                    NotificationCenter.default.post(name: .canvasZoomToFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Divider()

                Button("Switch Workspace") {
                    NotificationCenter.default.post(name: .toggleWorkspaceSwitcher, object: nil)
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Left Panel") {
                    NotificationCenter.default.post(name: .toggleLeftPanel, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }

            // Cmd+1..9 — switch agent tabs within active task
            CommandGroup(after: .windowArrangement) {
                tabShortcutButton(1, key: "1")
                tabShortcutButton(2, key: "2")
                tabShortcutButton(3, key: "3")
                tabShortcutButton(4, key: "4")
                tabShortcutButton(5, key: "5")
                tabShortcutButton(6, key: "6")
                tabShortcutButton(7, key: "7")
                tabShortcutButton(8, key: "8")
                tabShortcutButton(9, key: "9")

                Divider()

                // Ctrl+1..9 — switch tasks
                taskShortcutButton(1, key: "1")
                taskShortcutButton(2, key: "2")
                taskShortcutButton(3, key: "3")
                taskShortcutButton(4, key: "4")
                taskShortcutButton(5, key: "5")
                taskShortcutButton(6, key: "6")
                taskShortcutButton(7, key: "7")
                taskShortcutButton(8, key: "8")
                taskShortcutButton(9, key: "9")
            }
        }
    }

    private func tabShortcutButton(_ index: Int, key: String) -> some View {
        Button("Agent Tab \(index)") {
            NotificationCenter.default.post(
                name: .selectTabByIndex,
                object: nil,
                userInfo: ["index": index]
            )
        }
        .keyboardShortcut(SwiftUI.KeyEquivalent(Character(key)), modifiers: .command)
    }

    private func taskShortcutButton(_ index: Int, key: String) -> some View {
        Button("Task \(index)") {
            NotificationCenter.default.post(
                name: .selectTaskByIndex,
                object: nil,
                userInfo: ["index": index]
            )
        }
        .keyboardShortcut(SwiftUI.KeyEquivalent(Character(key)), modifiers: .control)
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var workspaces: [WorkspaceState] = []
    @Published var activeWorkspaceIndex: Int = 0
    @Published var isWorkspaceSwitcherOpen: Bool = false

    var hasNoWorkspaces: Bool { workspaces.isEmpty }

    var activeWorkspace: WorkspaceState? {
        guard !workspaces.isEmpty, activeWorkspaceIndex < workspaces.count else { return nil }
        return workspaces[activeWorkspaceIndex]
    }

    func openProject(_ project: ProjectInfo) {
        if let existingIndex = workspaces.firstIndex(where: { $0.projectPath == project.path }) {
            activeWorkspaceIndex = existingIndex
            return
        }
        let workspace = WorkspaceState(projectPath: project.path)
        workspaces.append(workspace)
        activeWorkspaceIndex = workspaces.count - 1
    }

    func closeWorkspace(at index: Int) {
        guard index < workspaces.count else { return }
        let workspace = workspaces[index]
        // Close all task terminals
        for task in workspace.tasks {
            task.closeAllTerminals()
        }
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            activeWorkspaceIndex = 0
        } else if activeWorkspaceIndex >= workspaces.count {
            activeWorkspaceIndex = workspaces.count - 1
        }
    }

    func switchToWorkspace(at index: Int) {
        guard index >= 0, index < workspaces.count else { return }
        activeWorkspaceIndex = index
    }
}

// MARK: - Project Info

struct ProjectInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let lastModified: Date?
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()

            if appState.hasNoWorkspaces {
                ProjectPickerView()
            } else if let workspace = appState.activeWorkspace {
                WorkspaceView(state: workspace)
                    .id(workspace.id)
            }
        }
        .toolbar {
            // Empty — workspace dropdown is now in the task rail
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newTerminalTab = Notification.Name("budahADE.newTerminalTab")
    static let closeTerminalTab = Notification.Name("budahADE.closeTerminalTab")
    static let toggleLeftPanel = Notification.Name("budahADE.toggleLeftPanel")
    static let splitRight = Notification.Name("budahADE.splitRight")
    static let splitDown = Notification.Name("budahADE.splitDown")
    static let selectTabByIndex = Notification.Name("budahADE.selectTabByIndex")
    static let toggleWorkspaceSwitcher = Notification.Name("budahADE.toggleWorkspaceSwitcher")
    static let newTask = Notification.Name("budahADE.newTask")
    static let selectTaskByIndex = Notification.Name("budahADE.selectTaskByIndex")
    static let renameTab = Notification.Name("budahADE.renameTab")
    static let renameTask = Notification.Name("budahADE.renameTask")
    static let toggleTaskMode = Notification.Name("budahADE.toggleTaskMode")
    static let canvasResetZoom = Notification.Name("budahADE.canvasResetZoom")
    static let canvasZoomToFit = Notification.Name("budahADE.canvasZoomToFit")
}
