import SwiftUI

struct CommitBarView: View {
    @ObservedObject var repo: GitRepository
    @Binding var commitMessage: String
    @State private var isGenerating = false

    private var canCommit: Bool {
        !repo.stagedFiles.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField("Commit message...", text: $commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.body(11))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1...4)
                .padding(8)
                .background(Theme.surface3)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
                .onSubmit { if canCommit { performCommit() } }

            HStack(spacing: 6) {
                Button { performCommit() } label: {
                    Text("Commit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(canCommit ? .white : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(canCommit ? Theme.info : Theme.surface3)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)

                Button {
                    generateAIMessage()
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("✨")
                                .font(.system(size: 12))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(repo.stagedFiles.isEmpty || isGenerating)
                .help("Generate commit message with AI")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func performCommit() {
        guard canCommit else { return }
        repo.commit(message: commitMessage)
        commitMessage = ""
    }

    private func generateAIMessage() {
        guard !repo.stagedFiles.isEmpty else { return }
        isGenerating = true
        Task {
            if let message = await AICommitService.shared.generateMessage(repoPath: repo.path) {
                await MainActor.run {
                    commitMessage = message
                    isGenerating = false
                }
            } else {
                await MainActor.run {
                    commitMessage = repo.generateCommitMessage()
                    isGenerating = false
                }
            }
        }
    }
}
