import SwiftUI

struct GitSidebarView: View {
    @ObservedObject var taskState: TaskState
    @StateObject private var repo: GitRepository
    @State private var panelWidth: CGFloat = 320
    @State private var isDragging: Bool = false
    @State private var commitMessage: String = ""
    @State private var expandedSection: SidebarSection? = .unstaged
    @State private var pushState: ActionState = .idle
    @State private var mergeState: ActionState = .idle
    @State private var actionError: String?
    @State private var diffFile: GitFileStatus?
    @State private var diffStaged: Bool = false
    @State private var showDiffPopover: Bool = false

    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 420

    enum SidebarSection { case unstaged, staged, commits }
    enum ActionState { case idle, loading, success }

    init(task: TaskState) {
        self.taskState = task
        _repo = StateObject(wrappedValue: GitRepository(path: task.worktreePath))
    }

    var body: some View {
        HStack(spacing: 0) {
            dragHandle

            VStack(spacing: 0) {
                // Branch flow header
                BranchFlowView(
                    sourceBranch: repo.currentBranch.isEmpty ? taskState.branchName : repo.currentBranch,
                    targetBranch: taskState.baseBranch
                )

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 0.5)

                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        unstagedSection
                        stagedSection
                        commitSection
                        commitsSection
                    }
                }

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 0.5)

                // Error banner
                if let error = actionError {
                    errorBanner(error)
                }

                // Action bar
                actionBar
            }
            .frame(width: panelWidth)
            .background(Theme.sidebar)
        }
        .onAppear { repo.startPolling() }
        .onDisappear { repo.stopPolling() }
    }

    // MARK: - Unstaged Section

    private var unstagedSection: some View {
        sectionView(
            title: "UNSTAGED",
            count: repo.unstagedFiles.count,
            section: .unstaged,
            trailing: {
                if !repo.unstagedFiles.isEmpty {
                    Button("Stage All") { repo.stageAll() }
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.accent)
                        .buttonStyle(.plain)
                }
            }
        ) {
            VStack(spacing: 0) {
                ForEach(repo.unstagedFiles) { file in
                    fileRow(file, staged: false)
                }
                if repo.unstagedFiles.isEmpty {
                    emptyState("No changes yet")
                }
            }
        }
    }

    // MARK: - Staged Section

    private var stagedSection: some View {
        sectionView(
            title: "STAGED",
            count: repo.stagedFiles.count,
            section: .staged,
            trailing: {
                if !repo.stagedFiles.isEmpty {
                    Button("Unstage All") { repo.unstageAll() }
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textSecondary)
                        .buttonStyle(.plain)
                }
            }
        ) {
            VStack(spacing: 0) {
                ForEach(repo.stagedFiles) { file in
                    fileRow(file, staged: true)
                }
                if repo.stagedFiles.isEmpty {
                    emptyState("No staged files")
                }
            }
        }
    }

    // MARK: - Commit Section

    private var commitSection: some View {
        Group {
            if !repo.stagedFiles.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("COMMIT MESSAGE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.8)

                        Spacer()

                        Button {
                            commitMessage = repo.generateCommitMessage()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                Text("Auto-generate")
                                    .font(Theme.caption(10))
                            }
                            .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Describe your changes...", text: $commitMessage, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(Theme.surface3)
                        .cornerRadius(Theme.pillCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                                .stroke(Theme.borderSubtle, lineWidth: 0.5)
                        )

                    Button {
                        repo.commit(message: commitMessage.trimmingCharacters(in: .whitespaces))
                        commitMessage = ""
                    } label: {
                        Text("Commit")
                            .font(Theme.label(12))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                canCommit
                                    ? Theme.accent.opacity(0.85)
                                    : Theme.accent.opacity(0.3)
                            )
                            .cornerRadius(Theme.pillCornerRadius)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .onChange(of: repo.stagedFiles.count) { oldCount, newCount in
            // Auto-populate commit message when files are first staged
            if oldCount == 0 && newCount > 0 && commitMessage.isEmpty {
                commitMessage = repo.generateCommitMessage()
            }
        }
    }

    private var canCommit: Bool {
        !repo.stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Commits Section

    private var commitsSection: some View {
        sectionView(
            title: "COMMITS",
            count: repo.recentCommits.count,
            section: .commits,
            trailing: { EmptyView() }
        ) {
            VStack(spacing: 0) {
                ForEach(repo.recentCommits) { commit in
                    commitRow(commit)
                }
                if repo.recentCommits.isEmpty {
                    emptyState("No commits yet")
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 6) {
            // Push button (primary)
            Button {
                performPush()
            } label: {
                HStack(spacing: 6) {
                    if pushState == .loading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: pushState == .success ? "checkmark.circle" : "arrow.up.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text(pushButtonLabel)
                        .font(Theme.label(12))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(pushState == .loading ? 0.5 : 0.85))
                .cornerRadius(Theme.pillCornerRadius)
            }
            .buttonStyle(.plain)
            .disabled(pushState == .loading)

            // Secondary actions
            HStack(spacing: 6) {
                Button {
                    repo.openPullRequestURL(baseBranch: taskState.baseBranch)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 10, weight: .medium))
                        Text("Create PR")
                            .font(Theme.label(11))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.surface3)
                    .cornerRadius(Theme.pillCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                            .stroke(Theme.borderSubtle, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    performMerge()
                } label: {
                    HStack(spacing: 4) {
                        if mergeState == .loading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: mergeState == .success ? "checkmark" : "arrow.triangle.merge")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text("Merge")
                            .font(Theme.label(11))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Theme.surface3)
                    .cornerRadius(Theme.pillCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                            .stroke(Theme.borderSubtle, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(mergeState == .loading)
            }
        }
        .padding(12)
    }

    private var pushButtonLabel: String {
        if pushState == .success { return "Pushed" }
        if pushState == .loading { return "Pushing..." }
        if repo.aheadCount > 0 { return "Push (\(repo.aheadCount) ahead)" }
        return "Push to Remote"
    }

    // MARK: - Actions

    private func performPush() {
        pushState = .loading
        actionError = nil
        Task {
            do {
                try await repo.push()
                await MainActor.run {
                    pushState = .success
                    // Reset after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        pushState = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    pushState = .idle
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func performMerge() {
        mergeState = .loading
        actionError = nil
        Task {
            do {
                try await repo.mergeIntoBase(taskState.baseBranch)
                await MainActor.run {
                    mergeState = .success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        mergeState = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    mergeState = .idle
                    actionError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Reusable Section

    @ViewBuilder
    private func sectionView<Trailing: View, Content: View>(
        title: String,
        count: Int,
        section: SidebarSection,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedSection = expandedSection == section ? nil : section
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedSection == section ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 10)

                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .tracking(0.8)

                    if count > 0 {
                        Text("\(count)")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.surface3)
                            .cornerRadius(4)
                    }

                    Spacer()

                    trailing()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSection == section {
                content()
            }
        }
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileRow(_ file: GitFileStatus, staged: Bool) -> some View {
        HStack(spacing: 8) {
            statusBadge(file.status)

            Text(file.path)
                .font(Theme.mono(11))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                if staged { repo.unstage(file.path) } else { repo.stage(file.path) }
            } label: {
                Image(systemName: staged ? "minus" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 16, height: 16)
                    .background(Theme.hoverFill)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            diffFile = file
            diffStaged = staged
            showDiffPopover = true
        }
        .popover(isPresented: Binding(
            get: { showDiffPopover && diffFile?.path == file.path },
            set: { if !$0 { showDiffPopover = false } }
        )) {
            VStack(spacing: 0) {
                HStack {
                    Text(file.path)
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                }
                .padding(8)
                .background(Theme.surface2)

                DiffView(diff: repo.diff(file: file.path, staged: staged))
                    .frame(width: 480, height: 320)
            }
            .background(Theme.appBackground)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(statusColor(status))
            .frame(width: 14, height: 14)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.warning
        case "A": return Theme.success
        case "D": return Theme.error
        case "R": return Theme.info
        case "?": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    // MARK: - Commit Row

    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.message)
                .font(Theme.body(11))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(String(commit.id.prefix(7)))
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.accent.opacity(0.7))
                Text(commit.date)
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
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

            Button {
                actionError = nil
            } label: {
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

    // MARK: - Empty State

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(11))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(isDragging ? Theme.accent.opacity(0.3) : Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        // Dragging left (negative) = wider panel
                        let newWidth = panelWidth - value.translation.width
                        panelWidth = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
