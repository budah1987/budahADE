import SwiftUI

struct BranchHeaderView: View {
    @ObservedObject var repo: GitRepository
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
        .background(Theme.surface2)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEditing ? Theme.info : Theme.borderSubtle, lineWidth: 1)
        )
    }

    private var defaultHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.info)

                if let prefix = BranchNameValidator.detectPrefix(repo.currentBranch) {
                    prefixBadge(prefix)
                    Text("/")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
                }

                let (_, name) = BranchNameValidator.split(repo.currentBranch)
                Text(name)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundColor(Theme.info)
                    .onTapGesture {
                        let parts = BranchNameValidator.split(repo.currentBranch)
                        selectedPrefix = parts.prefix
                        editedName = parts.name
                        isEditing = true
                    }
            }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)

                Button {
                    showTargetDropdown.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Text(repo.mergeTarget)
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.info.opacity(0.8))
                            .underline()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if showTargetDropdown {
                        targetDropdown
                            .offset(y: 20)
                    }
                }

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.12))
                        .cornerRadius(8)
                }

                if repo.behindCount > 0 {
                    Text("\(repo.behindCount) behind")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.error)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.error.opacity(0.12))
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
                    .foregroundColor(Theme.info)

                Button {
                    showPrefixDropdown.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedPrefix ?? "none")
                            .font(Theme.mono(11))
                            .foregroundColor(selectedPrefix != nil ? prefixColor(selectedPrefix!) : Theme.textMuted)
                        Image(systemName: showPrefixDropdown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 6))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.info, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topLeading) {
                    if showPrefixDropdown {
                        prefixDropdownMenu
                            .offset(y: 28)
                    }
                }

                if selectedPrefix != nil {
                    Text("/")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
                }

                TextField("branch-name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surface3)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.info, lineWidth: 1)
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
                        .background(Theme.info)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .onExitCommand { cancelEdit() }

            HStack(spacing: 5) {
                Text("→ into")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.textMuted)
                Text(repo.mergeTarget)
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.info.opacity(0.8))

                Spacer()

                if repo.aheadCount > 0 {
                    Text("\(repo.aheadCount) ahead")
                        .font(Theme.mono(9))
                        .foregroundColor(Theme.success)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.12))
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
                        .foregroundColor(Theme.info)
                        .frame(width: 12)
                    Text("none")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.textMuted)
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
                            .foregroundColor(Theme.info)
                            .frame(width: 12)
                        Text(type.prefix)
                            .font(Theme.mono(11))
                            .foregroundColor(prefixColor(type.prefix))
                        Spacer()
                        Text(type.label)
                            .font(Theme.caption(9))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 150)
        .background(Theme.surface3)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .zIndex(10)
    }

    private var targetDropdown: some View {
        VStack(spacing: 0) {
            ForEach(repo.branches.filter { !$0.hasPrefix("remotes/") && $0 != repo.currentBranch }, id: \.self) { branch in
                Button {
                    repo.mergeTarget = branch
                    showTargetDropdown = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: branch == repo.mergeTarget ? "checkmark" : "")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.info)
                            .frame(width: 12)
                        Text(branch)
                            .font(Theme.mono(11))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if branch != repo.branches.filter({ !$0.hasPrefix("remotes/") && $0 != repo.currentBranch }).last {
                    Divider().opacity(0.3)
                }
            }
        }
        .frame(width: 180)
        .background(Theme.surface3)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .zIndex(10)
    }

    private func prefixBadge(_ prefix: String) -> some View {
        Text(prefix)
            .font(Theme.mono(10, weight: .medium))
            .foregroundColor(prefixColor(prefix))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(prefixColor(prefix).opacity(0.12))
            .cornerRadius(3)
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
