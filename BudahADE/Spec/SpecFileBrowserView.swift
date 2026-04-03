import SwiftUI

// MARK: - Spec File Item

private struct SpecFileItem: Identifiable {
    let id: String        // file path
    let name: String
    let path: String
    let group: SpecFileGroup
    let isActive: Bool
    let version: Int?
    let taskCount: Int
    let completedCount: Int
}

private enum SpecFileGroup: String, CaseIterable {
    case active = "Active"
    case versions = "Versions"
    case project = "Project Specs"
}

// MARK: - Spec File Browser View

/// Flat grouped list of spec files for the left panel "Spec" tab.
/// Shows active spec, versioned archives, and root-level spec files.
struct SpecFileBrowserView: View {
    @ObservedObject var specState: SpecState
    let worktreePath: String

    @State private var specFiles: [SpecFileItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if specFiles.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .onAppear { scanFiles() }
        .onChange(of: specState.allSpecs.count) { _, _ in scanFiles() }
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(SpecFileGroup.allCases, id: \.self) { group in
                    let groupFiles = specFiles.filter { $0.group == group }
                    if !groupFiles.isEmpty {
                        sectionHeader(group.rawValue)
                        ForEach(groupFiles) { file in
                            fileRow(file)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.Colors.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func fileRow(_ file: SpecFileItem) -> some View {
        let isSelected = specState.activeSpec?.filePath == file.path

        return Button {
            specState.selectSpec(filePath: file.path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 12))
                    .foregroundStyle(file.isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(Theme.body(12))
                        .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .lineLimit(1)

                    if let version = file.version {
                        Text("Version \(version)")
                            .font(Theme.caption(10))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                if file.taskCount > 0 {
                    Text("\(file.completedCount)/\(file.taskCount)")
                        .font(Theme.code(10))
                        .foregroundStyle(
                            file.completedCount == file.taskCount
                                ? Theme.Colors.statusDone
                                : Theme.Colors.textTertiary
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Colors.accent.opacity(0.08))
                    : nil
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                let url = URL(fileURLWithPath: file.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No spec files")
                .font(Theme.label(12))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Create a *-spec.md or approve\na spec in Plan mode")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Discovery

    private func scanFiles() {
        var items: [SpecFileItem] = []
        let fm = FileManager.default
        let activePath = (worktreePath as NSString).appendingPathComponent(".budahade/spec.md")

        // Active spec
        if fm.fileExists(atPath: activePath) {
            let parsed = SpecParser.parse(fileAt: activePath)
            items.append(SpecFileItem(
                id: activePath,
                name: "spec.md",
                path: activePath,
                group: .active,
                isActive: true,
                version: nil,
                taskCount: parsed?.tasks.count ?? 0,
                completedCount: parsed?.completedCount ?? 0
            ))
        }

        // Versioned specs (newest first)
        let versions = SpecVersionManager.listVersions(in: worktreePath)
        for v in versions.reversed() {
            let parsed = SpecParser.parse(fileAt: v.path)
            items.append(SpecFileItem(
                id: v.path,
                name: "spec-v\(v.version).md",
                path: v.path,
                group: .versions,
                isActive: false,
                version: v.version,
                taskCount: parsed?.tasks.count ?? 0,
                completedCount: parsed?.completedCount ?? 0
            ))
        }

        // Root-level spec files (excluding active spec to avoid duplicates)
        let rootSpecs = SpecParser.findSpecFiles(in: worktreePath)
            .filter { $0 != activePath }
        for path in rootSpecs {
            let name = (path as NSString).lastPathComponent
            let parsed = SpecParser.parse(fileAt: path)
            items.append(SpecFileItem(
                id: path,
                name: name,
                path: path,
                group: .project,
                isActive: false,
                version: nil,
                taskCount: parsed?.tasks.count ?? 0,
                completedCount: parsed?.completedCount ?? 0
            ))
        }

        specFiles = items
    }
}
