import SwiftUI

struct WorkspaceDropdown: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = ProjectStore()
    @State private var isExpanded: Bool = false
    @State private var searchText: String = ""
    @State private var hoveredWorkspaceId: UUID?
    @State private var isHovered: Bool = false
    @State private var highlightedIndex: Int = 0

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
                    .font(Theme.label(12))
                    .foregroundColor(isHovered || isExpanded ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(isHovered || isExpanded ? Theme.Colors.hoverFill : Color.clear)
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspaceSwitcher)) { _ in
            isExpanded.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTabByIndex)) { notification in
            guard isExpanded,
                  let index = notification.userInfo?["index"] as? Int else { return }
            let wsCount = filteredOpenWorkspaces.count
            if index <= wsCount {
                let wsIdx = index - 1
                if let globalIdx = appState.workspaces.firstIndex(where: { $0.id == filteredOpenWorkspaces[wsIdx].id }) {
                    appState.switchToWorkspace(at: globalIdx)
                }
            }
            isExpanded = false
        }
        .onChange(of: isExpanded) { _, expanded in
            appState.isWorkspaceSwitcherOpen = expanded
            if expanded { highlightedIndex = 0 }
            if !expanded { searchText = "" }
        }
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            dropdownContent
                .frame(width: 300)
        }
    }

    // MARK: - Dropdown Content

    /// Total number of selectable rows (open workspaces + recent projects + "Open Folder")
    private var selectableCount: Int {
        filteredOpenWorkspaces.count + filteredAvailableProjects.count + 1
    }

    private var openFolderIndex: Int {
        filteredOpenWorkspaces.count + filteredAvailableProjects.count
    }

    private func selectHighlighted() {
        let wsCount = filteredOpenWorkspaces.count
        if highlightedIndex == openFolderIndex {
            openFolderPanel()
        } else if highlightedIndex < wsCount {
            let ws = filteredOpenWorkspaces[highlightedIndex]
            if let globalIdx = appState.workspaces.firstIndex(where: { $0.id == ws.id }) {
                appState.switchToWorkspace(at: globalIdx)
            }
            isExpanded = false
        } else {
            let projectIdx = highlightedIndex - wsCount
            if projectIdx < filteredAvailableProjects.count {
                appState.openProject(filteredAvailableProjects[projectIdx])
            }
            isExpanded = false
        }
    }

    private var dropdownContent: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textTertiary)
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .onSubmit { selectHighlighted() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !filteredOpenWorkspaces.isEmpty {
                        sectionHeader("Open")
                        ForEach(Array(filteredOpenWorkspaces.enumerated()), id: \.element.id) { idx, ws in
                            let globalIdx = appState.workspaces.firstIndex(where: { $0.id == ws.id }) ?? idx
                            let flatIdx = idx
                            workspaceRow(ws: ws, index: globalIdx, isHighlighted: highlightedIndex == flatIdx)
                        }
                    }

                    if !filteredAvailableProjects.isEmpty {
                        sectionHeader("Recent")
                        ForEach(Array(filteredAvailableProjects.enumerated()), id: \.element.id) { idx, project in
                            let flatIdx = filteredOpenWorkspaces.count + idx
                            projectRow(project, isHighlighted: highlightedIndex == flatIdx)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)

            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)

            Button(action: openFolderPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                    Text("Open Folder...")
                        .font(Theme.body(12))
                }
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    highlightedIndex == openFolderIndex
                        ? RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.Colors.hoverFill)
                        : nil
                )
            }
            .buttonStyle(.plain)
        }
        .background(Theme.Colors.surface)
        .onKeyPress(.downArrow) {
            if selectableCount > 0 {
                highlightedIndex = (highlightedIndex + 1) % selectableCount
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectableCount > 0 {
                highlightedIndex = (highlightedIndex - 1 + selectableCount) % selectableCount
            }
            return .handled
        }
        .onKeyPress(.return) {
            selectHighlighted()
            return .handled
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.Colors.textTertiary)
            .tracking(0.8)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func workspaceRow(ws: WorkspaceState, index: Int, isHighlighted: Bool = false) -> some View {
        let isActive = index == appState.activeWorkspaceIndex
        return Button {
            appState.switchToWorkspace(at: index)
            isExpanded = false
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary.opacity(0.4))
                    .frame(width: 5, height: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(ws.projectName)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    Text("\(ws.tasks.count) task\(ws.tasks.count == 1 ? "" : "s")")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Spacer()

                if !isActive {
                    Button {
                        appState.closeWorkspace(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isHighlighted
                    ? RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.Colors.hoverFill)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: ProjectInfo, isHighlighted: Bool = false) -> some View {
        Button {
            appState.openProject(project)
            isExpanded = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 5)
                Text(project.name)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isHighlighted
                    ? RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.Colors.hoverFill)
                    : nil
            )
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
