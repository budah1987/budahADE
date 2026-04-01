import SwiftUI

struct DiffModalView: View {
    @ObservedObject var repo: GitRepository
    let files: [GitFileStatus]
    let initialFileIndex: Int
    let staged: Bool
    let commitHash: String?
    @State private var currentIndex: Int
    @State private var showSplit = true
    @State private var loadedDiff: String?

    init(repo: GitRepository, files: [GitFileStatus], initialFileIndex: Int, staged: Bool, commitHash: String? = nil) {
        self.repo = repo
        self.files = files
        self.initialFileIndex = initialFileIndex
        self.staged = staged
        self.commitHash = commitHash
        _currentIndex = State(initialValue: initialFileIndex)
    }

    private var currentFile: GitFileStatus? {
        guard currentIndex >= 0, currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().foregroundColor(Theme.borderSubtle)
            diffContent
            Divider().foregroundColor(Theme.borderSubtle)
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBackground)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            if let file = currentFile {
                statusBadge(file.status)

                Text((file.path as NSString).lastPathComponent)
                    .font(Theme.label(13))
                    .foregroundColor(Theme.textPrimary)

                Text((file.path as NSString).deletingLastPathComponent)
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            if let file = currentFile, commitHash == nil, let diffText = loadedDiff {
                let adds = diffText.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
                let removes = diffText.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

                Text("+\(adds)")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.success)
                Text("−\(removes)")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.error)

                Button {
                    if staged { repo.unstage(file.path) } else { repo.stage(file.path) }
                } label: {
                    Text(staged ? "Unstage File" : "Stage File")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surface3)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface2)
    }

    private var diffContent: some View {
        Group {
            if let rawDiff = loadedDiff {
                if showSplit {
                    splitDiffView(rawDiff)
                } else {
                    unifiedDiffView(rawDiff)
                }
            } else if currentFile != nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No file selected")
                    .foregroundColor(Theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: currentIndex) {
            await loadDiff()
        }
    }

    private func loadDiff() async {
        guard let file = currentFile else {
            loadedDiff = nil
            return
        }
        loadedDiff = nil
        if let hash = commitHash {
            loadedDiff = repo.diffForCommit(hash)
        } else {
            loadedDiff = repo.diff(file: file.path, staged: staged)
        }
    }

    private func splitDiffView(_ diff: String) -> some View {
        let lines = diff.components(separatedBy: "\n")
        let (leftLines, rightLines) = parseSplitDiff(lines)

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("HEAD (before)")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(Theme.surface2)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(leftLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Rectangle().fill(Theme.borderSubtle).frame(width: 1)

            VStack(spacing: 0) {
                Text("Working Tree (after)")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(Theme.surface2)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rightLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func unifiedDiffView(_ diff: String) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(Theme.code(10))
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 32, alignment: .trailing)
                            .padding(.trailing, 4)

                        Text(line)
                            .font(Theme.code(11))
                            .foregroundColor(lineColor(line))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(lineBackground(line))
                }
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Button {
                if currentIndex > 0 { currentIndex -= 1 }
            } label: {
                Text("← Prev")
                    .font(Theme.caption(11))
                    .foregroundColor(currentIndex > 0 ? Theme.info : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex <= 0)

            Text("\(currentIndex + 1) of \(files.count) files")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textSecondary)

            Button {
                if currentIndex < files.count - 1 { currentIndex += 1 }
            } label: {
                Text("Next →")
                    .font(Theme.caption(11))
                    .foregroundColor(currentIndex < files.count - 1 ? Theme.info : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= files.count - 1)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    showSplit = false
                } label: {
                    Text("Unified")
                        .font(Theme.caption(10))
                        .foregroundColor(!showSplit ? Theme.info : Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(!showSplit ? Theme.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button {
                    showSplit = true
                } label: {
                    Text("Split")
                        .font(Theme.caption(10))
                        .foregroundColor(showSplit ? Theme.info : Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(showSplit ? Theme.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.surface3)
            .cornerRadius(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surface2)
    }

    struct DiffLine {
        let number: Int?
        let text: String
        let type: LineType
    }

    enum LineType {
        case context, added, removed, header
    }

    private func parseSplitDiff(_ lines: [String]) -> ([DiffLine], [DiffLine]) {
        var left: [DiffLine] = []
        var right: [DiffLine] = []
        var leftNum = 0
        var rightNum = 0

        for line in lines {
            if line.hasPrefix("@@") {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    let oldPart = parts[1].dropFirst()
                    let newPart = parts[2].dropFirst()
                    leftNum = Int(oldPart.components(separatedBy: ",").first ?? "0") ?? 0
                    rightNum = Int(newPart.components(separatedBy: ",").first ?? "0") ?? 0
                }
                left.append(DiffLine(number: nil, text: line, type: .header))
                right.append(DiffLine(number: nil, text: line, type: .header))
            } else if line.hasPrefix("---") || line.hasPrefix("+++") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
                continue
            } else if line.hasPrefix("-") {
                left.append(DiffLine(number: leftNum, text: String(line.dropFirst()), type: .removed))
                leftNum += 1
            } else if line.hasPrefix("+") {
                right.append(DiffLine(number: rightNum, text: String(line.dropFirst()), type: .added))
                rightNum += 1
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                left.append(DiffLine(number: leftNum, text: text, type: .context))
                right.append(DiffLine(number: rightNum, text: text, type: .context))
                leftNum += 1
                rightNum += 1
            }
        }

        return (left, right)
    }

    private func diffLineView(lineNumber: Int?, text: String, type: LineType) -> some View {
        HStack(spacing: 0) {
            Text(lineNumber.map { "\($0)" } ?? "")
                .font(Theme.code(10))
                .foregroundColor(Theme.textMuted)
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 4)

            Text(text)
                .font(Theme.code(11))
                .foregroundColor(lineTypeColor(type))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(lineTypeBackground(type))
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(Theme.label(10))
            .foregroundColor(statusColor(status))
            .frame(width: 14, height: 14)
            .background(statusColor(status).opacity(0.12))
            .cornerRadius(3)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Theme.success
        case "A": return Theme.info
        case "D": return Theme.error
        case "R": return Theme.warning
        default: return Theme.textMuted
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("@@") { return Theme.info }
        if line.hasPrefix("+") { return Theme.success }
        if line.hasPrefix("-") { return Theme.error }
        return Theme.textSecondary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Theme.success.opacity(0.06) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Theme.error.opacity(0.05) }
        return .clear
    }

    private func lineTypeColor(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.success
        case .removed: return Theme.error
        case .header: return Theme.info
        case .context: return Theme.textSecondary
        }
    }

    private func lineTypeBackground(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.success.opacity(0.06)
        case .removed: return Theme.error.opacity(0.05)
        case .header, .context: return .clear
        }
    }
}
