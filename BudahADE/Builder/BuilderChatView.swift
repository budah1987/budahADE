import SwiftUI

// MARK: - Step Panel Display State

private enum StepPanelDisplayState: Equatable {
    case hidden     // pre-build or user dismissed
    case collapsed  // slim header strip only
    case expanded   // full step list visible
}

// MARK: - Step Index Wrapper (for sheet presentation)

private struct StepIndexWrapper: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Pulsing Dot

private struct PulsingDot: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Builder Chat View

struct BuilderChatView: View {
    @Bindable var session: BuilderSession
    var specTitle: String = "Spec"
    /// Raw spec markdown — shown in conversation during ready state
    var specContent: String? = nil
    /// Spec file path — used to persist edits
    var specFilePath: String? = nil

    @State private var thinkingStartDate: Date?
    @State private var scrollTarget: UUID?
    @State private var confirmTriggered = false
    @State private var confirmedMessageIds: Set<UUID> = []
    /// Local copy of spec markdown (editable)
    @State private var specMarkdown: String = ""
    /// Show spec sheet (post-build-start "View Spec" or Edit Spec button)
    @State private var showSpecSheet: Bool = false

    // Step panel state
    @State private var stepPanelState: StepPanelDisplayState = .hidden
    @State private var selectedStepIndex: Int? = nil

    /// The underlying agent session driving the builder
    var agentSession: AgentSession?
    /// Builder agent coordinator (optional — nil until build starts)
    var builderAgent: BuilderAgent?
    /// Callback to launch the builder agent (wired by parent with task context)
    var onLaunchAgent: (() -> Void)?
    /// Callback to navigate back to Plan mode
    var onBackToPlan: (() -> Void)?
    /// Callback to open spec in edit mode (if nil, handled internally via sheet)
    var onEditSpec: (() -> Void)?

