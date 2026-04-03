import SwiftUI

// MARK: - Spec Strip Variant

enum SpecStripVariant {
    case compact  // Vertical layout for task rail
    case inline   // Horizontal layout for top bar
}

/// Spec progress strip — compact (task rail) or inline (top bar)
struct SpecStripView: View {
    @ObservedObject var specState: SpecState
    @ObservedObject var buildStatus: BuildStatusState
    var variant: SpecStripVariant = .compact
    /// Whether the builder is running (shows drawer toggle in inline variant)
    var hasBuilder: Bool = false
    /// Binding to toggle the builder drawer open/closed
    var isBuilderDrawerOpen: Binding<Bool>

    init(
        specState: SpecState,
        buildStatus: BuildStatusState,
        variant: SpecStripVariant = .compact,
        hasBuilder: Bool = false,
        isBuilderDrawerOpen: Binding<Bool> = .constant(false)
    ) {
        self.specState = specState
        self.buildStatus = buildStatus
        self.variant = variant
        self.hasBuilder = hasBuilder
        self.isBuilderDrawerOpen = isBuilderDrawerOpen
    }

    var body: some View {
        if specState.hasSpec {
            switch variant {
            case .compact:
                compactLayout
            case .inline:
                inlineLayout
            }
        }
    }

    // MARK: - Compact (Task Rail)

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(specState.result?.title ?? "Spec")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(specState.completedCount)/\(specState.totalCount)")
                    .font(Theme.label(9))
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * specState.progress, height: 3)
                        .animation(.easeOut(duration: 0.3), value: specState.progress)
                }
            }
            .frame(height: 3)

            if let current = specState.currentTaskTitle {
                Text(current)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Inline (Top Bar)

    private var inlineLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("SPEC")
                    .font(Theme.headline(9))
                    .foregroundColor(progressColor)

                // Segmented progress bar (section-aware)
                sectionSegmentedProgress
                    .frame(width: 120)

                Text("\(specState.completedCount)/\(specState.totalCount)")
                    .font(Theme.label(10))
                    .foregroundColor(Theme.Colors.textSecondary)

                if let section = specState.currentSection {
                    Text(section.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

                Text(specState.result?.title ?? "")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .lineLimit(1)

                Spacer()

                // Builder drawer toggle
                if hasBuilder {
                    Button {
                        isBuilderDrawerOpen.wrappedValue.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(builderDotColor)
                                .frame(width: 5, height: 5)
                            Image(systemName: isBuilderDrawerOpen.wrappedValue ? "chevron.up" : "terminal")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isBuilderDrawerOpen.wrappedValue ? Theme.Colors.accent.opacity(0.12) : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Build status action row
            if buildStatus.status != .idle, let action = buildStatus.lastAction {
                HStack(spacing: 6) {
                    Circle()
                        .fill(buildStatus.status == .blocked
                            ? Color(hex: 0xE06C75)
                            : Theme.Colors.accent)
                        .frame(width: 4, height: 4)
                    Text(buildStatus.status == .blocked
                        ? (buildStatus.blockers ?? "Blocked")
                        : action)
                        .font(.system(size: 10))
                        .foregroundColor(buildStatus.status == .blocked
                            ? Color(hex: 0xE06C75)
                            : Theme.Colors.textTertiary)
                        .lineLimit(1)

                    if buildStatus.status == .working, let elapsed = buildStatus.elapsed {
                        Text(elapsed)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.Colors.textTertiary.opacity(0.6))
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(Theme.Colors.sidebarBackground.opacity(0.5))
    }

    // MARK: - Section-Segmented Progress

    private var sectionSegmentedProgress: some View {
        HStack(spacing: 1) {
            let sections = specState.sections.filter { $0.totalCount > 0 }
            if sections.isEmpty {
                // Fallback to flat segmented progress
                flatSegmentedProgress
            } else {
                ForEach(sections) { section in
                    HStack(spacing: 1) {
                        ForEach(section.tasks) { task in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(task.isCompleted ? progressColor : Color.white.opacity(0.1))
                                .frame(height: 4)
                        }
                    }

                    // Section divider
                    if section.id != sections.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1, height: 6)
                    }
                }
            }
        }
    }

    private var flatSegmentedProgress: some View {
        HStack(spacing: 2) {
            ForEach(0..<specState.totalCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < specState.completedCount ? progressColor : Color.white.opacity(0.1))
                    .frame(height: 4)
                    .animation(.easeOut(duration: 0.2), value: specState.completedCount)
            }
        }
    }

    // MARK: - Helpers

    private var progressColor: Color {
        specState.progress >= 1.0 ? Theme.Colors.statusDone : Theme.Colors.accent
    }

    private var builderDotColor: Color {
        switch buildStatus.status {
        case .working:   return Theme.Colors.accent
        case .blocked:   return Color(hex: 0xE06C75)
        case .completed: return Theme.Colors.statusDone
        case .idle:      return Theme.Colors.textTertiary
        }
    }
}
