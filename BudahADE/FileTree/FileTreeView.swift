import SwiftUI
import AppKit

struct FileTreeView: View {

    let projectPath: String

    @StateObject private var watcher: FileWatcher
    @State private var rootNodes: [FileTreeNode] = []
    @State private var selectedPath: String? = nil

    init(projectPath: String) {
        self.projectPath = projectPath
        _watcher = StateObject(wrappedValue: FileWatcher(path: projectPath))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootNodes) { node in
                    FileTreeRowView(node: node, depth: 0, selectedPath: $selectedPath)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            loadTree()
            watcher.onChange = { loadTree() }
            watcher.start()
        }
        .onDisappear {
            watcher.stop()
        }
    }

    private func loadTree() {
        rootNodes = FileTreeNode.scan(directory: projectPath)
    }
}

// MARK: - Row

private struct FileTreeRowView: View {
    @ObservedObject var node: FileTreeNode
    let depth: Int
    @Binding var selectedPath: String?

    private var isSelected: Bool { !node.isDirectory && selectedPath == node.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton

            if isSelected {
                FilePreviewView(path: node.path, kind: node.kind)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if node.isDirectory && node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRowView(node: child, depth: depth + 1, selectedPath: $selectedPath)
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isSelected)
        .animation(nil, value: node.isExpanded)
    }

    private var rowButton: some View {
        Button {
            if node.isDirectory {
                node.toggle()
            } else {
                selectedPath = isSelected ? nil : node.path
            }
        } label: {
            HStack(spacing: 5) {
                Group {
                    if node.isDirectory {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 10)

                Image(systemName: node.icon)
                    .font(.system(size: 11))
                    .foregroundColor(node.iconColor)
                    .frame(width: 14, alignment: .center)

                Text(node.name)
                    .font(Theme.body(12))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 14 + 6)
            .padding(.trailing, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Theme.selectedFill : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
        }
    }
}
