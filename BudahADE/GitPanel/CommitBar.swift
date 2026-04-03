import SwiftUI

struct CommitBar: View {
    @ObservedObject var repo: GitRepository
    @State private var commitMessage: String = ""

    private var canCommit: Bool {
        !repo.stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(repo.stagedFiles.count) file\(repo.stagedFiles.count == 1 ? "" : "s") staged")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary)

            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.plain)
                .font(Theme.body(12))
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(8)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.Radius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.borderSubtle, lineWidth: 0.5)
                )
                .onSubmit {
                    performCommit()
                }

            Button(action: performCommit) {
                Text("Commit")
                    .font(Theme.label(12))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(canCommit ? Theme.Colors.accent.opacity(0.85) : Theme.Colors.accent.opacity(0.3))
                    .cornerRadius(Theme.Radius.sm)
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        .padding(8)
    }

    private func performCommit() {
        guard canCommit else { return }
        repo.commit(message: commitMessage.trimmingCharacters(in: .whitespaces))
        commitMessage = ""
    }
}
