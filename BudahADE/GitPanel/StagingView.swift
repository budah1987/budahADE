import SwiftUI

struct StagingView: View {
    @ObservedObject var repo: GitRepository
    var onSelectFile: (String, Bool) -> Void // (path, staged)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Staged section
            sectionHeader(
                title: "Staged",
                count: repo.stagedFiles.count,
                action: { repo.unstageAll() },
                actionLabel: "Unstage All",
                actionIcon: "minus"
            )

            ForEach(repo.stagedFiles) { file in
                fileRow(file: file, staged: true)
            }

            if repo.stagedFiles.isEmpty {
                emptyState("No staged files")
            }

            Rectangle()
                .fill(Theme.Colors.borderSubtle)
                .frame(height: 0.5)
                .padding(.vertical, 4)

            // Unstaged section
            sectionHeader(
                title: "Changes",
                count: repo.unstagedFiles.count,
                action: { repo.stageAll() },
                actionLabel: "Stage All",
                actionIcon: "plus"
            )

            ForEach(repo.unstagedFiles) { file in
                fileRow(file: file, staged: false)
            }

            if repo.unstagedFiles.isEmpty {
                emptyState("No changes")
            }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(
        title: String,
        count: Int,
        action: @escaping () -> Void,
        actionLabel: String,
        actionIcon: String
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textSecondary)
                .textCase(.uppercase)

            Text("\(count)")
                .font(Theme.caption(10))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(4)

            Spacer()

            if count > 0 {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 9, weight: .bold))
                        Text(actionLabel)
                            .font(Theme.label(10))
                    }
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.hoverFill)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileRow(file: GitFileStatus, staged: Bool) -> some View {
        HStack(spacing: 6) {
            statusBadge(file.status)

            Text(file.path)
                .font(Theme.body(12))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                if staged {
                    repo.unstage(file.path)
                } else {
                    repo.stage(file.path)
                }
            } label: {
                Image(systemName: staged ? "minus" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(Theme.Colors.hoverFill)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectFile(file.path, staged)
        }
        .background(Theme.Colors.hoverFill.opacity(0.01))
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(Theme.label(10))
            .foregroundColor(statusColor(status))
            .frame(width: 18, height: 18)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.Colors.warning
        case "A": return Theme.Colors.statusDone
        case "D": return Theme.Colors.error
        case "R": return Theme.Colors.info
        case "?": return Theme.Colors.textTertiary
        default: return Theme.Colors.textSecondary
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(11))
            .foregroundColor(Theme.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}
