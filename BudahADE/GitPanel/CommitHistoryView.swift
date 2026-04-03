import SwiftUI

struct CommitHistoryView: View {
    @ObservedObject var repo: GitRepository
    @State private var isExpanded = false
    @State private var commits: [GitCommit] = []
    var onSelectCommit: (GitCommit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                    if isExpanded && commits.isEmpty {
                        loadCommits()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 10)

                    Text("HISTORY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .tracking(0.8)

                    Text("\(repo.totalCommitCount)")
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.surfaceElevated)
                        .cornerRadius(8)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                timelineView
            }
        }
        .onChange(of: repo.recentCommits.count) { _, _ in
            if isExpanded { loadCommits() }
        }
    }

    private var timelineView: some View {
        VStack(spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                commitRow(commit: commit, index: index, total: commits.count)
            }

            if commits.count < repo.totalCommitCount {
                Button {
                    loadMoreCommits()
                } label: {
                    Text("Load more...")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.info)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .padding(.leading, 24)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitRow(commit: GitCommit, index: Int, total: Int) -> some View {
        let isHead = index == 0
        let isBelowFork: Bool = {
            guard let forkHash = repo.forkPointHash else { return false }
            guard let forkIndex = commits.firstIndex(where: { $0.id == forkHash }) else { return false }
            return index > forkIndex
        }()
        let isForkPoint = commit.id == repo.forkPointHash
        let isAtOrBelowFork = isForkPoint || isBelowFork
        let dotColor = isBelowFork ? Theme.Colors.accent : Theme.Colors.info
        let lineColor = isAtOrBelowFork ? Theme.Colors.accent : Theme.Colors.info

        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                if isHead {
                    Color.clear.frame(width: 2, height: 4)
                } else {
                    Rectangle()
                        .fill(isBelowFork ? Theme.Colors.accent : Theme.Colors.info)
                        .frame(width: 2, height: 4)
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: isHead ? 10 : 8, height: isHead ? 10 : 8)
                    .overlay {
                        if isHead {
                            Circle()
                                .stroke(dotColor.opacity(0.5), lineWidth: 2)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .shadow(color: isHead ? dotColor.opacity(0.3) : .clear, radius: 4)

                if index < total - 1 {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    Color.clear.frame(width: 2)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.message)
                    .font(Theme.body(11))
                    .foregroundColor(isBelowFork ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(String(commit.id.prefix(7)))
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Text(commit.date)
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.textTertiary)

                    Spacer()

                    if isHead {
                        badgePill("HEAD", color: Theme.Colors.info)
                        badgePill(repo.currentBranch.components(separatedBy: "/").last ?? repo.currentBranch, color: Theme.Colors.statusDone)
                    }

                    if isBelowFork, index == (commits.firstIndex(where: { $0.id == repo.forkPointHash }).map { $0 + 1 } ?? -1) {
                        badgePill("origin/\(repo.mergeTarget)", color: Theme.Colors.accent)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 12)
        .opacity(isBelowFork ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(commit)
        }
        .help("\(commit.message)\nAuthor: \(commit.author)\nHash: \(commit.id)")
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.caption(8))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }

    private func loadCommits() {
        commits = repo.extendedLog(limit: 20)
    }

    private func loadMoreCommits() {
        let newLimit = commits.count + 20
        commits = repo.extendedLog(limit: newLimit)
    }
}
