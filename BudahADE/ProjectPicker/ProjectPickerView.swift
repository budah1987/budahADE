import SwiftUI
import AppKit

struct ProjectPickerView: View {
    @StateObject private var store = ProjectStore()
    @EnvironmentObject var appState: AppState

    @State private var hoveredProject: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("BudahADE")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 48)
                .padding(.bottom, 8)

            Text("Select a project to get started")
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 32)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                    .font(.system(size: 14))

                TextField("Search projects...", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.textPrimary)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.panelSurface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 48)
            .padding(.bottom, 24)

            // Project grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.filteredProjects) { project in
                        ProjectCard(
                            project: project,
                            isHovered: hoveredProject == project.id
                        )
                        .onHover { hovering in
                            hoveredProject = hovering ? project.id : nil
                        }
                        .onTapGesture {
                            selectProject(project)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)

            // Open Folder button
            Button(action: openFolderPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                    Text("Open Folder...")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.panelSurface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBackground)
    }

    // MARK: - Actions

    private func selectProject(_ project: ProjectInfo) {
        store.saveLastProject(project.path)
        appState.openProject(project)
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let lastModified = attrs?[.modificationDate] as? Date

        let project = ProjectInfo(
            name: url.lastPathComponent,
            path: url.path,
            lastModified: lastModified
        )
        selectProject(project)
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: ProjectInfo
    let isHovered: Bool

    private var dateString: String {
        guard let date = project.lastModified else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 28))
                .foregroundColor(Theme.accent)

            Text(project.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Text(dateString)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(isHovered ? Theme.elevated : Theme.panelSurface)
        .cornerRadius(Theme.panelCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
