import SwiftUI

struct ChangesPanel: View {
    let worktreePath: String
    @StateObject private var repo: GitRepository

    init(worktreePath: String) {
        self.worktreePath = worktreePath
        _repo = StateObject(wrappedValue: GitRepository(path: worktreePath))
    }

    @State private var commitMessage: String = ""
    @State private var expandedSection: Section? = .unstaged

    enum Section { case unstaged, staged, commits }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                branchHeader

                sectionView(
                    title: "Unstaged",
                    count: repo.unstagedFiles.count,
                    section: .unstaged
                ) {
                    VStack(spacing: 0) {
                        ForEach(repo.unstagedFiles) { file in
                            fileRow(file, staged: false)
                        }
                        if !repo.unstagedFiles.isEmpty {
                            Button("Stage All") { repo.stageAll() }
                                .buttonStyle(PillButtonStyle())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                    }
                }

                sectionView(
                    title: "Staged",
                    count: repo.stagedFiles.count,
                    section: .staged
                ) {
                    VStack(spacing: 0) {
                        ForEach(repo.stagedFiles) { file in
                            fileRow(file, staged: true)
                        }
                        if !repo.stagedFiles.isEmpty {
                            VStack(spacing: 6) {
                                TextField("Commit message", text: $commitMessage, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(Theme.body(12))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(8)
                                    .background(Theme.surface3)
                                    .cornerRadius(Theme.pillCornerRadius)
                                    .lineLimit(3)
                                    .padding(.horizontal, 12)

                                Button("Commit") {
                                    repo.commit(message: commitMessage)
                                    commitMessage = ""
                                }
                                .buttonStyle(PillButtonStyle())
                                .disabled(commitMessage.isEmpty)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 6)
                            }
                        }
                    }
                }

                sectionView(
                    title: "Commits",
                    count: repo.recentCommits.count,
                    section: .commits
                ) {
                    VStack(spacing: 0) {
                        ForEach(repo.recentCommits) { commit in
                            commitRow(commit)
                        }
                    }
                }
            }
        }
        .onAppear { repo.startPolling() }
        .onDisappear { repo.stopPolling() }
    }

    // MARK: - Branch Header

    private var branchHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.accent)
            Text(repo.currentBranch)
                .font(Theme.mono(11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button(action: { repo.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Section

    private func sectionView<Content: View>(
        title: String,
        count: Int,
        section: Section,
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
                        .font(Theme.label(11))
                        .foregroundColor(Theme.textSecondary)
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSection == section {
                content()
            }
        }
    }

    // MARK: - File Row

    private func fileRow(_ file: GitFileStatus, staged: Bool) -> some View {
        HStack(spacing: 8) {
            Text(file.status)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(statusColor(file.status))
                .frame(width: 12)

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

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.warning
        case "A": return Theme.success
        case "D": return Theme.error
        case "R": return Theme.info
        default: return Theme.textMuted
        }
    }
}

// MARK: - Pill Button Style

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(11))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.6 : 0.85))
            .cornerRadius(Theme.pillCornerRadius)
            .frame(maxWidth: .infinity)
    }
}
