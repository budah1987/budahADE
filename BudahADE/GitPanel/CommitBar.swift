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
                .foregroundColor(Theme.textMuted)

            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.plain)
                .font(Theme.body(12))
                .foregroundColor(Theme.textPrimary)
                .padding(8)
                .background(Theme.surface3)
                .cornerRadius(Theme.pillCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                        .stroke(Theme.borderSubtle, lineWidth: 0.5)
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
                    .background(canCommit ? Theme.accent.opacity(0.85) : Theme.accent.opacity(0.3))
                    .cornerRadius(Theme.pillCornerRadius)
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
