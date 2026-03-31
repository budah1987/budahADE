import SwiftUI
import UniformTypeIdentifiers

struct NewTaskSheet: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var taskName: String = ""
    @State private var branchName: String = ""
    @State private var baseBranch: String = "main"
    @State private var availableBranches: [String] = ["main"]
    @State private var startWithPlan: Bool = false
    @State private var isCreating: Bool = false
    @State private var specFilePath: String? = nil
    @State private var specItemCount: Int = 0
    @State private var isDropTargeted: Bool = false
    @State private var showFilePicker: Bool = false
    @FocusState private var focusedField: Field?

    enum Field { case name, branch }

    private var isValid: Bool {
        !taskName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasSpec: Bool { specFilePath != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("New task")
                    .font(Theme.label(15))
                    .foregroundColor(Theme.textPrimary)
                Text(workspace.projectName)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 0.5)

            VStack(spacing: 14) {
                // Task name
                fieldGroup(label: "NAME") {
                    TextField("e.g. Rate limiter", text: $taskName)
                        .textFieldStyle(.plain)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.textPrimary)
                        .focused($focusedField, equals: .name)
                        .onChange(of: taskName) { _, newValue in
                            if branchName.isEmpty || branchName == slugify(taskName.dropLast()) {
                                branchName = slugify(newValue)
                            }
                        }
                        .onSubmit { focusedField = .branch }
                }

                // Branch
                fieldGroup(label: "BRANCH") {
                    TextField("feat/my-feature", text: $branchName)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        .foregroundColor(Theme.textPrimary)
                        .focused($focusedField, equals: .branch)
                        .onSubmit { if isValid { createTask() } }
                }

                // Base branch + plan toggle
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("from")
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.textMuted)

                        Menu {
                            ForEach(availableBranches, id: \.self) { branch in
                                Button(branch) { baseBranch = branch }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(baseBranch)
                                    .font(Theme.mono(11))
                                    .foregroundColor(Theme.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Spacer()

                    if !hasSpec {
                        Toggle(isOn: $startWithPlan) {
                            Text("Plan first")
                                .font(Theme.caption(11))
                                .foregroundColor(Theme.textMuted)
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 0.5)
                    .padding(.vertical, 2)

                // Spec file section
                specSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer(minLength: 16)

            // Actions
            HStack(spacing: 0) {
                if !workspace.tasks.isEmpty {
                    Button("Cancel") {
                        workspace.showNewTaskSheet = false
                    }
                    .buttonStyle(.plain)
                    .font(Theme.body(12))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }

                Spacer()

                Button(action: createTask) {
                    HStack(spacing: 5) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                        Text(hasSpec ? "Create & Build" : "Create")
                            .font(Theme.label(12))
                    }
                    .foregroundColor(isValid ? .white : Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isValid ? Theme.accent : Theme.surface3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isValid || isCreating)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        )
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadSpecFile(url.path)
            }
        }
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

    // MARK: - Spec Section

    @ViewBuilder
    private var specSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SPEC")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.8)

            if let path = specFilePath {
                // Spec loaded — show filename + item count
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent)
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(specItemCount) items")
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    Button {
                        specFilePath = nil
                        specItemCount = 0
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 18, height: 18)
                            .background(Theme.surface3)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.accent.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.15), lineWidth: 0.5)
                        )
                )
            } else {
                // Drop zone
                Button { showFilePicker = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(isDropTargeted ? Theme.accent : Theme.textMuted)
                        Text("Drop a spec or browse")
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isDropTargeted ? Theme.accent.opacity(0.06) : Color.white.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isDropTargeted ? Theme.accent.opacity(0.3) : Theme.borderSubtle,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
            }

            Text(hasSpec ? "Task opens in Build mode with builder agent" : "Optional — skip to start from scratch")
                .font(Theme.caption(10))
                .foregroundColor(Theme.textMuted.opacity(0.7))
        }
    }

    // MARK: - Field Group

    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.8)

            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.surface3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.borderSubtle, lineWidth: 0.5)
                        )
                )
        }
    }

    // MARK: - Actions

    private func createTask() {
        guard isValid else { return }
        isCreating = true
        let name = taskName.trimmingCharacters(in: .whitespaces)
        let branch = branchName.trimmingCharacters(in: .whitespaces)
        workspace.createTask(name: name, branchName: branch, baseBranch: baseBranch)

        if let task = workspace.activeTask {
            if let specPath = specFilePath {
                // Copy spec to .budahade/spec.md and go straight to Build
                copySpecToWorktree(specPath, task: task)
                task.enterBuildMode()
            } else if startWithPlan {
                task.enterPlanMode()
            }
        }
        workspace.showNewTaskSheet = false
    }

    private func copySpecToWorktree(_ sourcePath: String, task: TaskState) {
        let fm = FileManager.default
        let budahadeDir = (task.worktreePath as NSString).appendingPathComponent(".budahade")
        try? fm.createDirectory(atPath: budahadeDir, withIntermediateDirectories: true)
        let destPath = (budahadeDir as NSString).appendingPathComponent("spec.md")
        try? fm.copyItem(atPath: sourcePath, toPath: destPath)
    }

    private func loadSpecFile(_ path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        specFilePath = path
        specItemCount = content.components(separatedBy: "\n")
            .filter { $0.contains("- [ ]") || $0.contains("- [x]") || $0.contains("- [X]") }
            .count
        startWithPlan = false
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension == "md" else { return }
            DispatchQueue.main.async {
                loadSpecFile(url.path)
            }
        }
        return true
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
