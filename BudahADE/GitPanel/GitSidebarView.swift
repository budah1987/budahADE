import SwiftUI
import AppKit

struct GitSidebarView: View {
    @ObservedObject var taskState: TaskState
    let projectPath: String
    @StateObject private var repo: GitRepository
    @State private var panelWidth: CGFloat = 320
    @State private var isDragging: Bool = false
    @State private var commitMessage: String = ""
    @State private var pushState: ActionState = .idle
    @State private var mergeState: ActionState = .idle
    @State private var actionError: String?
    @State private var showDiffModal = false
    @State private var diffFiles: [GitFileStatus] = []
    @State private var diffFileIndex: Int = 0
    @State private var diffStaged: Bool = false
    @State private var diffCommitHash: String?

    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 420

    enum ActionState { case idle, loading, success }

    init(task: TaskState, projectPath: String) {
        self.taskState = task
        self.projectPath = projectPath
        _repo = StateObject(wrappedValue: GitRepository(path: task.worktreePath))
    }

    var body: some View {
        HStack(spacing: 0) {
            dragHandle

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        BranchHeaderView(repo: repo, projectPath: projectPath)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)

                        Divider().foregroundColor(Theme.Colors.borderSubtle)

                        ChangesListView(repo: repo) { file, staged in
                            openDiffForFile(file, staged: staged)
                        }

                        Divider().foregroundColor(Theme.Colors.borderSubtle)

                        CommitBarView(repo: repo, commitMessage: $commitMessage)

                        Divider().foregroundColor(Theme.Colors.borderSubtle)

                        CommitHistoryView(repo: repo) { commit in
                            openDiffForCommit(commit)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let error = actionError {
                    errorBanner(error)
                }

                actionBar
            }
            .frame(width: panelWidth)
            .background(Theme.Colors.sidebarBackground)
            .onAppear {
                repo.mergeTarget = taskState.baseBranch
                repo.startPolling()
            }
            .onDisappear { repo.stopPolling() }
        }
        .onChange(of: showDiffModal) { _, show in
            if show {
                presentDiffWindow()
            }
        }
    }

    // MARK: - Diff Modal Triggers

    private func openDiffForFile(_ file: GitFileStatus, staged: Bool) {
        let fileList = staged ? repo.stagedFiles : repo.unstagedFiles
        diffFiles = fileList
        diffFileIndex = fileList.firstIndex(where: { $0.path == file.path }) ?? 0
        diffStaged = staged
        diffCommitHash = nil
        showDiffModal = true
    }

    private func openDiffForCommit(_ commit: GitCommit) {
        Task {
            let files = repo.filesChangedInCommit(commit.id)
            diffFiles = files
            diffFileIndex = 0
            diffStaged = false
            diffCommitHash = commit.id
            showDiffModal = true
        }
    }

    private func presentDiffWindow() {
        let content = DiffModalView(
            repo: repo,
            files: diffFiles,
            initialFileIndex: diffFileIndex,
            staged: diffStaged,
            commitHash: diffCommitHash
        )

        let hostingView = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = currentFile(diffFiles, diffFileIndex)
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 500, height: 350)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.makeKeyAndOrderFront(nil)

        showDiffModal = false
    }

    private func currentFile(_ files: [GitFileStatus], _ index: Int) -> String {
        guard index >= 0, index < files.count else { return "Diff" }
        return (files[index].path as NSString).lastPathComponent
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button { performPush() } label: {
                HStack(spacing: 4) {
                    if pushState == .loading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(pushButtonLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Theme.Colors.appBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.Colors.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(pushState == .loading)

            Button {
                repo.openPullRequestURL(baseBranch: repo.mergeTarget)
            } label: {
                Text("PR")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button { performMerge() } label: {
                HStack(spacing: 4) {
                    if mergeState == .loading {
                        ProgressView().controlSize(.mini)
                    }
                    Text(mergeState == .success ? "Merged ✓" : "Merge")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(mergeState == .loading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.sidebarBackground)
    }

    private var pushButtonLabel: String {
        switch pushState {
        case .loading: return "Pushing..."
        case .success: return "Pushed ✓"
        case .idle:
            return repo.aheadCount > 0 ? "Push (\(repo.aheadCount))" : "Push"
        }
    }

    // MARK: - Actions

    private func performPush() {
        pushState = .loading
        Task {
            do {
                try await repo.push()
                await MainActor.run {
                    pushState = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { pushState = .idle }
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    pushState = .idle
                }
            }
        }
    }

    private func performMerge() {
        mergeState = .loading
        Task {
            do {
                try await repo.mergeIntoBase(repo.mergeTarget)
                await MainActor.run {
                    mergeState = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { mergeState = .idle }
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    mergeState = .idle
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.Colors.error)

            Text(message)
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.error)
                .lineLimit(2)

            Spacer()

            Button { actionError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.error.opacity(0.08))
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(isDragging ? Theme.Colors.accent.opacity(0.3) : Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in isDragging = false }
            )
    }
}
