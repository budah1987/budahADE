import SwiftUI

struct GitSidebarView: View {
    @ObservedObject var taskState: TaskState
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

    init(task: TaskState) {
        self.taskState = task
        _repo = StateObject(wrappedValue: GitRepository(path: task.worktreePath))
    }

    var body: some View {
        HStack(spacing: 0) {
            dragHandle

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        BranchHeaderView(repo: repo)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)

                        Divider().foregroundColor(Theme.borderSubtle)

                        ChangesListView(repo: repo) { file, staged in
                            openDiffForFile(file, staged: staged)
                        }

                        Divider().foregroundColor(Theme.borderSubtle)

                        CommitBarView(repo: repo, commitMessage: $commitMessage)

                        Divider().foregroundColor(Theme.borderSubtle)

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
            .background(Theme.sidebar)
            .onAppear {
                repo.mergeTarget = taskState.baseBranch
                repo.startPolling()
            }
            .onDisappear { repo.stopPolling() }
        }
        .sheet(isPresented: $showDiffModal) {
            DiffModalView(
                repo: repo,
                files: diffFiles,
                initialFileIndex: diffFileIndex,
                staged: diffStaged,
                commitHash: diffCommitHash
            )
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
        diffFiles = repo.filesChangedInCommit(commit.id)
        diffFileIndex = 0
        diffStaged = false
        diffCommitHash = commit.id
        showDiffModal = true
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
                .foregroundColor(Theme.appBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Theme.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(pushState == .loading)

            Button {
                repo.openPullRequestURL(baseBranch: repo.mergeTarget)
            } label: {
                Text("PR")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surface3)
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
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.surface3)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(mergeState == .loading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.sidebar)
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
                .foregroundColor(Theme.error)

            Text(message)
                .font(Theme.caption(11))
                .foregroundColor(Theme.error)
                .lineLimit(2)

            Spacer()

            Button { actionError = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.error.opacity(0.08))
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(isDragging ? Theme.accent.opacity(0.3) : Color.clear)
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
