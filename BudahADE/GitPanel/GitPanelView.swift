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
                HStack {
                    BranchPicker(repo: repo)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(Theme.Colors.borderSubtle)
                    .frame(height: 0.5)

                ScrollView {
                    StagingView(repo: repo) { path, staged in
                        selectedFile = path
                        selectedFileStaged = staged
                        selectedDiff = repo.diff(file: path, staged: staged)
                    }
                }

                Rectangle()
                    .fill(Theme.Colors.borderSubtle)
                    .frame(height: 0.5)

                CommitBar(repo: repo)
            }
            .frame(minHeight: 200)

            // Bottom: diff view
            VStack(alignment: .leading, spacing: 0) {
                if let file = selectedFile {
                    HStack {
                        Text(file)
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            selectedFile = nil
                            selectedDiff = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surface)

                    DiffView(diff: selectedDiff)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a file to view diff")
                            .font(Theme.body(12))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.appBackground)
                }
            }
            .frame(minHeight: 100)
        }
        .background(Theme.Colors.sidebarBackground)
        .onAppear {
            repo.startPolling()
        }
        .onDisappear {
            repo.stopPolling()
        }
    }
}
