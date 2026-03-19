import SwiftUI

struct GitPanelView: View {
    let projectPath: String

    @StateObject private var repo: GitRepository
    @State private var selectedFile: String?
    @State private var selectedDiff: String = ""
    @State private var selectedFileStaged: Bool = false

    init(projectPath: String) {
        self.projectPath = projectPath
        _repo = StateObject(wrappedValue: GitRepository(path: projectPath))
    }

    var body: some View {
        VSplitView {
            // Top: branch picker, staging, commit
            VStack(alignment: .leading, spacing: 0) {
                // Branch picker
                HStack {
                    BranchPicker(repo: repo)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                Divider()
                    .background(Theme.border)

                // Staging area
                ScrollView {
                    StagingView(repo: repo) { path, staged in
                        selectedFile = path
                        selectedFileStaged = staged
                        selectedDiff = repo.diff(file: path, staged: staged)
                    }
                }

                Divider()
                    .background(Theme.border)

                // Commit bar
                CommitBar(repo: repo)
            }
            .frame(minHeight: 200)

            // Bottom: diff view
            VStack(alignment: .leading, spacing: 0) {
                if let file = selectedFile {
                    HStack {
                        Text(file)
                            .font(Theme.uiFont(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            selectedFile = nil
                            selectedDiff = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.panelSurface)

                    DiffView(diff: selectedDiff)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a file to view diff")
                            .font(Theme.uiFont(size: 12))
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.appBackground)
                }
            }
            .frame(minHeight: 100)
        }
        .background(Theme.panelSurface)
        .onAppear {
            repo.startPolling()
        }
        .onDisappear {
            repo.stopPolling()
        }
    }
}
