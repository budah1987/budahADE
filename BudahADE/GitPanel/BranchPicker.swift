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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textMuted)

                Text(repo.currentBranch.isEmpty ? "No branch" : repo.currentBranch)
                    .font(Theme.label(12))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface3)
            .cornerRadius(Theme.pillCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .stroke(Theme.borderSubtle, lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
