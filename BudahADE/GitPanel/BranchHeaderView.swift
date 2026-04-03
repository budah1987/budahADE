import SwiftUI

struct BranchHeaderView: View {
    @ObservedObject var repo: GitRepository
    let projectPath: String
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var selectedPrefix: String?
    @State private var showPrefixDropdown = false
    @State private var showTargetDropdown = false
    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editingHeader
            } else {
                defaultHeader
            }
        }
        .padding(10)
        .background(Theme.Colors.surface)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEditing ? Theme.Colors.info : Theme.Colors.borderSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                let parts = BranchNameValidator.split(repo.currentBranch)
                selectedPrefix = parts.prefix
                editedName = parts.name
                isEditing = true
            }
        }
    }

    private var defaultHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.info)

                if let prefix = BranchNameValidator.detectPrefix(repo.currentBranch) {
                    prefixBadge(prefix)
                    Text("/")
                        .font(Theme.body(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                let (_, name) = BranchNameValidator.split(repo.currentBranch)
                Text(name)
                    .font(Theme.label(12))
                    .foregroundColor(Theme.Colors.info)
            }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.Colors.textTertiary)

                Button {
                    showTargetDropdown.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Text(repo.mergeTarget)
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.Colors.info.opacity(0.8))
                            .underline()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTargetDropdown, arrowEdge: .bottom) {
                    BasedOnDropdownView(
                        projectPath: projectPath,
                        baseBranch: $repo.mergeTarget,
                        isPresented: $showTargetDropdown
                    )
                }

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.statusDone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.statusDone.opacity(0.12))
                        .cornerRadius(8)
                }

                if repo.behindCount > 0 {
                    Text("\(repo.behindCount) behind")
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.error)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.error.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    private var editingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.info)

                Button {
                    showPrefixDropdown.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedPrefix ?? "none")
                            .font(Theme.body(11))
                            .foregroundColor(selectedPrefix != nil ? prefixColor(selectedPrefix!) : Theme.Colors.textTertiary)
                        Image(systemName: showPrefixDropdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.Colors.info, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPrefixDropdown, arrowEdge: .bottom) {
                    prefixDropdownMenu
                }

                if selectedPrefix != nil {
                    Text("/")
                        .font(Theme.body(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                TextField("branch-name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.Colors.info, lineWidth: 1)
                    )
                    .onChange(of: editedName) { _, newValue in
                        editedName = BranchNameValidator.sanitize(newValue)
                    }
                    .onSubmit { saveBranchName() }

                Button { saveBranchName() } label: {
                    Text("Save")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.info)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .onExitCommand { cancelEdit() }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.Colors.textTertiary)

                Button {
                    showTargetDropdown.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Text(repo.mergeTarget)
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.Colors.info.opacity(0.8))
                            .underline()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTargetDropdown, arrowEdge: .bottom) {
                    BasedOnDropdownView(
                        projectPath: projectPath,
                        baseBranch: $repo.mergeTarget,
                        isPresented: $showTargetDropdown
                    )
                }

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.caption(9))
                        .foregroundColor(Theme.Colors.statusDone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.statusDone.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    private var prefixDropdownMenu: some View {
        VStack(spacing: 0) {
            Button {
                selectedPrefix = nil
                showPrefixDropdown = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedPrefix == nil ? "checkmark" : "")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.Colors.info)
                        .frame(width: 12)
                    Text("none")
                        .font(Theme.body(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(BranchNameValidator.prefixTypes) { type in
                Divider().opacity(0.3)
                Button {
                    selectedPrefix = type.prefix
                    showPrefixDropdown = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedPrefix == type.prefix ? "checkmark" : "")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.Colors.info)
                            .frame(width: 12)
                        Text(type.prefix)
                            .font(Theme.body(11))
                            .foregroundColor(prefixColor(type.prefix))
                            .lineLimit(1)
                        Spacer()
                        Text(type.label)
                            .font(Theme.caption(9))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
        .padding(4)
    }


    private func prefixBadge(_ prefix: String) -> some View {
        Text(prefix)
            .font(Theme.label(10))
            .foregroundColor(prefixColor(prefix))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(prefixColor(prefix).opacity(0.12))
            .cornerRadius(3)
    }

    private func prefixColor(_ prefix: String) -> Color {
        guard let type = BranchNameValidator.prefixTypes.first(where: { $0.prefix == prefix }) else {
            return Theme.Colors.textTertiary
        }
        switch type.color {
        case "success": return Theme.Colors.statusDone
        case "error": return Theme.Colors.error
        case "accent": return Theme.Colors.accent
        case "info": return Theme.Colors.info
        case "warning": return Theme.Colors.warning
        case "textMuted": return Theme.Colors.textTertiary
        default: return Theme.Colors.textSecondary
        }
    }

    private func saveBranchName() {
        let newName = BranchNameValidator.compose(prefix: selectedPrefix, name: editedName)
        let sanitized = BranchNameValidator.sanitize(newName)
        guard !sanitized.isEmpty, sanitized != repo.currentBranch else {
            cancelEdit()
            return
        }
        _ = repo.renameBranch(from: repo.currentBranch, to: sanitized)
        isEditing = false
        showPrefixDropdown = false
    }

    private func cancelEdit() {
        isEditing = false
        showPrefixDropdown = false
    }

}
