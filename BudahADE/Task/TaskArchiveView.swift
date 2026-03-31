import SwiftUI

struct TaskArchiveView: View {
    @ObservedObject var archive: TaskArchive
    let onReopen: (ArchivedTask) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Task Archive")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.label(13))
                    .foregroundColor(Theme.accent)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            if archive.tasks.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(archive.tasks) { task in
                            TaskArchiveRow(task: task, onReopen: {
                                onReopen(task)
                                dismiss()
                            })
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 480, height: 420)
        .background(Theme.appBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.textMuted)
            Text("No archived tasks")
                .font(Theme.label(14))
                .foregroundColor(Theme.textMuted)
            Text("Completed tasks will appear here")
                .font(Theme.caption(12))
                .foregroundColor(Theme.textMuted.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Archive Row

private struct TaskArchiveRow: View {
    let task: ArchivedTask
    let onReopen: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(task.branchName)
                            .font(Theme.caption(10))
                    }
                    .foregroundColor(Theme.textMuted)

                    if task.specVersionCount > 0 {
                        metaPill("\(task.specVersionCount) spec \(task.specVersionCount == 1 ? "version" : "versions")")
                    }

                    if task.conversationCount > 0 {
                        metaPill("\(task.conversationCount) \(task.conversationCount == 1 ? "conversation" : "conversations")")
                    }
                }

                Text(relativeTime(from: task.completedAt))
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted.opacity(0.6))
            }

            Spacer()

            Button("Reopen") { onReopen() }
                .font(Theme.label(11))
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.accent.opacity(0.10))
                )
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isHovered ? Color.white.opacity(0.03) : Color.clear
        )
        .onHover { isHovered = $0 }
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(10))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
        let days = hours / 24
        if days < 30 { return "\(days) \(days == 1 ? "day" : "days") ago" }
        let months = days / 30
        return "\(months) \(months == 1 ? "month" : "months") ago"
    }
}
