import SwiftUI

struct LeftPanelView: View {
    @ObservedObject var state: WorkspaceState
    let worktreePath: String

    @State private var panelWidth: CGFloat = 280
    @State private var isDragging: Bool = false

    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 400

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                // Content area
                Group {
                    switch state.activeLeftTab {
                    case .files:
                        FileTreeView(projectPath: worktreePath)
                    case .changes:
                        ChangesPanel(worktreePath: worktreePath)
                    case .agents:
                        AgentsPanel(workspace: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panelWidth)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))

            // Drag handle
            dragHandle
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(LeftPanelTab.allCases, id: \.self) { tab in
                Button {
                    state.activeLeftTab = tab
                } label: {
                    Text(tab.rawValue.capitalized)
                        .font(Theme.uiFont(size: 12, weight: .medium))
                        .foregroundColor(
                            state.activeLeftTab == tab
                                ? Theme.textPrimary
                                : Theme.textSecondary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Group {
                                if state.activeLeftTab == tab {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.elevated)
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
            .fill(isDragging ? Theme.accent.opacity(0.5) : Color.clear)
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
