import SwiftUI
import Foundation

// MARK: - File Kind

enum FileKind {
    case directory
    case image, video, audio
    case code, markup, data
    case document, pdf
    case other

    static func from(ext: String) -> FileKind {
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif",
             "tiff", "bmp", "ico", "icns", "svg":           return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "webm",
             "wmv", "flv":                                   return .video
        case "mp3", "aac", "wav", "flac", "m4a", "ogg":    return .audio
        case "swift", "js", "ts", "jsx", "tsx", "py", "rb",
             "go", "rs", "cpp", "c", "h", "java", "kt",
             "sh", "bash", "zsh", "fish":                   return .code
        case "html", "css", "scss", "less", "xml",
             "md", "mdx", "txt", "rtf":                     return .markup
        case "json", "yaml", "yml", "toml", "ini",
             "env", "lock", "plist":                        return .data
        case "pdf":                                         return .pdf
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx": return .document
        default:                                            return .other
        }
    }
}

// MARK: - FileTreeNode

final class FileTreeNode: Identifiable, ObservableObject, Hashable {

    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let kind: FileKind

    @Published var children: [FileTreeNode]?
    @Published var isExpanded: Bool = false

    static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        let ext = (name as NSString).pathExtension.lowercased()
        self.kind = isDirectory ? .directory : FileKind.from(ext: ext)
    }

    // MARK: - Icon

    var icon: String {
        if isDirectory { return isExpanded ? "folder.fill" : "folder.fill" }
        switch kind {
        case .image:    return "photo"
        case .video:    return "film"
        case .audio:    return "waveform"
        case .code:
            let ext = (name as NSString).pathExtension.lowercased()
            if ext == "swift" { return "swift" }
            return "doc.text"
        case .markup:
            let ext = (name as NSString).pathExtension.lowercased()
            return ext == "md" || ext == "mdx" ? "doc.richtext" : "doc.text"
        case .data:     return "curlybraces"
        case .pdf:      return "doc.fill"
        case .document: return "doc.fill"
        case .directory: return "folder.fill"
        case .other:    return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return Color(hex: 0x7b9fd4) } // muted blue for folders
        switch kind {
        case .image:    return Color(hex: 0x9e7bd4)  // purple
        case .video:    return Color(hex: 0xd47b7b)  // red
        case .audio:    return Color(hex: 0x7bd4b0)  // teal
        case .code:
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "swift":         return Color(hex: 0xe8784a)
            case "ts", "tsx":     return Color(hex: 0x4a8fe8)
            case "js", "jsx":     return Color(hex: 0xe8d44a)
            case "py":            return Color(hex: 0x4aaee8)
            case "go":            return Color(hex: 0x4ad4e8)
            case "rs":            return Color(hex: 0xe8a84a)
            case "rb":            return Color(hex: 0xe84a4a)
            default:              return Theme.textSecondary
            }
        case .markup:   return Color(hex: 0xa8c47b)  // green
        case .data:     return Color(hex: 0xe8c47b)  // amber
        case .pdf:      return Color(hex: 0xe87b7b)  // red
        case .document: return Color(hex: 0x7b9fe8)
        case .directory: return Color(hex: 0x7b9fd4)
        case .other:    return Theme.textMuted
        }
    }

    // MARK: - Toggle (no animation — caller must NOT wrap in withAnimation)

    func toggle() {
        guard isDirectory else { return }
        if !isExpanded, children == nil {
            children = FileTreeNode.scan(directory: path)
        }
        isExpanded.toggle()
    }

    // MARK: - Scan

    private static let ignoredNames: Set<String> = [
        "node_modules", ".git", ".build", ".DS_Store", "__pycache__",
        ".swiftpm", ".next", "dist", ".cache", "coverage"
    ]

    static func scan(directory: String) -> [FileTreeNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        var dirs: [FileTreeNode] = []
        var files: [FileTreeNode] = []

        for entry in entries.sorted() {
            if ignoredNames.contains(entry) || entry.hasPrefix(".") { continue }
            let fullPath = (directory as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }
            let node = FileTreeNode(name: entry, path: fullPath, isDirectory: isDir.boolValue)
            if isDir.boolValue { dirs.append(node) } else { files.append(node) }
        }

        return dirs + files
    }
}
