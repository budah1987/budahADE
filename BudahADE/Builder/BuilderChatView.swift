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

    // Input bar state (owned here, passed as binding to ChatInputBar)
    @State private var builderInputText: String = ""
    @State private var builderSelectedModel: AgentModel = .sonnet

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
    /// Git branch name — shown in spec header
    var branchName: String? = nil

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
                            colors: [Color.clear, Theme.Colors.appBackground],
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
            .background(Theme.Colors.appBackground)

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
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Button("Done") { showSpecSheet = false }
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.Colors.statusWorking)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.Colors.surface)

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
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                }
            }
            .frame(width: 680, height: 560)
            .background(Theme.Colors.appBackground)
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
                ChatInputBar(
                    inputText: $builderInputText,
                    selectedModel: $builderSelectedModel,
                    session: agentSession,
                    isRunning: isRunning,
                    onSend: sendMessage,
                    placeholder: "Talk to the builder…",
                    aboveInput: {
                        // Done state: Review Diff + Commit buttons
                        if session.buildState == .done {
                            HStack(spacing: 8) {
                                Spacer()
                                Button(action: reviewDiff) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 10))
                                        Text("Review Diff")
                                            .font(Theme.label(12))
                                    }
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.Colors.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)

                                Button(action: commitChanges) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 10))
                                        Text("Commit")
                                            .font(Theme.label(12))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.Colors.statusDone)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    },
                    topBarExtras: { EmptyView() }
                )
            }
        }
    }

    // MARK: - Ready State Action Bar

    private var readyStateActionBar: some View {
        HStack(spacing: 0) {
            // Left: Edit Spec first, then Back to Plan
            HStack(spacing: 16) {
                Button {
                    if let onEditSpec { onEditSpec() } else { showSpecSheet = true }
                } label: {
                    Text("Edit Spec")
                        .font(Theme.label(12))
                        .foregroundStyle(Color(hex: 0x888888))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(Color(hex: 0x34353A))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if let onBackToPlan {
                    Button(action: onBackToPlan) {
                        Text("Back to Plan")
                            .font(Theme.label(12))
                            .foregroundStyle(Color(hex: 0x888888))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                            .background(Color(hex: 0x34353A))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Right: Start Build — white with subtle purple glow
            Button(action: startBuild) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.black.opacity(0.85))
                    Text("Start Build")
                        .font(.custom("Geist-SemiBold", size: 13))
                        .foregroundColor(.black)
                    Text("⌘↵")
                        .font(Theme.caption(10))
                        .foregroundColor(Color.black.opacity(0.45))
                }
                .padding(.vertical, 8)
                .padding(.leading, 18)
                .padding(.trailing, 20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color(hex: 0x8B5CF6).opacity(0.15), radius: 12, x: 0, y: 0)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(hex: 0x1F1F1F).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Step Header (compact top strip while building)

    private var stepHeader: some View {
        Group {
            if session.buildState == .building, let step = session.activeStep {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.Colors.statusWorking)
                        .frame(width: 6, height: 6)
                    Text("Step \(session.completedCount + 1)/\(session.totalCount)")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.Colors.statusWorking)
                    Text("—")
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(step.title)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    // View Spec button — opens spec sheet
                    Button("View Spec") { showSpecSheet = true }
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .buttonStyle(.plain)
                    SpecProgressBar(steps: session.steps, size: .mini)
                        .frame(width: 100)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.Colors.surface)
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
        .background(Theme.Colors.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 0.5)
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
                .foregroundStyle(Theme.Colors.textTertiary)
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
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Colors.surfaceElevated)
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
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Colors.surfaceElevated)
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
                .font(Theme.body(11))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(
                    step.state == .done ? Color.white.opacity(0.25) :
                    isActive ? Color(hex: 0xFFFFFF).opacity(0.8) :
                    Color.white.opacity(0.2)
                )
                .strikethrough(step.state == .done, color: Color.white.opacity(0.2))
                .lineLimit(1)

            Spacer()

            // Sub-task progress on active step
            if isActive && !step.subTasks.isEmpty {
                Text("\(step.subTasksDone)/\(step.subTasksTotal)")
                    .font(Theme.code(10))
                    .foregroundStyle(Theme.Colors.statusWorking)
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
                    .foregroundStyle(Theme.Colors.error.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0xA78BFA).opacity(0.051))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color(hex: 0xA78BFA).opacity(0.122), lineWidth: 1))
                : nil
        )
    }

    @ViewBuilder
    private func stepRowIndicator(state: StepState, isActive: Bool) -> some View {
        Group {
            switch state {
            case .done:
                Text("✓")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.statusDone)
                    .frame(width: 12)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.error)
                    .frame(width: 12)
            case .skipped:
                Image(systemName: "forward.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .frame(width: 12)
            case .building:
                Circle()
                    .fill(Theme.Colors.statusWorking)
                    .frame(width: 4, height: 4)
                    .modifier(PulsingDot())
                    .frame(width: 12)
            case .queued:
                Circle()
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 6, height: 6)
                    .frame(width: 12)
            }
        }
    }

    private func miniActionButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 22, height: 22)
                .background(Theme.Colors.surfaceElevated)
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
        case .ready:    return Theme.Colors.textTertiary
        case .building: return Theme.Colors.statusWorking
        case .paused:   return Theme.Colors.warning
        case .done:     return Theme.Colors.statusDone
        case .failed:   return Theme.Colors.error
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.buildState == .ready {
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
        VStack(alignment: .leading, spacing: 0) {
            specHeaderView
            Text("Click any block to edit")
                .font(Theme.caption(11))
                .foregroundStyle(Color(hex: 0xAEAEAE))
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            EditableMarkdownRenderer(content: $specMarkdown, onDone: { saveSpec() })
        }
        .padding(.bottom, 24)
    }

    private var specHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Filename · from · Spec Author
            HStack(spacing: 6) {
                if let path = specFilePath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(Theme.code(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 12)
                Text("from")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0x666666)).frame(width: 5, height: 5)
                    Text("Spec Author")
                        .font(Theme.body(11))
                        .foregroundStyle(Color(hex: 0x666666))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Large title
            Text(specTitle)
                .font(.custom("Geist-SemiBold", size: 28))
                .foregroundStyle(Color(hex: 0xE8E8E8))
                .tracking(-0.5)

            // Stats row
            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Text("\(session.totalCount)")
                        .font(Theme.code(12))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: 0xA78BFA))
                    Text("tasks")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 12)
                if let branch = branchName {
                    Text(branch)
                        .font(Theme.code(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .padding(.bottom, 16)
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
                .foregroundColor(Theme.Colors.statusWorking)
            Text("Ready to build")
                .font(Theme.label(16))
                .foregroundColor(Theme.Colors.textSecondary)
            Text("Review the spec above, then start when ready.")
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textTertiary)
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
            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 1)
            Text(text)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize()
            Rectangle().fill(Theme.Colors.borderSubtle).frame(height: 1)
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
