import SwiftUI

struct MarkdownTileView: View {
    let path: String
    @ObservedObject var canvas: PlanCanvasState
    let elementId: UUID
    let onClose: () -> Void

    @State private var spec: SpecParseResult?
    @State private var sections: [MarkdownSection] = []
    @State private var editingSectionId: String?
    @State private var editContent: String = ""
    @State private var pollTimer: Timer?

    private var filename: String { (path as NSString).lastPathComponent }
    private var hasCheckboxes: Bool { sections.contains { !$0.checkboxItems.isEmpty } }

    var body: some View {
        TileChrome(
            title: spec?.title ?? filename,
            icon: hasCheckboxes ? "doc.badge.gearshape" : "doc.text",
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                // Progress bar (only if has checkboxes)
                if let spec, spec.totalCount > 0 {
                    progressBar(spec)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)
                }

                // Sections
                if sections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                sectionView(section)
                            }
                        }
                    }
                    .background(Color.clear.contentShape(Rectangle()))
                    .onTapGesture { commitCurrentEdit() }
                }

                Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)

                // Footer
                tileFooter
            }
        }
        .onAppear { reload(); startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Progress Bar

    private func progressBar(_ spec: SpecParseResult) -> some View {
        HStack(spacing: 8) {
            Text("\(spec.completedCount)/\(spec.totalCount)")
                .font(Theme.label(12))
                .foregroundColor(spec.progress >= 1.0 ? Theme.Colors.statusDone : Theme.Colors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(spec.progress >= 1.0 ? Theme.Colors.statusDone : Theme.Colors.accent)
                        .frame(width: geo.size.width * spec.progress, height: 3)
                        .animation(.easeOut(duration: 0.3), value: spec.progress)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Section View

    private func sectionView(_ section: MarkdownSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Text(section.heading)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)

                // Source attribution
                if let sourceId = section.sourceId {
                    HStack(spacing: 3) {
                        Circle().fill(Theme.Colors.accent).frame(width: 6, height: 6)
                        Text("from \(sourceId)")
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }

                if !section.checkboxItems.isEmpty {
                    let done = section.checkboxItems.filter(\.isCompleted).count
                    Text("\(done)/\(section.checkboxItems.count)")
                        .font(Theme.caption(11))
                        .foregroundColor(done == section.checkboxItems.count ? Theme.Colors.statusDone : Theme.Colors.textTertiary)
                }

                Spacer()

                // Detach button
                Button {
                    canvas.detachSpecSection(specTileId: elementId, sectionId: section.id, specPath: path)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Detach section to canvas tile")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.Colors.surface.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture {
                if editingSectionId != nil && editingSectionId != section.id {
                    commitCurrentEdit()
                }
            }

            // Section content: edit mode or display mode
            if editingSectionId == section.id {
                // Edit mode
                TextEditor(text: $editContent)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .onExitCommand { commitEdit(section) }
            } else {
                // Display mode: show checkboxes or content preview
                if section.checkboxItems.isEmpty {
                    // Non-task section: content preview (clickable to edit)
                    let preview = section.body
                        .components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .prefix(5)
                        .joined(separator: "\n")
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(5)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { startEditing(section) }
                    }
                } else {
                    // Task section: show checkboxes
                    ForEach(section.checkboxItems) { task in
                        taskRow(task)
                    }
                }
            }

            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)
        }
    }

    // MARK: - Task Row

    private func taskRow(_ task: SpecTask) -> some View {
        Button { toggleTask(task) } label: {
            HStack(spacing: 8) {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundColor(task.isCompleted ? Theme.Colors.statusDone : Theme.Colors.textTertiary)
                Text(task.title)
                    .font(.system(size: 13, weight: task.isCompleted ? .regular : .medium))
                    .foregroundColor(task.isCompleted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                    .strikethrough(task.isCompleted, color: Theme.Colors.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editing

    private func startEditing(_ section: MarkdownSection) {
        if editingSectionId != nil {
            commitCurrentEdit()
        }
        editingSectionId = section.id
        editContent = section.body
    }

    private func commitCurrentEdit() {
        guard let editingId = editingSectionId,
              let section = sections.first(where: { $0.id == editingId }) else { return }
        commitEdit(section)
    }

    private func commitEdit(_ section: MarkdownSection) {
        guard editingSectionId == section.id else { return }
        editingSectionId = nil

        // Read file fresh — don't rely on stale lineRange
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: .newlines)

        // Find the heading line in the current file content
        guard let headingIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## \(section.heading)"
        }) else { return }

        // Find the end of this section (next ## heading or EOF)
        var endIdx = lines.count
        for i in (headingIdx + 1)..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                endIdx = i
                break
            }
        }

        // Replace: keep heading line, replace body
        let headingLine = lines[headingIdx]
        let newLines = [headingLine] + editContent.components(separatedBy: .newlines)
        lines.replaceSubrange(headingIdx..<endIdx, with: newLines)

        let newContent = lines.joined(separator: "\n")
        try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
        reload()
    }

    // MARK: - Toggle Checkbox

    private func toggleTask(_ task: SpecTask) {
        guard var content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        content = SpecParser.toggleCheckbox(in: content, at: task.id)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        reload()
    }

    // MARK: - Footer

    private var tileFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 9))
                .foregroundColor(Theme.Colors.textTertiary)
            Text(filename)
                .font(Theme.body(11))
                .foregroundColor(Theme.Colors.textTertiary)
            Spacer()
            Text("\(sections.count) sections")
                .font(Theme.caption(11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Empty document")
                .font(Theme.body(14))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Loading

    private func reload() {
        spec = SpecParser.parse(fileAt: path)
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            sections = SpecParser.parseMarkdownSections(from: content)
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                // Don't reload while user is editing — would clobber editing state
                guard editingSectionId == nil else { return }
                reload()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
