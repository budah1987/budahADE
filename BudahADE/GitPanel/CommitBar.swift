import SwiftUI

struct CommitBar: View {
    @ObservedObject var repo: GitRepository
    @State private var commitMessage: String = ""

    private var canCommit: Bool {
        !repo.stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Summary line
            Text("\(repo.stagedFiles.count) file\(repo.stagedFiles.count == 1 ? "" : "s") staged")
                .font(Theme.uiFont(size: 11))
                .foregroundColor(Theme.textMuted)

            // Commit message field
            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.plain)
                .font(Theme.uiFont(size: 12))
                .foregroundColor(Theme.textPrimary)
                .padding(8)
                .background(Theme.glassInputFill)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .onSubmit {
                    performCommit()
                }

            // Commit button
            Button(action: performCommit) {
                Text("Commit")
                    .font(Theme.uiFont(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(canCommit ? Theme.accent : Theme.accent.opacity(0.4))
                    .cornerRadius(6)
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