    private var isRunning: Bool {
        agentSession?.status == .streaming || agentSession?.status == .connecting
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                // Step status header (compact — shows while building)
                stepHeader

                // Message list
                messageList
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [Color.clear, Theme.contentBg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .allowsHitTesting(false)
                    }

                // Inline collapsible step panel (appears once build starts)
                if stepPanelState != .hidden {
                    inlineStepPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom area: option sheet, question stepper, or input bar
                bottomArea
            }
            .background(Theme.contentBg)

            // Turn scrubber on right edge
            if !session.turnMarkers.isEmpty {
                ChatTurnScrubber(
                    markers: session.turnMarkers,
                    activeMessageId: scrollTarget,
                    stepColorProvider: { stepIndex in
                        builderStepColor(for: stepIndex, steps: session.steps)
                    },
                    onMarkerTap: { messageId in
                        scrollTarget = messageId
                    }
                )
                .padding(.top, 48)
                .padding(.trailing, 14)
            }
        }
        .onAppear {
            if let content = specContent, !content.isEmpty {
                specMarkdown = content
            }
        }
        .onChange(of: specContent) { _, newContent in
            if let content = newContent, !content.isEmpty, specMarkdown.isEmpty {
                specMarkdown = content
            }
        }
        .sheet(isPresented: $showSpecSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text(specTitle)
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Done") { showSpecSheet = false }
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.builder)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.surface2)

                Divider().opacity(0.3)

                if !specMarkdown.isEmpty {
                    ScrollView {
                        EditableMarkdownRenderer(content: $specMarkdown, onDone: {
                            showSpecSheet = false
                            saveSpec()
                        })
                        .padding(20)
                    }
                } else {
                    Spacer()
                    Text("No spec loaded")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                }
            }
            .frame(width: 680, height: 560)
            .background(Theme.contentBg)
        }
        .sheet(item: selectedStepBinding) { wrapper in
            if session.steps.indices.contains(wrapper.index) {
                StepDetailModal(
                    step: $session.steps[wrapper.index],
                    stepIndex: wrapper.index,
                    totalSteps: session.totalCount,
                    onJumpToChat: {
                        scrollTarget = session.steps[wrapper.index].chatMessageRange?.start
                        selectedStepIndex = nil
                    },
                    onViewDiff: { selectedStepIndex = nil },
                    onRetry: {
                        session.steps[wrapper.index].state = .queued
                        session.steps[wrapper.index].error = nil
                        selectedStepIndex = nil
                    },
                    onSkip: {
                        session.skipStep(at: wrapper.index)
                        selectedStepIndex = nil
                    },
                    onRemove: {
                        session.steps.remove(at: wrapper.index)
                        selectedStepIndex = nil
                    },
                    onSave: { selectedStepIndex = nil }
                )
            }
        }
        .onChange(of: session.buildState) { _, newState in
            // Auto-show panel (collapsed) when build starts
            if newState != .ready && stepPanelState == .hidden {
                withAnimation(.easeInOut(duration: 0.25)) {
                    stepPanelState = .collapsed
                }
            }
        }
        .onKeyPress(.escape) {
            guard isRunning else { return .ignored }
            cancelBuild()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if session.buildState == .ready {
                startBuild()
                return .handled
            }
            guard let agent = agentSession, !agent.confirmDismissed, !isRunning,
                  let lastMsg = agent.messages.last,
                  lastMsg.role == .assistant,
                  !lastMsg.content.isEmpty,
                  (agent.parseInteractiveMarkers(in: lastMsg.content).contains(where: {
                      if case .confirm = $0 { return true }; return false
                  }) || agent.detectConfirmation(in: lastMsg.content) != nil) else { return .ignored }
            withAnimation(.easeOut(duration: 0.15)) { confirmTriggered = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                confirmTriggered = false
                confirmedMessageIds.insert(lastMsg.id)
                agent.confirmDismissed = true
                sendHiddenConfirmation()
            }
            return .handled
        }
    }

    // MARK: - Bottom Area

    @ViewBuilder
    private var bottomArea: some View {
        if let agent = agentSession,
           !agent.optionsDismissed,
           let lastMsg = agent.messages.last,
           lastMsg.role == .assistant,
           !lastMsg.content.isEmpty,
           let options = agent.detectOptions(in: lastMsg.content),
           !options.isEmpty {
            let question = agent.detectQuestion(in: lastMsg.content)
            OptionButtonsSheet(
                contextText: question?.contextText ?? "",
                options: options,
                onSelect: { option in
                    agent.optionsDismissed = true
                    sendMessage("\(option.label). \(option.text)")
                },
                onDismiss: { agent.optionsDismissed = true },
                onCustomResponse: { text in
                    agent.optionsDismissed = true
                    sendMessage(text)
                }
            )
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let agent = agentSession,
                  !agent.questionSeriesDismissed,
                  let lastMsg = agent.messages.last,
                  lastMsg.role == .assistant,
                  !lastMsg.content.isEmpty,
                  let questions = agent.detectQuestionSeries(in: lastMsg.content),
                  !questions.isEmpty {
            QuestionStepperSheet(
                questions: questions,
                onComplete: { answers in
                    agent.questionSeriesDismissed = true
                    let response = answers.enumerated().map { i, answer in
                        "\(i + 1). \(answer)"
                    }.joined(separator: "\n")
                    sendMessage(response)
                },
                onDismiss: { agent.questionSeriesDismissed = true }
            )
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            VStack(spacing: 0) {
                // Ready state action bar — shown above input when not yet building
                if session.buildState == .ready {
                    readyStateActionBar
                }
                BuilderInputBar(
                    session: session,
                    agentSession: agentSession,
                    onSend: sendMessage,
                    onReviewDiff: reviewDiff,
                    onCommit: commitChanges
                )
            }
        }
    }

    // MARK: - Ready State Action Bar

    private var readyStateActionBar: some View {
        HStack(spacing: 6) {
            if let onBackToPlan {
                Button(action: onBackToPlan) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                        Text("Back to Plan")
                            .font(Theme.label(12))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            // Edit Spec — always visible; handled internally when onEditSpec is nil
            Button {
                if let onEditSpec { onEditSpec() } else { showSpecSheet = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                    Text("Edit Spec")
                        .font(Theme.label(12))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: startBuild) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Start Build")
                        .font(Theme.label(12))
                    Text("⌘↵")
                        .font(Theme.caption(11))
                        .opacity(0.5)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.builder)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Theme.surface2.opacity(0.88)
                Color.white.opacity(0.03)
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.6)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(height: 0.5)
        }
    }

    // MARK: - Step Header (compact top strip while building)

    private var stepHeader: some View {
        Group {
            if session.buildState == .building, let step = session.activeStep {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.builder)
                        .frame(width: 6, height: 6)
                    Text("Step \(session.completedCount + 1)/\(session.totalCount)")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.builder)
                    Text("—")
                        .foregroundStyle(Theme.textMuted)
                    Text(step.title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    // View Spec button — opens spec sheet
                    Button("View Spec") { showSpecSheet = true }
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.textSecondary)
                        .buttonStyle(.plain)
                    SpecProgressBar(steps: session.steps, size: .mini)
                        .frame(width: 100)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface2)
            }
        }
    }

    // MARK: - Inline Step Panel

    private var inlineStepPanel: some View {
        VStack(spacing: 0) {
            // Header strip — always visible when panel is not hidden
            stepPanelHeader

            // Expanded content
            if stepPanelState == .expanded {
                stepPanelList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.surface2)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
        }
    }

    private var stepPanelHeader: some View {
        HStack(spacing: 8) {
            // State dot
            Circle()
                .fill(stepStateColor)
                .frame(width: 6, height: 6)
                .modifier(PulsingDot())
                .opacity(session.buildState == .building ? 1 : 0)
                .overlay {
                    if session.buildState != .building {
                        Circle().fill(stepStateColor).frame(width: 6, height: 6)
                    }
                }

            // Progress text
            Text("\(session.completedCount)/\(session.totalCount)")
                .font(Theme.code(11, weight: .medium))
                .foregroundStyle(stepStateColor)

            // Spec title
            Text(specTitle)
                .font(Theme.label(11))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)

            // Progress bar — tap a segment to open that step's modal
            SpecProgressBar(steps: session.steps, size: .mini, onSegmentTap: { index in
                selectedStepIndex = index
                if stepPanelState == .collapsed {
                    withAnimation(.easeInOut(duration: 0.2)) { stepPanelState = .expanded }
                }
            })
            .frame(maxWidth: .infinity)

            // Expand/collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    stepPanelState = stepPanelState == .expanded ? .collapsed : .expanded
                }
            } label: {
                Image(systemName: stepPanelState == .expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Theme.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Close/hide button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    stepPanelState = .hidden
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Theme.surface3)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var stepPanelList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                        stepPanelRow(step: step, index: index)
                            .id(step.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedStepIndex = index }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 180)
            .onChange(of: session.activeStepIndex) { _, newIndex in
                guard let idx = newIndex, session.steps.indices.contains(idx) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(session.steps[idx].id, anchor: .center)
                }
            }
        }
    }

    private func stepPanelRow(step: BuildStep, index: Int) -> some View {
        let isActive = index == session.activeStepIndex

        return HStack(spacing: 8) {
            // State indicator
            stepRowIndicator(state: step.state, isActive: isActive)

            // Title
            Text(step.title)
                .font(Theme.body(12))
                .fontWeight(isActive ? .medium : .regular)
                .foregroundStyle(
                    step.state == .done ? Theme.textMuted :
                    isActive ? Theme.textPrimary :
                    Theme.textSecondary
                )
                .strikethrough(step.state == .done, color: Theme.textMuted)
                .lineLimit(1)

            Spacer()

            // Sub-task progress on active step
            if isActive && !step.subTasks.isEmpty {
                Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                    .font(Theme.code(10))
                    .foregroundStyle(Theme.builder)
            }

            // Per-step pause/resume/cancel on active row
            if isActive {
                if session.buildState == .building {
                    HStack(spacing: 2) {
                        miniActionButton("pause.fill") { pauseBuild() }
                        miniActionButton("xmark") { cancelBuild() }
                    }
                } else if session.buildState == .paused {
                    HStack(spacing: 2) {
                        miniActionButton("play.fill") { resumeBuild() }
                        miniActionButton("xmark") { cancelBuild() }
                    }
                }
            }

            // Failed attempt badge
            if step.state == .failed {
                Text("×\(step.attemptCount)")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.error.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.builder.opacity(0.08))
                : nil
        )
    }

    @ViewBuilder
    private func stepRowIndicator(state: StepState, isActive: Bool) -> some View {
        Group {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.error)
            case .skipped:
                Image(systemName: "forward.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 12)
            case .building:
                Circle()
                    .fill(Theme.builder)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingDot())
                    .frame(width: 12)
            case .queued:
                Circle()
                    .strokeBorder(Theme.textMuted.opacity(0.5), lineWidth: 1)
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func miniActionButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(Theme.surface3)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // Step panel binding for sheet presentation
    private var selectedStepBinding: Binding<StepIndexWrapper?> {
        Binding(
            get: {
                guard let idx = selectedStepIndex, session.steps.indices.contains(idx) else { return nil }
                return StepIndexWrapper(index: idx)
            },
            set: { wrapper in selectedStepIndex = wrapper?.index }
        )
    }

    private var stepStateColor: Color {
        switch session.buildState {
        case .ready:    return Theme.textMuted
        case .building: return Theme.builder
        case .paused:   return Theme.warning
        case .done:     return Theme.success
        case .failed:   return Theme.error
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty && session.buildState == .ready {
                        if !specMarkdown.isEmpty {
                            specDocumentView
                        } else {
                            readyEmptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        }
                    }

                    // Error banner
                    if let agent = agentSession, case .error(let msg) = agent.status {
                        errorBanner(msg)
                    }

                    ForEach(session.messages) { message in
                        // Step transition divider
                        if let marker = stepTransitionMarker(before: message) {
                            stepDivider(marker)
                        }

                        PlanMessageBubble(
                            message: message,
                            isSpec: false,
                            isEditing: false,
                            editableContent: .constant(message.content)
                        )
                        .id(message.id)

                        // Inline confirm button
                        if let agent = agentSession,
                           message.role == .assistant,
                           !message.content.isEmpty,
                           (agent.parseInteractiveMarkers(in: message.content).contains(where: {
                               if case .confirm = $0 { return true }; return false
                           }) || agent.detectConfirmation(in: message.content) != nil),
                           (confirmedMessageIds.contains(message.id) ||
                            (!agent.confirmDismissed &&
                             !isRunning &&
                             message.id == agent.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.id)) {
                            ConfirmButton(
                                onConfirm: {
                                    confirmedMessageIds.insert(message.id)
                                    agent.confirmDismissed = true
                                    sendHiddenConfirmation()
                                },
                                onDismiss: { agent.confirmDismissed = true },
                                externalTrigger: confirmedMessageIds.contains(message.id)
                            )
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                    }

                    // Streaming text
                    if let agent = agentSession,
                       agent.status == .streaming,
                       !agent.currentStreamingText.isEmpty {
                        MarkdownRenderer(agent.currentStreamingText, isStreaming: true)
                            .id("streaming")
                    }

                    // Activity feed
                    if let agent = agentSession,
                       (agent.status == .connecting ||
                        (agent.status == .streaming && agent.currentStreamingText.isEmpty)) {
                        ActivityFeedView(
                            activityFeed: agent.activityFeed,
                            isThinking: agent.isThinking,
                            startDate: thinkingStartDate
                        )
                        .id("thinking")
                    }

                    Color.clear.frame(height: 120).id("scroll-spacer")
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: agentSession?.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: scrollTarget) { _, newId in
                if let id = newId {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: agentSession?.activityFeed.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: agentSession?.status) { _, newValue in
                if newValue == .connecting {
                    thinkingStartDate = Date()
                    agentSession?.activityFeed = []
                    agentSession?.isThinking = false
                } else if newValue == .idle || newValue == .done || newValue == nil {
                    thinkingStartDate = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy: proxy)
                    }
                } else if case .error = newValue {
                    thinkingStartDate = nil
                }
            }
        }
    }

    // MARK: - Spec Document (ready state)

    private var specDocumentView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Click any block to edit")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 4)

            EditableMarkdownRenderer(content: $specMarkdown, onDone: {
                saveSpec()
            })
        }
        .padding(.bottom, 24)
    }

    private func saveSpec() {
        guard let path = specFilePath, !specMarkdown.isEmpty else { return }
        try? specMarkdown.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Ready State Empty

    private var readyEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.builder)
            Text("Ready to build")
                .font(Theme.label(16))
                .foregroundColor(Theme.textSecondary)
            Text("Review the spec above, then start when ready.")
                .font(Theme.body(13))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
            Text(message)
                .font(Theme.body(13))
                .foregroundColor(.red)
                .lineLimit(3)
            Spacer()
            Button("Retry") {
                agentSession?.status = .idle
            }
            .font(Theme.caption(12))
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Step Dividers

    private func stepTransitionMarker(before message: ChatMessage) -> String? {
        for (index, step) in session.steps.enumerated() {
            if step.chatMessageRange?.start == message.id {
                return "Step \(index + 1): \(step.title)"
            }
        }
        return nil
    }

    private func stepDivider(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
            Text(text)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textMuted)
                .fixedSize()
            Rectangle().fill(Theme.borderSubtle).frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Scroll

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let id: AnyHashable? = {
            if let agent = agentSession {
                if agent.status == .connecting ||
                   (agent.status == .streaming && agent.currentStreamingText.isEmpty) {
                    return "thinking"
                } else if agent.status == .streaming {
                    return "streaming"
                }
            }
            if let last = session.messages.last {
                return last.id
            }
            return nil
        }()
        if let id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        if let agent = builderAgent {
            agent.sendMessage(text)
        } else {
            let message = ChatMessage(role: .user, content: text)
            session.messages.append(message)
            session.addTurnMarker(for: message)
        }
    }

    private func sendHiddenConfirmation() {
        if let agent = builderAgent {
            agent.sendMessage("Yes, looks good. Proceed.")
        }
    }

    private func startBuild() {
        onLaunchAgent?()
    }

    private func pauseBuild() {
        builderAgent?.pause()
    }

    private func resumeBuild() {
        builderAgent?.resume()
    }

    private func cancelBuild() {
        builderAgent?.cancel()
    }

    private func retryFailed() {
        for index in session.steps.indices where session.steps[index].state == .failed {
            session.steps[index].state = .queued
            session.steps[index].error = nil
        }
        if let agent = builderAgent {
            let stepIdx = session.steps.indices.first(where: { session.steps[$0].state == .queued }) ?? 0
            session.startStep(at: stepIdx)
            agent.resume()
        }
    }

    private func reviewDiff() {
        NotificationCenter.default.post(name: .toggleRightPanel, object: nil)
    }

    private func commitChanges() {
        NotificationCenter.default.post(name: .toggleRightPanel, object: nil)
    }
}
