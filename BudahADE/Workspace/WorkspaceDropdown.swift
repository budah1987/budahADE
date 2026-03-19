import SwiftUI

struct WorkspaceDropdown: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = ProjectStore()
    @State private var isExpanded: Bool = false
    @State private var searchText: String = ""
    @State private var hoveredWorkspaceId: UUID?
    @State private var isHovered: Bool = false

    private var filteredAvailableProjects: [ProjectInfo] {
        let openPaths = Set(appState.workspaces.map(\.projectPath))
        let available = store.filteredProjects.filter { !openPaths.contains($0.path) }
        if searchText.isEmpty { return Array(available.prefix(8)) }
        return available.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredOpenWorkspaces: [WorkspaceState] {
        if searchText.isEmpty { return appState.workspaces }
        return appState.workspaces.filter { $0.projectName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(appState.activeWorkspace?.projectName ?? "No Project")
                    .font(Theme.uiFont(size: 12, weight: .medium))
                    .foregroundColor(isHovered || isExpanded ? Theme.textPrimary : Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .opacity(isHovered || isExpanded ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceSwitcher)) { _ in
            isExpanded.toggle()
        }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            dropdownContent
                .frame(width: 320)
        }
    }

    // MARK: - Dropdown Content

    private var dropdownContent: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textMuted)
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Open workspaces
                    if !filteredOpenWorkspaces.isEmpty {
                        sectionHeader("Open")
                        ForEach(Array(filteredOpenWorkspaces.enumerated()), id: \.element.id) { idx, ws in
                            let globalIdx = appState.workspaces.firstIndex(where: { $0.id == ws.id }) ?? idx
                            workspaceRow(ws: ws, index: globalIdx)
                        }
                    }

                    // Available projects
                    if !filteredAvailableProjects.isEmpty {
                        sectionHeader("Recent")
                        ForEach(filteredAvailableProjects) { project in
                            projectRow(project)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)

            Divider().background(Theme.border)

            // Open folder button
            Button(action: openFolderPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                    Text("Open Folder...")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.panelSurface)
    }

    // MARK: - Rows

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.textMuted)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func workspaceRow(ws: WorkspaceState, index: Int) -> some View {
        let isActive = index == appState.activeWorkspaceIndex
        return Button {
            appState.switchToWorkspace(at: index)
            isExpanded = false
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isActive ? Theme.accent : Theme.textMuted.opacity(0.4))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ws.projectName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                    Text("\(ws.tasks.count) task\(ws.tasks.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                if !isActive {
                    Button {
                        appState.closeWorkspace(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: ProjectInfo) -> some View {
        Button {
            appState.openProject(project)
            isExpanded = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 6)
                Text(project.name)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Open Folder

    private func openFolderPanel() {
        isExpanded = false
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
        appState.openProject(project)
    }
}
