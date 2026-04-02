import SwiftUI

// MARK: - Builder Input Bar

struct BuilderInputBar: View {
    @Bindable var session: BuilderSession
    var onSend: (String) -> Void
    var onStart: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onCancel: () -> Void
    var onRetry: () -> Void
    var onReviewDiff: () -> Void
    var onCommit: () -> Void

    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            HStack(spacing: 8) {
                // Left: state-aware controls
                leftControls

                // Center: status text
                statusText
                    .frame(maxWidth: .infinity)

                // Right: primary action + input
                rightControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Text input — always available
            HStack(spacing: 8) {
                TextField("Talk to the builder...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($inputFocused)
                    .onSubmit {
                        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSend(inputText)
                        inputText = ""
                    }

                if !inputText.isEmpty {
                    Button {
                        onSend(inputText)
                        inputText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.builder)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(Theme.contentBg)
    }

    // MARK: - Left Controls

    @ViewBuilder
    private var leftControls: some View {
        switch session.buildState {
        case .ready:
            EmptyView()
        case .building:
            HStack(spacing: 6) {
                iconButton("pause.fill", action: onPause)
                iconButton("xmark", action: onCancel)
            }
        case .paused:
            HStack(spacing: 6) {
                iconButton("play.fill", action: onResume)
                iconButton("xmark", action: onCancel)
            }
        case .done:
            EmptyView()
        case .failed:
            iconButton("arrow.clockwise", action: onRetry)
        }
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        switch session.buildState {
        case .ready:
            Text("Review spec, then start")
                .font(Theme.code(12))
                .foregroundStyle(Theme.textMuted)
        case .building:
            if let step = session.activeStep {
                Text("Step \(session.completedCount + 1)/\(session.totalCount) — \(step.title)")
                    .font(Theme.code(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        case .paused:
            Text("Paused at step \(session.completedCount + 1)")
                .font(Theme.code(12))
                .foregroundStyle(Theme.warning)
        case .done:
            Text("Build complete — \(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(12))
                .foregroundStyle(Theme.success)
        case .failed:
            Text("Failed at step \((session.activeStepIndex ?? 0) + 1)")
                .font(Theme.code(12))
                .foregroundStyle(Theme.error)
        }
    }

    // MARK: - Right Controls

    @ViewBuilder
    private var rightControls: some View {
        switch session.buildState {
        case .ready:
            Button(action: onStart) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Start Build")
                        .font(Theme.label(12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.builder)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        case .building, .paused:
            EmptyView()
        case .done:
            HStack(spacing: 6) {
                Button(action: onReviewDiff) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10))
                        Text("Review Diff")
                            .font(Theme.label(12))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: onCommit) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                        Text("Commit")
                            .font(Theme.label(12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.success)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        case .failed:
            HStack(spacing: 6) {
                Button {
                    // Edit step — will be wired to StepDetailModal
                } label: {
                    Text("Edit Step")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button {
                    // Skip current failed step
                    if let idx = session.activeStepIndex {
                        session.skipStep(at: idx)
                    }
                } label: {
                    Text("Skip")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
