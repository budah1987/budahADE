import SwiftUI

struct NewTaskSheet: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var taskName: String = ""
    @State private var branchName: String = ""
    @State private var baseBranch: String = "main"
    @State private var isCreating: Bool = false
    @FocusState private var focusedField: Field?

    enum Field { case name, branch }

    private var isValid: Bool {
        !taskName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("What are you working on?")
                    .font(Theme.headline(17))
                    .foregroundColor(Theme.textPrimary)
                Text(workspace.projectName)
                    .font(Theme.caption(12))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            VStack(spacing: 16) {
                // Task name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("TASK NAME")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.8)

                    TextField("e.g. Rate limiter", text: $taskName)
                        .textFieldStyle(.plain)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.surface3)
                        .cornerRadius(Theme.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                        .focused($focusedField, equals: .name)
                        .onChange(of: taskName) { _, newValue in
                            if branchName.isEmpty || branchName == slugify(taskName.dropLast()) {
                                branchName = slugify(newValue)
                            }
                        }
                        .onSubmit { focusedField = .branch }
                }

                // Branch name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("BRANCH")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.8)

                    TextField("feat/my-feature", text: $branchName)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(14))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.surface3)
                        .cornerRadius(Theme.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                        .focused($focusedField, equals: .branch)
                        .onSubmit { if isValid { createTask() } }
                }

                // Base branch
                HStack {
                    Text("Based on")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textMuted)

                    TextField("main", text: $baseBranch)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: 80)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            // Actions
            HStack(spacing: 10) {
                if !workspace.tasks.isEmpty {
                    Button("Cancel") {
                        workspace.showNewTaskSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Spacer()

                Button(action: createTask) {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        Text("Create Task")
                            .font(Theme.label(13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(isValid ? Theme.accent : Theme.accent.opacity(0.3))
                    .cornerRadius(Theme.cardCornerRadius)
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isCreating)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 380)
        .background(Theme.surface2)
        .cornerRadius(14)
        .onAppear {
            focusedField = .name
        }
    }

    // MARK: - Actions

    private func createTask() {
        guard isValid else { return }
        isCreating = true
        let name = taskName.trimmingCharacters(in: .whitespaces)
        let branch = branchName.trimmingCharacters(in: .whitespaces)
        workspace.createTask(name: name, branchName: branch, baseBranch: baseBranch)
        workspace.showNewTaskSheet = false
    }

    // MARK: - Helpers

    private func slugify(_ text: any StringProtocol) -> String {
        let lower = text.lowercased()
        let slug = lower
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "feat/\(slug)"
    }
}
