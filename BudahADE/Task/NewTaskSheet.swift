import SwiftUI

struct NewTaskSheet: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var taskName: String = ""
    @State private var branchName: String = ""
    @State private var baseBranch: String = "main"
    @State private var availableBranches: [String] = ["main"]
    @State private var startWithPlan: Bool = false
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
                        .focused($focusedField, equals: .branch)
                        .onSubmit { if isValid { createTask() } }
                }

                // Base branch + plan toggle
                HStack {
                    Text("Based on")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textMuted)

                    Menu {
                        ForEach(availableBranches, id: \.self) { branch in
                            Button(branch) {
                                baseBranch = branch
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(baseBranch)
                                .font(Theme.body(11))
                                .foregroundColor(Theme.textSecondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 120)

                    Spacer()

                    Toggle(isOn: $startWithPlan) {
                        Text("Start with a plan")
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.textMuted)
                    }
                    .toggleStyle(.checkbox)
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
            Task {
                let branches = await GitRepository.listBranches(at: workspace.projectPath)
                availableBranches = branches.isEmpty ? ["main"] : branches
                if !availableBranches.contains(baseBranch) {
                    baseBranch = availableBranches.first ?? "main"
                }
            }
        }
    }

    // MARK: - Actions

    private func createTask() {
        guard isValid else { return }
        isCreating = true
        let name = taskName.trimmingCharacters(in: .whitespaces)
        let branch = branchName.trimmingCharacters(in: .whitespaces)
        workspace.createTask(name: name, branchName: branch, baseBranch: baseBranch)
        if startWithPlan, let task = workspace.activeTask {
            task.enterPlanMode()
        }
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
