import SwiftUI

/// Live spec viewer/editor tile for the Plan canvas.
/// Shows sections with headers, interactive checkboxes, and detach buttons.
struct SpecDocumentTileView: View {
    let path: String
    @ObservedObject var canvas: PlanCanvasState
    let elementId: UUID
    let onClose: () -> Void

    @State private var spec: SpecParseResult?
    @State private var pollTimer: Timer?

    private var filename: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        TileChrome(
            title: spec?.title ?? filename,
            icon: "doc.badge.gearshape",
            onClose: onClose
        ) {
            if let spec {
                specContent(spec)
            } else {
                emptyState
            }
        }
        .onAppear {
            loadSpec()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Spec Content

    private func specContent(_ spec: SpecParseResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Overall progress
                progressBar(spec)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)

                // Sections
                ForEach(spec.sections) { section in
                    sectionView(section, spec: spec)
                }
            }
        }
    }

    // MARK: - Progress Bar

    private func progressBar(_ spec: SpecParseResult) -> some View {
        HStack(spacing: 8) {
            Text("\(spec.completedCount)/\(spec.totalCount)")
                .font(Theme.mono(10))
                .foregroundColor(spec.progress >= 1.0 ? Theme.success : Theme.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(spec.progress >= 1.0 ? Theme.success : Theme.accent)
                        .frame(width: geo.size.width * spec.progress, height: 3)
                        .animation(.easeOut(duration: 0.3), value: spec.progress)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Section View

    private func sectionView(_ section: SpecSection, spec: SpecParseResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with detach button
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                if section.totalCount > 0 {
                    Text("\(section.completedCount)/\(section.totalCount)")
                        .font(Theme.mono(9))
                        .foregroundColor(section.progress >= 1.0 ? Theme.success : Theme.textMuted)
                }

                Spacer()

                // Detach button
                Button {
                    canvas.detachSpecSection(
                        specTileId: elementId,
                        sectionId: section.id,
                        specPath: path
                    )
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Detach section to canvas tile")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface2.opacity(0.5))

            // Section content
            if section.tasks.isEmpty {
                // Non-task section: show content preview
                let preview = section.content
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .prefix(5)
                    .joined(separator: "\n")

                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            } else {
                // Task section: show checkboxes
                ForEach(section.tasks) { task in
                    taskRow(task, section: section)
                }
            }

            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
        }
    }

    // MARK: - Task Row (Interactive Checkbox)

    private func taskRow(_ task: SpecTask, section: SpecSection) -> some View {
        Button {
            toggleTask(task)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(task.isCompleted ? Theme.success : Theme.textMuted)

                Text(task.title)
                    .font(.system(size: 11, weight: task.isCompleted ? .regular : .medium))
                    .foregroundColor(task.isCompleted ? Theme.textMuted : Theme.textPrimary)
                    .strikethrough(task.isCompleted, color: Theme.textMuted)
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

    // MARK: - Toggle Checkbox

    private func toggleTask(_ task: SpecTask) {
        guard var content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        var newLines = lines

        // Find the line matching this task and toggle it
        var taskCounter = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("- [ ] ") {
                if taskCounter == task.id {
                    if task.isCompleted {
                        // Uncheck: [x] → [ ]
                        newLines[i] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                            .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                    } else {
                        // Check: [ ] → [x]
                        newLines[i] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                    }
                    break
                }
                taskCounter += 1
            }
        }

        content = newLines.joined(separator: "\n")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)

        // Reload
        loadSpec()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted)
            Text("Spec not found")
                .font(Theme.body(13))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Polling

    private func loadSpec() {
        spec = SpecParser.parse(fileAt: path)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                loadSpec()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
