import SwiftUI
import AppKit

struct DiffModalView: View {
    @ObservedObject var repo: GitRepository
    let files: [GitFileStatus]
    let initialFileIndex: Int
    let staged: Bool
    let commitHash: String?
    @State private var currentIndex: Int
    @State private var showSplit = true
    @State private var loadedDiff: String?
    @State private var parsedLeftLines: [DiffLine] = []
    @State private var parsedRightLines: [DiffLine] = []
    @State private var addCount: Int = 0
    @State private var removeCount: Int = 0
    @State private var commitDetail: CommitDetail?
    @State private var hashCopied = false
    @State private var actionError: String?
    @State private var showRevertConfirm = false
    @State private var showCherryPick = false
    @State private var cherryPickBranch = ""
    @State private var githubURL: URL?

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
            if let hash = commitHash {
                commitHeader(hash)
                Divider().foregroundColor(Theme.Colors.borderSubtle)
                fileList
                Divider().foregroundColor(Theme.Colors.borderSubtle)
            } else {
                workingTreeHeader
                Divider().foregroundColor(Theme.Colors.borderSubtle)
            }
            diffContent
            Divider().foregroundColor(Theme.Colors.borderSubtle)
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.appBackground)
        .task {
            if let hash = commitHash {
                commitDetail = repo.commitDetail(hash)
                githubURL = repo.githubURLForCommit(hash)
            }
        }
    }

    // MARK: - Commit Header

    private func commitHeader(_ hash: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Subject + body
            VStack(alignment: .leading, spacing: 4) {
                Text(commitDetail?.subject ?? "Loading...")
                    .font(Theme.label(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)

                if let body = commitDetail?.body, !body.isEmpty {
                    Text(body)
                        .font(Theme.body(11))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Metadata row
            HStack(spacing: 8) {
                Text(String(hash.prefix(7)))
                    .font(Theme.code(11))
                    .foregroundColor(Theme.Colors.textTertiary)

                Circle().fill(Theme.Colors.borderSubtle).frame(width: 3, height: 3)

                Text(commitDetail?.author ?? "")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.Colors.textTertiary)

                Circle().fill(Theme.Colors.borderSubtle).frame(width: 3, height: 3)

                Text(commitDetail?.date ?? "")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.Colors.textTertiary)

                if let detail = commitDetail, detail.parentCount > 1 {
                    badgePill("merge", color: Theme.Colors.warning)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // Action buttons
            HStack(spacing: 6) {
                actionButton(icon: "doc.on.doc", label: hashCopied ? "Copied" : "Copy Hash") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hash, forType: .string)
                    hashCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { hashCopied = false }
                }

                if let url = githubURL {
                    actionButton(icon: "arrow.up.right", label: "GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                }

                actionButton(icon: "arrow.uturn.backward", label: "Revert") {
                    showRevertConfirm = true
                }

                actionButton(icon: "arrow.triangle.branch", label: "Cherry-pick") {
                    showCherryPick = true
                }

                Spacer()

                if let error = actionError {
                    Text(error)
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.error)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.Colors.surface)
        .alert("Revert this commit?", isPresented: $showRevertConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) { performRevert(hash) }
        } message: {
            Text("This creates a new commit that undoes the changes from \(String(hash.prefix(7))).")
        }
        .alert("Cherry-pick onto branch", isPresented: $showCherryPick) {
            TextField("Branch name", text: $cherryPickBranch)
            Button("Cancel", role: .cancel) { cherryPickBranch = "" }
            Button("Cherry-pick") { performCherryPick(hash) }
        } message: {
            Text("Apply \(String(hash.prefix(7))) onto another branch.")
        }
    }

    // MARK: - Working Tree Header (non-commit diffs)

    private var workingTreeHeader: some View {
        HStack(spacing: 10) {
            if let file = currentFile {
                statusBadge(file.status)

                Text((file.path as NSString).lastPathComponent)
                    .font(Theme.label(13))
                    .foregroundColor(Theme.Colors.textPrimary)

                Text((file.path as NSString).deletingLastPathComponent)
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            if let file = currentFile, loadedDiff != nil {
                Text("+\(addCount)")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.statusDone)
                Text("−\(removeCount)")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.error)

                Button {
                    if staged { repo.unstage(file.path) } else { repo.stage(file.path) }
                } label: {
                    Text(staged ? "Unstage File" : "Stage File")
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.surfaceElevated)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.Colors.surface)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                    let isActive = idx == currentIndex
                    Button {
                        currentIndex = idx
                    } label: {
                        HStack(spacing: 5) {
                            statusBadge(file.status)

                            Text((file.path as NSString).lastPathComponent)
                                .font(Theme.caption(11))
                                .foregroundColor(isActive ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isActive ? Theme.Colors.surfaceElevated : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(Theme.Colors.appBackground)
    }

    // MARK: - Diff Content

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
                    .foregroundColor(Theme.Colors.textTertiary)
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
            parsedLeftLines = []
            parsedRightLines = []
            addCount = 0
            removeCount = 0
            return
        }
        loadedDiff = nil
        let rawDiff: String
        if let hash = commitHash {
            rawDiff = repo.diffForCommitFile(hash, file: file.path)
        } else {
            rawDiff = repo.diff(file: file.path, staged: staged)
        }
        // Pre-parse split diff lines and counts once
        let lines = rawDiff.components(separatedBy: "\n")
        let (left, right) = parseSplitDiff(lines)
        parsedLeftLines = left
        parsedRightLines = right
        addCount = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        removeCount = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        loadedDiff = rawDiff
    }

    // MARK: - Split Diff

    private func splitDiffView(_ diff: String) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("HEAD (before)")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surface)

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(parsedLeftLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Rectangle().fill(Theme.Colors.borderSubtle).frame(width: 1)

            VStack(spacing: 0) {
                Text("Working Tree (after)")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surface)

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(parsedRightLines.enumerated()), id: \.offset) { _, line in
                            diffLineView(lineNumber: line.number, text: line.text, type: line.type)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Unified Diff

    private func unifiedDiffView(_ diff: String) -> some View {
        let lines = diff.components(separatedBy: "\n")
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(Theme.code(10))
                            .foregroundColor(Theme.Colors.textTertiary)
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

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if commitHash == nil {
                Button {
                    if currentIndex > 0 { currentIndex -= 1 }
                } label: {
                    Text("← Prev")
                        .font(Theme.caption(11))
                        .foregroundColor(currentIndex > 0 ? Theme.Colors.info : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex <= 0)

                Text("\(currentIndex + 1) of \(files.count) files")
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.Colors.textSecondary)

                Button {
                    if currentIndex < files.count - 1 { currentIndex += 1 }
                } label: {
                    Text("Next →")
                        .font(Theme.caption(11))
                        .foregroundColor(currentIndex < files.count - 1 ? Theme.Colors.info : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(currentIndex >= files.count - 1)
            }

            Spacer()

            HStack(spacing: 0) {
                Button { showSplit = false } label: {
                    Text("Unified")
                        .font(Theme.caption(10))
                        .foregroundColor(!showSplit ? Theme.Colors.info : Theme.Colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(!showSplit ? Theme.Colors.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)

                Button { showSplit = true } label: {
                    Text("Split")
                        .font(Theme.caption(10))
                        .foregroundColor(showSplit ? Theme.Colors.info : Theme.Colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(showSplit ? Theme.Colors.info.opacity(0.12) : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.Colors.surfaceElevated)
            .cornerRadius(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.Colors.surface)
    }

    // MARK: - Actions

    private func performRevert(_ hash: String) {
        Task {
            do {
                try await repo.revertCommit(hash)
                actionError = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func performCherryPick(_ hash: String) {
        let branch = cherryPickBranch.trimmingCharacters(in: .whitespaces)
        cherryPickBranch = ""
        guard !branch.isEmpty else { return }
        Task {
            do {
                try await repo.cherryPickCommit(hash, onto: branch)
                actionError = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Shared Components

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Theme.caption(10))
            }
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.Colors.surfaceElevated)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.caption(9))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .cornerRadius(3)
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
                .foregroundColor(Theme.Colors.textTertiary)
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
        case "M": return Theme.Colors.statusDone
        case "A": return Theme.Colors.info
        case "D": return Theme.Colors.error
        case "R": return Theme.Colors.warning
        default: return Theme.Colors.textTertiary
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("@@") { return Theme.Colors.info }
        if line.hasPrefix("+") { return Theme.Colors.statusDone }
        if line.hasPrefix("-") { return Theme.Colors.error }
        return Theme.Colors.textSecondary
    }

    private func lineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Theme.Colors.statusDone.opacity(0.06) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Theme.Colors.error.opacity(0.05) }
        return .clear
    }

    private func lineTypeColor(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.Colors.statusDone
        case .removed: return Theme.Colors.error
        case .header: return Theme.Colors.info
        case .context: return Theme.Colors.textSecondary
        }
    }

    private func lineTypeBackground(_ type: LineType) -> Color {
        switch type {
        case .added: return Theme.Colors.statusDone.opacity(0.06)
        case .removed: return Theme.Colors.error.opacity(0.05)
        case .header, .context: return .clear
        }
    }
}
