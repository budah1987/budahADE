import SwiftUI
import Foundation

// MARK: - File Mention Item

struct FileMentionItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    /// Path relative to the workspace root
    let relativePath: String
    /// Absolute path on disk
    let absolutePath: String
    let isDirectory: Bool
    let icon: String
    let iconColor: Color

    static func == (lhs: FileMentionItem, rhs: FileMentionItem) -> Bool {
        lhs.relativePath == rhs.relativePath
    }
}

// MARK: - Document Mention Popover

struct DocumentMentionPopover: View {
    let items: [FileMentionItem]
    let filter: String
    let onSelect: (FileMentionItem) -> Void
    let onDismiss: () -> Void
    @Binding var selectedIndex: Int

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                MentionRow(
                                    item: item,
                                    isSelected: index == selectedIndex,
                                    onSelect: { onSelect(item) }
                                )
                                .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)

                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        MentionKeyHint("↑↓")
                        Text("navigate")
                    }
                    HStack(spacing: 3) {
                        MentionKeyHint("tab")
                        Text("complete")
                    }
                    HStack(spacing: 3) {
                        MentionKeyHint("⏎")
                        Text("select")
                    }
                    HStack(spacing: 3) {
                        MentionKeyHint("esc")
                        Text("dismiss")
                    }
                }
                .font(Theme.caption(10))
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.Colors.borderLight, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 16, y: -4)
            )
            .frame(width: 380)
        }
    }

    /// Move selection up
    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    /// Move selection down
    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    /// Get the currently selected item
    var selectedItem: FileMentionItem? {
        guard !items.isEmpty, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }
}

// MARK: - Mention Row

private struct MentionRow: View {
    let item: FileMentionItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 11))
                    .foregroundColor(item.iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(item.relativePath)
                        .font(Theme.code(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()

                if item.isDirectory {
                    Text("dir")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.hoverFill)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.15) : (isHovered ? Theme.Colors.hoverFill : Color.clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Mention Key Hint

private struct MentionKeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.caption(9))
            .foregroundColor(Theme.Colors.textTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.Colors.surface.opacity(0.8))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - File Scanner for Mentions

enum DocumentMentionScanner {

    /// Recursively scans a directory and returns a flat list of FileMentionItems,
    /// with paths relative to `rootPath`. Results are cached per root path.
    static func scan(rootPath: String, maxResults: Int = 500) -> [FileMentionItem] {
        let fm = FileManager.default
        let resolvedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path

        var results: [FileMentionItem] = []
        var queue: [(path: String, depth: Int)] = [(resolvedRoot, 0)]
        let maxDepth = 8

        while !queue.isEmpty && results.count < maxResults {
            let (currentPath, depth) = queue.removeFirst()
            guard depth <= maxDepth else { continue }

            guard let entries = try? fm.contentsOfDirectory(atPath: currentPath) else { continue }
            for entry in entries.sorted() {
                guard results.count < maxResults else { break }
                if ignoredNames.contains(entry) || entry.hasPrefix(".") { continue }

                let fullPath = (currentPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

                let relativePath = String(fullPath.dropFirst(resolvedRoot.count + 1))
                let ext = (entry as NSString).pathExtension.lowercased()
                let kind = isDir.boolValue ? FileKind.directory : FileKind.from(ext: ext)

                let item = FileMentionItem(
                    name: entry,
                    relativePath: relativePath,
                    absolutePath: fullPath,
                    isDirectory: isDir.boolValue,
                    icon: iconFor(kind: kind, ext: ext, isDir: isDir.boolValue),
                    iconColor: colorFor(kind: kind, ext: ext, isDir: isDir.boolValue)
                )
                results.append(item)

                if isDir.boolValue {
                    queue.append((fullPath, depth + 1))
                }
            }
        }

        return results
    }

    /// Filter items by query (matches name or path, case-insensitive)
    static func filter(_ items: [FileMentionItem], query: String, limit: Int = 30) -> [FileMentionItem] {
        guard !query.isEmpty else { return Array(items.prefix(limit)) }
        let q = query.lowercased()

        // Score-based filtering: name prefix match > name contains > path contains
        struct Scored {
            let item: FileMentionItem
            let score: Int
        }

        let scored = items.compactMap { item -> Scored? in
            let nameLower = item.name.lowercased()
            let pathLower = item.relativePath.lowercased()

            if nameLower.hasPrefix(q) {
                return Scored(item: item, score: 3)
            } else if nameLower.contains(q) {
                return Scored(item: item, score: 2)
            } else if pathLower.contains(q) {
                return Scored(item: item, score: 1)
            }
            return nil
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }

    // MARK: - Private

    private static let ignoredNames: Set<String> = [
        "node_modules", ".git", ".build", ".DS_Store", "__pycache__",
        ".swiftpm", ".next", "dist", ".cache", "coverage",
        "Pods", ".xcodeproj", ".xcworkspace", "DerivedData",
        ".budahade"
    ]

    private static func iconFor(kind: FileKind, ext: String, isDir: Bool) -> String {
        if isDir { return "folder.fill" }
        switch kind {
        case .image:     return "photo"
        case .video:     return "film"
        case .audio:     return "waveform"
        case .code:
            if ext == "swift" { return "swift" }
            return "doc.text"
        case .markup:
            return ext == "md" || ext == "mdx" ? "doc.richtext" : "doc.text"
        case .data:      return "curlybraces"
        case .pdf:       return "doc.fill"
        case .document:  return "doc.fill"
        case .directory: return "folder.fill"
        case .other:     return "doc"
        }
    }

    private static func colorFor(kind: FileKind, ext: String, isDir: Bool) -> Color {
        if isDir { return Color(hex: 0x7b9fd4) }
        switch kind {
        case .image:    return Color(hex: 0x9e7bd4)
        case .video:    return Color(hex: 0xd47b7b)
        case .audio:    return Color(hex: 0x7bd4b0)
        case .code:
            switch ext {
            case "swift":         return Color(hex: 0xe8784a)
            case "ts", "tsx":     return Color(hex: 0x4a8fe8)
            case "js", "jsx":     return Color(hex: 0xe8d44a)
            case "py":            return Color(hex: 0x4aaee8)
            case "go":            return Color(hex: 0x4ad4e8)
            case "rs":            return Color(hex: 0xe8a84a)
            case "rb":            return Color(hex: 0xe84a4a)
            default:              return Theme.Colors.textSecondary
            }
        case .markup:   return Color(hex: 0xa8c47b)
        case .data:     return Color(hex: 0xe8c47b)
        case .pdf:      return Color(hex: 0xe87b7b)
        case .document: return Color(hex: 0x7b9fe8)
        case .directory: return Color(hex: 0x7b9fd4)
        case .other:    return Theme.Colors.textTertiary
        }
    }
}

// MARK: - Mention Popover State (for NSEvent monitor)

final class MentionPopoverState: ObservableObject {
    @Published var isVisible = false
    @Published var items: [FileMentionItem] = []
    @Published var selectedIndex: Int = 0

    func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    var selectedItem: FileMentionItem? {
        guard !items.isEmpty, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }
}
