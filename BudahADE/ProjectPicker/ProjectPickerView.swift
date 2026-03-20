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
                .font(Theme.display(36))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 48)
                .padding(.bottom, 8)

            Text("Select a project to get started")
                .font(Theme.body(14))
                .foregroundColor(Theme.textSecondary)
                .padding(.bottom, 32)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textMuted)
                    .font(.system(size: 13))

                TextField("Search projects...", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.textPrimary)
                    .font(Theme.body(14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface2)
            .cornerRadius(Theme.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Theme.border, lineWidth: 0.5)
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
                        .font(.system(size: 12))
                    Text("Open Folder...")
                        .font(Theme.label(13))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface2)
                .cornerRadius(Theme.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 0.5)
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
                .font(.system(size: 24))
                .foregroundColor(Theme.accent.opacity(0.7))

            Text(project.name)
                .font(Theme.label(14))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Text(dateString)
                .font(Theme.caption(11))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(isHovered ? Theme.surface3 : Theme.surface2)
        .cornerRadius(Theme.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(isHovered ? Theme.borderActive : Theme.borderSubtle, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
