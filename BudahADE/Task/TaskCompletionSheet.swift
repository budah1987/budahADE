import SwiftUI

struct TaskCompletionSheet: View {
    @ObservedObject var workspace: WorkspaceState
    let task: TaskState
    @Environment(\.dismiss) private var dismiss

    @State private var prTitle: String
    @State private var prBody: String = ""
    @State private var isCreatingPR: Bool = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm: Bool = false

    init(workspace: WorkspaceState, task: TaskState) {
        _workspace = ObservedObject(wrappedValue: workspace)
        self.task = task
        _prTitle = State(initialValue: task.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Complete Task")
                    .font(Theme.headline(17))
                    .foregroundColor(Theme.textPrimary)
                Text(task.branchName)
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            VStack(spacing: 14) {
                // PR Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("PR TITLE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.8)
                    TextField("Pull request title", text: $prTitle)
                        .textFieldStyle(.plain)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.surface3)
                        .cornerRadius(Theme.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                }

                // PR Body
                VStack(alignment: .leading, spacing: 6) {
                    Text("DESCRIPTION")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.8)
                    TextEditor(text: $prBody)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.textPrimary)
                        .frame(height: 80)
                        .padding(8)
                        .background(Theme.surface3)
                        .cornerRadius(Theme.cardCornerRadius)
                        .scrollContentBackground(.hidden)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            // Actions
            VStack(spacing: 8) {
                Button(action: createPR) {
                    HStack(spacing: 6) {
                        if isCreatingPR {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        Text("Create PR")
                            .font(Theme.label(13))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(!prTitle.isEmpty ? Theme.accent.opacity(0.85) : Theme.accent.opacity(0.3))
                    .cornerRadius(Theme.cardCornerRadius)
                }
                .buttonStyle(.plain)
                .disabled(prTitle.isEmpty || isCreatingPR)

                HStack(spacing: 8) {
                    Button("Just Mark Complete") {
                        workspace.completeTask(task.id)
                        dismiss()
                    }
                    .font(Theme.body(12))
                    .foregroundColor(Theme.textSecondary)
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Cancel") { dismiss() }
                        .font(Theme.body(12))
                        .foregroundColor(Theme.textMuted)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400)
        .background(Theme.surface2)
        .cornerRadius(14)
    }

    // MARK: - Create PR

    private func createPR() {
        guard !prTitle.isEmpty else { return }
        isCreatingPR = true
        errorMessage = nil

        Task {
            do {
                try await GitWorktreeManager.runGit(
                    args: ["push", "-u", "origin", task.branchName],
                    repoPath: task.worktreePath
                )

                var args = ["pr", "create", "--title", prTitle, "--body", prBody]
                if prBody.isEmpty { args = ["pr", "create", "--title", prTitle, "--body", ""] }
                try await runProcess(
                    "/usr/bin/env",
                    args: ["gh"] + args,
                    cwd: task.worktreePath
                )

                await MainActor.run {
                    workspace.completeTask(task.id)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreatingPR = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func runProcess(_ executable: String, args: [String], cwd: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                process.standardOutput = Pipe()
                let errPipe = Pipe()
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NSError(
                            domain: "PR",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)]
                        ))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
