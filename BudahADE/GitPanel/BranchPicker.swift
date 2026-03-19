import SwiftUI

struct BranchPicker: View {
    @ObservedObject var repo: GitRepository

    var body: some View {
        Menu {
            ForEach(repo.branches, id: \.self) { branch in
                Button {
                    repo.checkout(branch: branch)
                } label: {
                    HStack {
                        Text(branch)
                        if branch == repo.currentBranch {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)

                Text(repo.currentBranch.isEmpty ? "No branch" : repo.currentBranch)
                    .font(Theme.uiFont(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.panelSurface)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
