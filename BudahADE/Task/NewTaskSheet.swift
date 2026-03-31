import SwiftUI

struct NewTaskSheet: View {
    @ObservedObject var workspace: WorkspaceState
    @State private var taskName: String = ""
    @State private var branchPrefix: String? = "feat"
    @State private var branchSlug: String = ""
    @State private var baseBranch: String = "main"
    @State private var startWithPlan: Bool = false
    @State private var isCreating: Bool = false
    @State private var showPrefixDropdown = false
    @State private var showBasedOnDropdown = false
    @State private var hoveredPrefix: String? = nil
    @FocusState private var focusedField: Field?

    enum Field { case name, branch }

    private var fullBranchName: String {
        BranchNameValidator.compose(prefix: branchPrefix, name: branchSlug)
    }

    private var isValid: Bool {
        !taskName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !branchSlug.trimmingCharacters(in: .whitespaces).isEmpty
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
                            let prevSlug = slugify(taskName.dropLast())
                            if branchSlug.isEmpty || branchSlug == prevSlug {
                                branchSlug = slugify(newValue)
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

                    HStack(spacing: 6) {
                        // Prefix selector
                        Button {
                            showPrefixDropdown.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Text(branchPrefix ?? "none")
                                    .font(Theme.body(12))
                                    .foregroundColor(branchPrefix != nil ? prefixColor(branchPrefix!) : Theme.textMuted)
                                Image(systemName: showPrefixDropdown ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.surface2)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showPrefixDropdown, arrowEdge: .bottom) {
                            prefixDropdownMenu
                        }

                        if branchPrefix != nil {
                            Text("/")
                                .font(Theme.body(13))
                                .foregroundColor(Theme.textMuted)
                        }

                        TextField("my-feature", text: $branchSlug)
                            .textFieldStyle(.plain)
                            .font(Theme.body(14))
                            .foregroundColor(Theme.textPrimary)
                            .focused($focusedField, equals: .branch)
                            .onChange(of: branchSlug) { _, newValue in
                                branchSlug = BranchNameValidator.sanitize(newValue)
                            }
                            .onSubmit { if isValid { createTask() } }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surface3)
                    .cornerRadius(Theme.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                }

                // Base branch + plan toggle
                HStack {
                    Text("Based on")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textMuted)

                    Button {
                        showBasedOnDropdown.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(baseBranch)
                                .font(Theme.body(11))
                                .foregroundColor(Theme.textSecondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                                .foregroundColor(Theme.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surface3)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showBasedOnDropdown, arrowEdge: .bottom) {
                        BasedOnDropdownView(
                            projectPath: workspace.projectPath,
                            baseBranch: $baseBranch,
                            isPresented: $showBasedOnDropdown
                        )
                    }

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
        }
    }

    // MARK: - Prefix Dropdown

    private var prefixDropdownMenu: some View {
        VStack(spacing: 0) {
            Button {
                branchPrefix = nil
                showPrefixDropdown = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: branchPrefix == nil ? "checkmark" : "")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.info)
                        .frame(width: 12)
                    Text("none")
                        .font(Theme.body(11))
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hoveredPrefix == "__none" ? Theme.surface3 : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredPrefix = $0 ? "__none" : nil }

            ForEach(BranchNameValidator.prefixTypes) { type in
                Divider().opacity(0.3)
                Button {
                    branchPrefix = type.prefix
                    showPrefixDropdown = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: branchPrefix == type.prefix ? "checkmark" : "")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.info)
                            .frame(width: 12)
                        Text(type.prefix)
                            .font(Theme.body(11))
                            .foregroundColor(prefixColor(type.prefix))
                            .lineLimit(1)
                        Spacer()
                        Text(type.label)
                            .font(Theme.caption(9))
                            .foregroundColor(Theme.textMuted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(hoveredPrefix == type.prefix ? Theme.surface3 : Color.clear)
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredPrefix = $0 ? type.prefix : nil }
            }
        }
        .frame(width: 200)
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

    // MARK: - Actions

    private func createTask() {
        guard isValid else { return }
        isCreating = true
        let name = taskName.trimmingCharacters(in: .whitespaces)
        workspace.createTask(name: name, branchName: fullBranchName, baseBranch: baseBranch)
        if startWithPlan, let task = workspace.activeTask {
            task.enterPlanMode()
        }
        workspace.showNewTaskSheet = false
    }

    // MARK: - Helpers

    private func slugify(_ text: any StringProtocol) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func prefixColor(_ prefix: String) -> Color {
        guard let type = BranchNameValidator.prefixTypes.first(where: { $0.prefix == prefix }) else {
            return Theme.textMuted
        }
        switch type.color {
        case "success": return Theme.success
        case "error": return Theme.error
        case "accent": return Theme.accent
        case "info": return Theme.info
        case "warning": return Theme.warning
        case "textMuted": return Theme.textMuted
        default: return Theme.textSecondary
        }
    }
}

// MARK: - Based On Dropdown

struct BasedOnDropdownView: View {
    let projectPath: String
    @Binding var baseBranch: String
    @Binding var isPresented: Bool

    @State private var localBranches: [String] = []
    @State private var remoteBranches: [String] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var hoveredBranch: String? = nil
    @FocusState private var searchFocused: Bool

    private var filteredLocal: [String] {
        guard !searchText.isEmpty else { return localBranches }
        return localBranches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredRemote: [String] {
        guard !searchText.isEmpty else { return remoteBranches }
        return remoteBranches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search pill
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                TextField("Search branches...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textPrimary)
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 7)

            Divider().opacity(0.3)

            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.6)
                    Text("Loading branches…")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if !filteredLocal.isEmpty {
                            sectionHeader("ON GITHUB")
                            ForEach(filteredLocal, id: \.self) { branch in
                                branchRow(branch)
                            }
                        }
                        if !filteredRemote.isEmpty {
                            if !filteredLocal.isEmpty {
                                Divider().opacity(0.3).padding(.vertical, 4)
                            }
                            sectionHeader("LOCAL ONLY")
                            ForEach(filteredRemote, id: \.self) { branch in
                                branchRow(branch)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 240, height: 360)
        .onAppear {
            searchFocused = true
            Task {
                let grouped = await GitRepository.listBranchesGrouped(at: projectPath)
                localBranches = grouped.local
                remoteBranches = grouped.remote
                isLoading = false
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func branchRow(_ branch: String) -> some View {
        Button {
            baseBranch = branch
            isPresented = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: branch == baseBranch ? "checkmark" : "")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.info)
                    .frame(width: 12)
                Text(branch)
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(hoveredBranch == branch ? Theme.surface3 : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredBranch = $0 ? branch : nil }
    }
}
