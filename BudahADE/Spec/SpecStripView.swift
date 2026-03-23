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
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(specState.completedCount)/\(specState.totalCount)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
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
                    .foregroundColor(Theme.textMuted)
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(progressColor)

                // Segmented progress bar (section-aware)
                sectionSegmentedProgress
                    .frame(width: 120)

                Text("\(specState.completedCount)/\(specState.totalCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)

                if let section = specState.currentSection {
                    Text(section.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }

                Text(specState.result?.title ?? "")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Build status action row
            if buildStatus.status != .idle, let action = buildStatus.lastAction {
                HStack(spacing: 6) {
                    Circle()
                        .fill(buildStatus.status == .blocked
                            ? Color(hex: 0xE06C75)
                            : Theme.accent)
                        .frame(width: 4, height: 4)
                    Text(buildStatus.status == .blocked
                        ? (buildStatus.blockers ?? "Blocked")
                        : action)
                        .font(.system(size: 10))
                        .foregroundColor(buildStatus.status == .blocked
                            ? Color(hex: 0xE06C75)
                            : Theme.textMuted)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(Theme.sidebar.opacity(0.5))
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
        specState.progress >= 1.0 ? Theme.success : Theme.accent
    }
}
