import SwiftUI

struct PlanArchiveView: View {
    let archivedTabs: [ArchivedPlanTab]
    var onDelete: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Plan Archive")
                    .font(Theme.label(16))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.3)

            if archivedTabs.isEmpty {
                VStack(spacing: 8) {
                    Text("No archived conversations")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(archivedTabs.enumerated()), id: \.element.id) { index, tab in
                            PlanArchiveRow(tab: tab) {
                                onDelete?(index)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 420, height: 400)
        .background(Theme.Colors.surface)
    }
}

// MARK: - Archive Row

private struct PlanArchiveRow: View {
    let tab: ArchivedPlanTab
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Role icon
            Image(systemName: tab.role.iconName)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tab.title)
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("\(tab.messageCount) msgs")
                        .font(Theme.caption(10))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                if !tab.preview.isEmpty {
                    Text(tab.preview)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(tab.archivedAt.formatted(.relative(presentation: .named)))
                .font(Theme.caption(10))
                .foregroundStyle(Theme.Colors.textTertiary)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.Colors.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
