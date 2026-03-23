import SwiftUI

struct BranchFlowView: View {
    let sourceBranch: String
    let targetBranch: String

    var body: some View {
        VStack(spacing: 10) {
            // Labels
            HStack {
                Text("Your code lives in:")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Text("and will be merged into:")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
            }

            // Branch pills + arrow
            HStack(spacing: 0) {
                branchPill(sourceBranch, accent: true)

                // Arrow connector
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.textMuted.opacity(0.4))
                        .frame(height: 1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textMuted.opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                branchPill(targetBranch, accent: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func branchPill(_ name: String, accent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(accent ? Theme.accent : Theme.textMuted)

            Text(name)
                .font(Theme.mono(11, weight: .medium))
                .foregroundColor(accent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .fill(accent ? Theme.accent.opacity(0.08) : Theme.surface3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .stroke(accent ? Theme.accent.opacity(0.3) : Theme.borderSubtle, lineWidth: 1)
        )
        .fixedSize()
    }
}
