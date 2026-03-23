import SwiftUI

struct LeftPanelView: View {
    @ObservedObject var state: WorkspaceState
    let worktreePath: String

    @State private var panelWidth: CGFloat = 280
    @State private var isDragging: Bool = false

    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 400

    /// Tabs visible based on current state (spec tab only when spec exists)
    private var visibleTabs: [LeftPanelTab] {
        var tabs = LeftPanelTab.allCases
        if state.activeTask?.specState.hasSpec != true {
            tabs.removeAll { $0 == .spec }
        }
        return tabs
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                // Content area
                Group {
                    switch state.activeLeftTab {
                    case .files:
                        FileTreeView(projectPath: worktreePath)
                    case .spec:
                        if let task = state.activeTask {
                            SpecPanelView(specState: task.specState, buildStatus: task.buildStatus)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panelWidth)
            // No individual background/clip/border — parent sidebar zone provides these

            // Drag handle
            dragHandle
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        state.activeLeftTab = tab
                    }
                } label: {
                    Text(tab.rawValue.capitalized)
                        .font(Theme.label(11))
                        .foregroundColor(
                            state.activeLeftTab == tab
                                ? Theme.textPrimary
                                : Theme.textMuted
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Group {
                                if state.activeLeftTab == tab {
                                    RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                                        .fill(Color.white.opacity(0.10))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(isDragging ? Theme.accent.opacity(0.3) : Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newWidth = panelWidth + value.translation.width
                        panelWidth = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
