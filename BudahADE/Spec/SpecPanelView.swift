import SwiftUI

struct SpecPanelView: View {
    @ObservedObject var specState: SpecState
    @ObservedObject var buildStatus: BuildStatusState
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if specState.hasSpec {
                specContent
            } else {
                emptyState
            }
        }
    }

    // MARK: - Spec Content

    private var specContent: some View {
        VStack(spacing: 0) {
            // Spec picker (multi-spec)
            if specState.allSpecs.count > 1 {
                specPicker
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Progress header with collapse toggle
            HStack {
                progressHeader
                collapseToggle
            }
            .padding(.horizontal, 12)
            .padding(.top, specState.allSpecs.count > 1 ? 4 : 10)
            .padding(.bottom, 6)

            // Block graph — always visible (even when collapsed)
            SpecBlockGraphView(specState: specState, buildStatus: buildStatus)

            if isExpanded {
                // Build status row with elapsed time
                if buildStatus.status != .idle {
                    buildStatusRow
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)

                // Section-grouped task list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let spec = specState.activeSpec {
                            if spec.sections.isEmpty {
                                ForEach(spec.tasks) { task in
                                    taskRow(task: task, spec: spec)
                                }
                            } else {
                                ForEach(spec.sections) { section in
                                    sectionGroup(section: section, spec: spec)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                // File path
                if let spec = specState.activeSpec {
                    filePath(spec)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Collapse Toggle

    private var collapseToggle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Group

    @ViewBuilder
    private func sectionGroup(section: SpecSection, spec: SpecParseResult) -> some View {
        DisclosureGroup {
            if section.tasks.isEmpty {
                // Content preview for non-task sections
                let preview = section.content
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .prefix(3)
                    .joined(separator: "\n")

                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            } else {
                ForEach(section.tasks) { task in
                    taskRow(task: task, spec: spec, sectionId: section.id)
                }
            }
        } label: {
            sectionHeader(section: section)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func sectionHeader(section: SpecSection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            if section.totalCount > 0 {
                Text("\(section.completedCount)/\(section.totalCount)")
                    .font(Theme.mono(9))
                    .foregroundColor(
                        section.progress >= 1.0 ? Theme.success : Theme.textMuted
                    )
            }
        }
    }

    // MARK: - Build Status Row

    private var buildStatusRow: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(buildStatus.status == .blocked ? Color(hex: 0xE06C75) : Theme.accent)
                .frame(width: 6, height: 6)

            if buildStatus.status == .blocked, let blocker = buildStatus.blockers {
                Text(blocker)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: 0xE06C75))
                    .lineLimit(2)
            } else if let action = buildStatus.lastAction {
                Text(action)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)

                if let elapsed = buildStatus.elapsed {
                    Text(elapsed)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.textMuted.opacity(0.6))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(buildStatus.status == .blocked
                    ? Color(hex: 0xE06C75).opacity(0.08)
                    : Theme.accent.opacity(0.06))
        )
    }

    // MARK: - Spec Picker

    private var specPicker: some View {
        Menu {
            ForEach(Array(specState.allSpecs.enumerated()), id: \.offset) { index, spec in
                Button {
                    specState.selectSpec(at: index)
                } label: {
                    HStack {
                        Text(spec.title ?? specFileName(spec.filePath))
                        if index == specState.selectedSpecIndex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(specState.activeSpec?.title ?? "Spec")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Text("\(specState.allSpecs.count) specs")
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.borderSubtle, lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(specState.activeSpec?.title ?? "Spec")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(specState.completedCount) of \(specState.totalCount)")
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.textSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * specState.progress, height: 4)
                        .animation(.easeOut(duration: 0.3), value: specState.progress)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Task Row

    private func taskRow(task: SpecTask, spec: SpecParseResult, sectionId: String? = nil) -> some View {
        let firstUncheckedId = spec.tasks.first(where: { !$0.isCompleted })?.id
        let isCurrent = task.id == firstUncheckedId
        let isActiveInBuild = isCurrent && buildStatus.status == .working
                && buildStatus.currentTaskIndex == task.id

        return HStack(spacing: 8) {
            // Status indicator
            if task.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.success)
            } else if isActiveInBuild {
                // Pulsing indicator for actively building
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 2)
                    .modifier(PulsingModifier())
            } else if isCurrent {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 2)
            } else {
                Circle()
                    .strokeBorder(Theme.textMuted.opacity(0.5), lineWidth: 1)
                    .frame(width: 12, height: 12)
            }

            // Task title + optional action text
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(
                        task.isCompleted ? Theme.textMuted :
                        isCurrent ? Theme.textPrimary : Theme.textSecondary
                    )
                    .strikethrough(task.isCompleted, color: Theme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isActiveInBuild, let action = buildStatus.lastAction {
                    Text(action)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isCurrent
                ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.accent.opacity(0.08))
                : nil
        )
        .padding(.horizontal, 4)
    }

    // MARK: - File Path

    private func filePath(_ spec: SpecParseResult) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)

            Button {
                let url = URL(fileURLWithPath: spec.filePath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Text(specFileName(spec.filePath))
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No spec file")
                .font(Theme.label(12))
                .foregroundColor(Theme.textMuted)
            Text("Create a *-spec.md to track progress")
                .font(Theme.caption(11))
                .foregroundColor(Theme.textMuted.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var progressColor: Color {
        specState.progress >= 1.0 ? Theme.success : Theme.accent
    }

    private func specFileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
