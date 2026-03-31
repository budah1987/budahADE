import SwiftUI

struct ChangesListView: View {
    @ObservedObject var repo: GitRepository
    var onSelectFile: (GitFileStatus, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            unstagedSection
            stagedSection
        }
    }

    private var unstagedSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: "CHANGES",
                count: repo.unstagedFiles.count,
                countColor: Theme.accent
            )

            if repo.unstagedFiles.isEmpty {
                emptyState("No changes yet")
            } else {
                ForEach(repo.unstagedFiles) { file in
                    fileRow(file: file, staged: false)
                }

                Button {
                    repo.stageAll()
                } label: {
                    Text("Stage All")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Theme.surface3)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private var stagedSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: "STAGED",
                count: repo.stagedFiles.count,
                countColor: Theme.info
            )

            if !repo.stagedFiles.isEmpty {
                ForEach(repo.stagedFiles) { file in
                    fileRow(file: file, staged: true)
                }

                Button {
                    repo.unstageAll()
                } label: {
                    Text("Unstage All")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Theme.surface3)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionHeader(title: String, count: Int, countColor: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .tracking(0.8)

            if count > 0 {
                Text("\(count)")
                    .font(Theme.caption(9))
                    .foregroundColor(countColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(countColor.opacity(0.12))
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func fileRow(file: GitFileStatus, staged: Bool) -> some View {
        HStack(spacing: 8) {
            statusBadge(file.status)

            Text(file.path)
                .font(Theme.body(11))
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
        .background(staged ? Theme.info.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectFile(file, staged)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(Theme.label(10))
            .foregroundColor(statusColor(status))
            .frame(width: 14, height: 14)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.success
        case "A": return Theme.info
        case "D": return Theme.error
        case "R": return Theme.warning
        case "?": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(11))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
