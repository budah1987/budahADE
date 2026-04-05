import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - PlanChatView

struct PlanChatView: View {
    @ObservedObject var state: PlanChatState

    /// Sibling plan tabs (other than this one) — used for Hand off popover.
    var siblingTabs: [PlanTabInfo] = []
    /// Called when user picks Hand off → target tab.
    var onHandOff: ((UUID) -> Void)? = nil
    /// Called when user picks Hand off but no sibling exists — creates a new tab with the role and hands off.
    var onCreateAndHandOff: ((AgentMode) -> Void)? = nil
    /// Called when user approves spec and wants to transition to Build mode.
    /// Parameter: item count from the approved spec.
    var onApproveToBuild: ((Int) -> Void)? = nil

    @State private var inputText: String = ""
    @State private var thinkingStartDate: Date?
    @State private var slashPopoverIndex: Int = 0
    @State private var keyMonitor: Any?
    @StateObject private var slashState = SlashPopoverState()
    @State private var confirmTriggered = false
    @State private var confirmedMessageIds: Set<UUID> = []
    @State private var slashCommandSelected = false
    @State private var scrollToMessage: UUID?
    @State private var fastThinkingEnabled = false
    @State private var planModeEnabled = false

    /// Whether the slash command popover should be visible
    private var showSlashPopover: Bool {
        inputText.hasPrefix("/") && !isRunning && !slashCommandSelected
    }

    /// The filter text after the "/"
    private var slashFilter: String {
        guard inputText.hasPrefix("/") else { return "" }
        let afterSlash = String(inputText.dropFirst())
        // Only filter on the first word (before any space = arguments)
        return afterSlash.split(separator: " ").first.map(String.init) ?? afterSlash
    }

    /// Default commands to show before CLI init event provides the real list
    private static let defaultRemoteCommands = [
        "update-config", "debug", "simplify", "batch", "loop", "schedule",
        "claude-api", "qmd-sessions", "site-extract", "prepare-to-build",
        "handoff", "find-skills", "figma-design-system", "design-apply",
        "design-extract", "kill-mcp", "notion-update", "figma-connect",
        "interface-design:extract", "interface-design:status",
        "interface-design:audit", "interface-design:init",
        "interface-design:interface-design",
        "figma-friend:figma-designer", "figma-friend:clone-ui",
        "compact", "context", "cost", "heapdump", "init",
        "pr-comments", "release-notes", "review", "security-review",
        "extra-usage", "insights",
    ]

    /// Ghost text completion — shows the full command with typed portion + faint remainder
    private var ghostCompletion: String? {
        guard showSlashPopover, !allCommands.isEmpty else { return nil }
        let idx = min(slashPopoverIndex, allCommands.count - 1)
        let command = allCommands[idx]
        // Show the full "/command" as ghost text
        return "/\(command)"
    }

    /// All available commands (local + from CLI or defaults)
    private var allCommands: [String] {
        let local = ["clear", "model"]
        let remote = session?.availableCommands.isEmpty == false
            ? session!.availableCommands
            : Self.defaultRemoteCommands
        let all = local + remote
        if slashFilter.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(slashFilter) }
    }

    private var session: AgentSession? { state.plannerSession }
    private var isRunning: Bool {
        session?.status == .streaming || session?.status == .connecting
    }

    /// True when there's at least one assistant message
    private var hasAssistantMessage: Bool {
        session?.messages.contains { $0.role == .assistant } == true
    }

    /// Whether a spec is ready (file written to disk OR spec structure in messages)
    private var isSpecComplete: Bool {
        state.specReadySignalId != nil
    }

    // InputHeightKey moved to Shared/ChatInputBar.swift

    var body: some View {
        VStack(spacing: 0) {
            // Role indicator
            HStack(spacing: 6) {
                Image(systemName: state.role.iconName)
                    .foregroundStyle(state.role.dotColor)
                Text(state.role.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Messages + turn scrubber (right edge, vertical)
            ZStack(alignment: .trailing) {
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

                if !state.turnMarkers.isEmpty {
                    ChatTurnScrubber(
                        markers: state.turnMarkers,
                        onMarkerTap: { messageId in
                            scrollToMessage = messageId
                        }
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 22)
                }
            }

            // Interactive detection: markers first, regex fallback
            if let session,
               let lastMsg = session.messages.last,
               lastMsg.role == .assistant,
               !lastMsg.content.isEmpty,
               let markerBlock = session.parseInteractiveMarkers(in: lastMsg.content).first {
                // Marker-based detection — agent emitted structured markers
                switch markerBlock {
                case .choice(let options) where !session.optionsDismissed:
                    if let detectedOptions = markerBlock.asDetectedOptions {
                        let question = session.detectQuestion(in: lastMsg.content)
                        let specReady = state.looksLikeSpec(lastMsg.content)
                        OptionButtonsSheet(
                            contextText: question?.contextText ?? "",
                            options: detectedOptions,
                            showApproveAndBuild: specReady,
                            onSelect: { option in
                                session.optionsDismissed = true
                                state.sendMessage("\(option.label). \(option.text)")
                            },
                            onDismiss: {
                                session.optionsDismissed = true
                            },
                            onCustomResponse: { text in
                                session.optionsDismissed = true
                                state.sendMessage(text)
                            },
                            onApproveAndBuild: {
                                session.optionsDismissed = true
                                handleApprove()
                            }
                        )
                        .frame(maxWidth: 752)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        inputArea
                    }
                case .questions where !session.questionSeriesDismissed:
                    if let detectedQuestions = markerBlock.asDetectedQuestions {
                        QuestionStepperSheet(
                            questions: detectedQuestions,
                            onComplete: { answers in
                                session.questionSeriesDismissed = true
                                let response = answers.enumerated().map { i, answer in
                                    "\(i + 1). \(answer)"
                                }.joined(separator: "\n")
                                state.sendMessage(response)
                            },
                            onDismiss: {
                                session.questionSeriesDismissed = true
                            }
                        )
                        .frame(maxWidth: 752)
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        inputArea
                    }
                default:
                    // .confirm is handled inline, dismissed markers fall through
                    inputArea
                }
            } else if let session,
               !session.optionsDismissed,
               let lastMsg = session.messages.last,
               lastMsg.role == .assistant,
               !lastMsg.content.isEmpty,
               let options = session.detectOptions(in: lastMsg.content),
               !options.isEmpty {
                // Regex fallback — option detection
                let question = session.detectQuestion(in: lastMsg.content)
                let specReady = state.looksLikeSpec(lastMsg.content)
                OptionButtonsSheet(
                    contextText: question?.contextText ?? "",
                    options: options,
                    showApproveAndBuild: specReady,
                    onSelect: { option in
                        session.optionsDismissed = true
                        state.sendMessage("\(option.label). \(option.text)")
                    },
                    onDismiss: {
                        session.optionsDismissed = true
                    },
                    onCustomResponse: { text in
                        session.optionsDismissed = true
                        state.sendMessage(text)
                    },
                    onApproveAndBuild: {
                        session.optionsDismissed = true
                        handleApprove()
                    }
                )
                .frame(maxWidth: 752)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isSpecComplete {
                SpecCompleteSheet(
                    siblingTabs: siblingTabs,
                    onApproveAndBuild: {
                        dismissSpecSignal()
                        handleApprove()
                    },
                    onHandOff: { targetTabId in
                        dismissSpecSignal()
                        onHandOff?(targetTabId)
                    },
                    onCreateAndHandOff: { role in
                        dismissSpecSignal()
                        onCreateAndHandOff?(role)
                    },
                    onContinue: {
                        dismissSpecSignal()
                    }
                )
                .frame(maxWidth: 752)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let session,
                      !session.questionSeriesDismissed,
                      let lastMsg = session.messages.last,
                      lastMsg.role == .assistant,
                      !lastMsg.content.isEmpty,
                      let questions = session.detectQuestionSeries(in: lastMsg.content),
                      !questions.isEmpty {
                // Regex fallback — question series
                QuestionStepperSheet(
                    questions: questions,
                    onComplete: { answers in
                        session.questionSeriesDismissed = true
                        let response = answers.enumerated().map { i, answer in
                            "\(i + 1). \(answer)"
                        }.joined(separator: "\n")
                        state.sendMessage(response)
                    },
                    onDismiss: {
                        session.questionSeriesDismissed = true
                    }
                )
                .frame(maxWidth: 752)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                inputArea
            }
        }
        .background(Theme.Colors.appBackground)
        .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            cycleModel()
            return .handled
        }
        // DEBUG: Opt+B — force show SpecCompleteSheet
        .onKeyPress(characters: CharacterSet(charactersIn: "b"), phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            debugForceSpecComplete()
            return .handled
        }
        .onKeyPress(.escape) {
            guard isRunning else { return .ignored }
            state.cancel()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            // Cmd+Enter confirms regardless of focus
            guard press.modifiers.contains(.command) else { return .ignored }
            guard let session, !session.confirmDismissed, !isRunning,
                  let lastMsg = session.messages.last,
                  lastMsg.role == .assistant,
                  !lastMsg.content.isEmpty,
                  (session.parseInteractiveMarkers(in: lastMsg.content).contains(where: {
                      if case .confirm = $0 { return true }; return false
                  }) || session.detectConfirmation(in: lastMsg.content) != nil) else { return .ignored }
            withAnimation(.easeOut(duration: 0.15)) { confirmTriggered = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                confirmTriggered = false
                confirmedMessageIds.insert(lastMsg.id)
                session.confirmDismissed = true
                sendHiddenConfirmation()
            }
            return .handled
        }
        // Ctrl+V paste and focus now handled by ChatInputBar
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Show handed-off context banner
                    if !state.handedOffContext.isEmpty && (session == nil || session?.messages.isEmpty == true) {
                        ForEach(Array(state.handedOffContext.enumerated()), id: \.offset) { _, item in
                            HandOffBanner(roleName: item.role.displayName, content: item.content)
                        }
                        .padding(.top, 16)
                    }

                    if session == nil || (session?.messages.isEmpty == true && !isRunning && state.handedOffContext.isEmpty) {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }

                    if let session {
                        // Error banner
                        if case .error(let msg) = session.status {
                            errorBanner(msg)
                        }

                        ForEach(session.messages) { message in
                            PlanMessageBubble(
                                message: message,
                                isSpec: message.role == .assistant && state.looksLikeSpec(message.content),
                                isEditing: state.editingMessageId == message.id,
                                editableContent: Binding(
                                    get: { state.pendingSpec ?? message.content },
                                    set: { state.pendingSpec = $0 }
                                ),
                                onBuild: {
                                    state.pendingSpec = message.content
                                    print("[PlanChat] Build requested for spec (\(message.content.count) chars)")
                                },
                                onEdit: {
                                    state.editingMessageId = message.id
                                    state.pendingSpec = message.content
                                },
                                onDoneEditing: {
                                    state.editingMessageId = nil
                                }
                            )
                            .id(message.id)

                            // Inline confirm button — green "Accepted" persists for all confirmed messages
                            // Uses cached detection to avoid per-render regex parsing
                            if message.role == .assistant,
                               !message.content.isEmpty,
                               session.cachedHasConfirm(for: message),
                               (confirmedMessageIds.contains(message.id) ||
                                (!session.confirmDismissed &&
                                 !isRunning &&
                                 message.id == session.messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.id)) {
                                ConfirmButton(
                                    onConfirm: {
                                        confirmedMessageIds.insert(message.id)
                                        session.confirmDismissed = true
                                        sendHiddenConfirmation()
                                    },
                                    onDismiss: {
                                        session.confirmDismissed = true
                                    },
                                    externalTrigger: confirmedMessageIds.contains(message.id)
                                )
                                .padding(.top, 4)
                                .transition(.opacity)
                            }
                        }

                        // Streaming text bubble
                        if session.status == .streaming && !session.currentStreamingText.isEmpty {
                            streamingBubble(session.currentStreamingText)
                                .id("streaming")
                        }

                        // Activity feed — tool calls, thinking, rate limits
                        if session.status == .connecting ||
                           (session.status == .streaming && session.currentStreamingText.isEmpty) {
                            ActivityFeedView(
                                activityFeed: session.activityFeed,
                                isThinking: session.isThinking,
                                startDate: thinkingStartDate
                            )
                            .id("thinking")
                        }
                    }

                    // Spacer clears the gradient overlay + gives room to scroll past content
                    Color.clear.frame(height: 120).id("scroll-spacer")
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .onChange(of: session?.scrollGeneration) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: scrollToMessage) { _, newId in
                if let id = newId {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollToMessage = nil
                }
            }
            .onChange(of: session?.status) { _, newValue in
                if newValue == .connecting {
                    thinkingStartDate = Date()
                    session?.activityFeed = []
                    session?.isThinking = false
                } else if newValue == .idle || newValue == .done || newValue == nil {
                    thinkingStartDate = nil
                } else if case .error = newValue {
                    thinkingStartDate = nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Start planning")
                .font(Theme.label(16))
                .foregroundColor(Theme.Colors.textSecondary)
            Text("Describe what you want to build. The planner will research your codebase and create a spec.")
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

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
                session?.status = .idle
            }
            .font(Theme.caption(12))
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func streamingBubble(_ text: String) -> some View {
        MarkdownRenderer(text, isStreaming: true)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let id: AnyHashable? = {
            if session?.status == .connecting ||
               (session?.status == .streaming && session?.currentStreamingText.isEmpty == true) {
                return "thinking"
            } else if session?.status == .streaming {
                return "streaming"
            } else if let last = session?.messages.last {
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

    // MARK: - Input Area

    // hasInput, tokenFraction, tokenLabel, formatTokenCount moved to ChatInputBar

    private var inputArea: some View {
        ChatInputBar(
            inputText: $inputText,
            selectedModel: $state.selectedModel,
            session: session,
            isRunning: isRunning,
            onSend: { prompt in state.sendMessage(prompt) },
            onCancel: { state.cancel() },
            saveImage: { data in state.saveImage(data: data) },
            ghostText: ghostCompletion,
            onReturnKey: { press in
                guard showSlashPopover && !allCommands.isEmpty else { return .ignored }
                let idx = min(slashPopoverIndex, allCommands.count - 1)
                inputText = "/\(allCommands[idx]) "
                slashCommandSelected = true
                return .handled
            },
            onTabKey: { press in
                if press.modifiers.contains(.shift) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        planModeEnabled.toggle()
                    }
                    return .handled
                }
                guard showSlashPopover && !allCommands.isEmpty else { return .ignored }
                let idx = min(slashPopoverIndex, allCommands.count - 1)
                inputText = "/\(allCommands[idx]) "
                slashCommandSelected = true
                return .handled
            },
            aboveInput: {
                // Slash command popover — floats above input
                if showSlashPopover && !allCommands.isEmpty {
                    SlashCommandPopover(
                        commands: allCommands,
                        filter: "",
                        onSelect: { command in
                            inputText = "/\(command) "
                        },
                        onDismiss: {
                            inputText = ""
                        },
                        selectedIndex: $slashPopoverIndex
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Pipeline stage indicator
                if let pipeline = state.activePipeline {
                    PipelineStageBar(pipeline: pipeline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
            },
            topBarExtras: {
                // Fast Thinking toggle (only for models that support it)
                if state.selectedModel.supportsFastThinking {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            fastThinkingEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("Fast")
                                .font(Theme.label(11))
                        }
                        .foregroundColor(fastThinkingEnabled ? .white : Color(hex: 0x938d8d).opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(fastThinkingEnabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(fastThinkingEnabled ? Color.white.opacity(0.15) : Color.clear, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Toggle fast thinking (⌥T)")
                }

                // Plan Mode toggle
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        planModeEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("Plan")
                            .font(Theme.label(11))
                    }
                    .foregroundColor(planModeEnabled ? .white : Color(hex: 0x938d8d).opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(planModeEnabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(planModeEnabled ? Color.white.opacity(0.15) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Toggle plan mode (⇧⇥)")
            }
        )
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: inputText) { oldValue, newValue in
            if newValue.count < oldValue.count || !newValue.hasPrefix("/") {
                slashCommandSelected = false
            }
            let visible = newValue.hasPrefix("/") && !isRunning && !slashCommandSelected
            slashState.isVisible = visible
            slashState.commands = visible ? allCommands : []
            if oldValue.count != newValue.count {
                slashState.selectedIndex = 0
                slashPopoverIndex = 0
            }
        }
        .onChange(of: slashState.selectedIndex) { _, newValue in
            slashPopoverIndex = newValue
        }
    }

    private func installKeyMonitor() {
        let ss = slashState
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Shift+Tab toggles plan mode (keyCode 48 = Tab)
            if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.planModeEnabled.toggle()
                    }
                }
                return nil
            }

            // Opt+T toggles fast thinking
            if event.keyCode == 17 && event.modifierFlags.contains(.option) && state.selectedModel.supportsFastThinking {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.fastThinkingEnabled.toggle()
                    }
                }
                return nil
            }

            guard ss.isVisible else { return event }

            switch Int(event.keyCode) {
            case 126: // up arrow
                DispatchQueue.main.async { ss.moveUp() }
                return nil
            case 125: // down arrow
                DispatchQueue.main.async { ss.moveDown() }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Debug

    /// Force-trigger SpecCompleteSheet for testing without running an agent.
    private func debugForceSpecComplete() {
        print("[DEBUG] debugForceSpecComplete called, session: \(session != nil)")
        let session = state.ensureSession()
        let fakeSpec = """
        # Spec: Notification Center & Activity Feed

        A persistent notification center that aggregates activity across all tasks, agents, and build runs. Users can triage, dismiss, and jump to source from a unified inbox view.

        ## 1. Data Model

        Define the core notification types and storage layer used throughout the feature.

        - [ ] Create `NotificationEntry` struct with id, kind, taskId, timestamp, title, body, isRead, sourceURL
        - [ ] Add `NotificationKind` enum: `.agentMessage`, `.buildComplete`, `.buildFailed`, `.specApproved`, `.mention`, `.system`
        - [ ] Add `NotificationStore` class (`@Observable`) with ordered array and persistence via JSON
        - [ ] Write `NotificationStore.add(_:)`, `markRead(_:)`, `markAllRead()`, `delete(_:)`, `clearAll()`
        - [ ] Wire `NotificationStore` into `WorkspaceState` as `notifications`
        - [ ] Add `unreadCount: Int` computed property to `WorkspaceState`

        ## 2. Notification Generation

        Emit notifications from the right sources so the feed populates automatically during normal usage.

        - [ ] Emit `.buildComplete` from `BuilderSession` when `buildState` transitions to `.done`
        - [ ] Emit `.buildFailed` from `BuilderSession` when `buildState` transitions to `.failed`, include failed step title in body
        - [ ] Emit `.agentMessage` from `AgentSession` when a new assistant message arrives and the task is not active
        - [ ] Emit `.specApproved` from `PlanChatState` when spec signal fires
        - [ ] Emit `.system` on app launch if last build was incomplete (crash recovery)
        - [ ] Throttle `.agentMessage` emissions to at most 1 per 3 seconds per task to prevent spam

        ## 3. Notification Center Panel

        The primary UI: a slide-in panel anchored to the toolbar bell icon.

        - [ ] Add `NotificationCenterView` SwiftUI view with `@Environment` dismiss support
        - [ ] Render grouped sections by date: Today, Yesterday, Earlier
        - [ ] Each row: icon (colored by kind), title (semibold 13px), body (muted 12px, 2 lines), relative timestamp (9px muted)
        - [ ] Unread rows: left 2px accent border, slightly lighter background
        - [ ] Swipe-to-delete row action (macOS: right-click → Delete)
        - [ ] Tap row → mark read, jump to source (select task, open correct tab)
        - [ ] "Mark all read" button in header when unread count > 0
        - [ ] Empty state: centered icon + "No notifications" label

        ## 4. Toolbar Integration

        Surface unread count and open the panel from the main window toolbar.

        - [ ] Add bell icon button to `WorkspaceToolbar` right cluster
        - [ ] Show red badge with unread count when > 0; hide badge when 0
        - [ ] Badge caps at "99+" for large counts
        - [ ] Button opens `NotificationCenterView` as a popover anchored to bell
        - [ ] Popover auto-dismisses on outside click
        - [ ] Keyboard shortcut: `⌘⇧N` to toggle panel

        ## 5. Persistence & State Restoration

        Notifications should survive app restarts and be cleared gracefully.

        - [ ] Persist `NotificationStore` to `~/Library/Application Support/BudahADE/notifications.json`
        - [ ] Load on app launch before first render to avoid badge flash
        - [ ] Cap stored notifications at 500; prune oldest read entries when over limit
        - [ ] Clear all notifications when a task is deleted
        - [ ] Export `unreadCount` to UserDefaults so Dock badge can reflect it (future)

        ## 6. Tests

        Verify core logic without UI dependencies.

        - [ ] Test `NotificationStore.add` deduplicates by id
        - [ ] Test `markAllRead` sets isRead on all entries
        - [ ] Test `clearAll` empties the store
        - [ ] Test unread count updates reactively after `markRead`
        - [ ] Test throttle: rapid `.agentMessage` emissions produce at most 1 entry per 3s window

        Specification is complete and ready for implementation.
        """
        session.messages.append(ChatMessage(role: .assistant, content: fakeSpec))
        session.status = .done
        print("[DEBUG] Injected fake spec. specReadySignalId: \(state.specReadySignalId ?? "nil")")
    }

    // MARK: - Actions

    /// Dismiss the current spec-ready signal.
    private func dismissSpecSignal() {
        if let id = state.specReadySignalId {
            state.dismissedSpecSignals.insert(id)
        }
    }

    private func sendHiddenConfirmation() {
        let session = state.ensureSession()
        state.chatManager.send(sessionId: session.id, prompt: "Yes, looks good. Proceed.", showInChat: false)
        state.persistConversation()
    }

    // canSend moved to ChatInputBar

    private func handleApprove() {
        // Prefer spec content from a file the agent wrote (root-level *-spec.md etc.)
        // over the assistant's last message, which is often just a summary.
        let specContent: String
        let existingSpecFiles = SpecParser.findSpecFiles(in: state.worktreePath)
            .filter { !$0.contains(".budahade/spec.md") } // skip our own output path
        if let agentSpecPath = existingSpecFiles.first,
           let fileContent = try? String(contentsOfFile: agentSpecPath, encoding: .utf8),
           !fileContent.isEmpty {
            specContent = fileContent
        } else if let lastAssistant = session?.messages.last(where: { $0.role == .assistant }),
                  !lastAssistant.content.isEmpty {
            specContent = lastAssistant.content
        } else {
            return
        }

        print("[Approve] Writing spec to \(state.worktreePath)")
        let _ = SpecVersionManager.approve(content: specContent, in: state.worktreePath)

        // Count spec items from the approved content
        let itemCount = specContent.components(separatedBy: "\n")
            .filter { $0.contains("- [ ]") || $0.contains("- [x]") || $0.contains("- [X]") }
            .count

        print("[Approve] Spec written — \(itemCount) items, calling onApproveToBuild")

        // Inline confirmation in chat
        state.sendMessage("→ spec.md written — \(itemCount) items")

        // Trigger Plan → Build transition
        onApproveToBuild?(itemCount)
        print("[Approve] onApproveToBuild returned")
    }

    private func handleEdit() {
        state.sendMessage("[Edit requested] What would you like to change?")
    }

    private func cycleModel() {
        let all = AgentModel.allCases
        guard let idx = all.firstIndex(of: state.selectedModel) else { return }
        state.selectedModel = all[(idx + 1) % all.count]
    }

    // sendMessage, pasteImageFromClipboard, handleDrop moved to ChatInputBar
}

// MARK: - Plan Message Bubble

struct PlanMessageBubble: View {
    let message: ChatMessage
    let isSpec: Bool
    let isEditing: Bool
    @Binding var editableContent: String
    let onBuild: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDoneEditing: (() -> Void)?

    init(
        message: ChatMessage,
        isSpec: Bool = false,
        isEditing: Bool = false,
        editableContent: Binding<String> = .constant(""),
        onBuild: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onDoneEditing: (() -> Void)? = nil
    ) {
        self.message = message
        self.isSpec = isSpec
        self.isEditing = isEditing
        self._editableContent = editableContent
        self.onBuild = onBuild
        self.onEdit = onEdit
        self.onDoneEditing = onDoneEditing
    }

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            VStack(alignment: .leading, spacing: 0) {
                if isEditing {
                    EditableMarkdownRenderer(content: $editableContent) {
                        onDoneEditing?()
                    }
                } else {
                    assistantBubble
                }
            }
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 80)
            Text(message.content)
                .font(Theme.body(14))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0x30221f))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tool calls — compact
            if let tools = message.toolCalls, !tools.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(.bottom, 2)
            }

            if !message.content.isEmpty {
                MarkdownRenderer(message.content)
            }
        }
    }

    private var specActionButtons: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                onEdit?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                    Text("Edit")
                        .font(Theme.label(12))
                }
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.Colors.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                onBuild?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 11))
                    Text("Build")
                        .font(Theme.label(12))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var systemBubble: some View {
        Text(message.content)
            .font(Theme.caption(12))
            .foregroundColor(Theme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundColor(Theme.Colors.borderSubtle)
            )
    }
}


// MARK: - Option Buttons Sheet

struct OptionButtonsSheet: View {
    let contextText: String
    let options: [AgentSession.DetectedOption]
    var showApproveAndBuild: Bool = false
    let onSelect: (AgentSession.DetectedOption) -> Void
    let onDismiss: () -> Void
    let onCustomResponse: (String) -> Void
    var onApproveAndBuild: (() -> Void)? = nil

    @State private var customText: String = ""
    @State private var focusedIndex: Int? = nil
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFieldFocused: Bool

    /// Auto-detect: if any option has a description, use detailed layout
    private var isDetailed: Bool {
        options.contains { !$0.description.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent top border
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.4))
                .frame(height: 1.5)

            VStack(alignment: .leading, spacing: 6) {
                // Header: question + dismiss
                sheetHeader

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
                    .padding(.bottom, 2)

                // Option rows — compact or detailed
                if isDetailed {
                    detailedOptions
                } else {
                    compactOptions
                }

                // Approve & Build button — shown when spec looks complete
                if showApproveAndBuild {
                    Button {
                        onApproveAndBuild?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Approve & Build")
                                .font(Theme.label(13))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.Colors.statusWorking)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }

                // Custom text field
                customTextField
                    .padding(.top, 4)

                // Keyboard hints footer
                keyboardFooter
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Theme.Colors.sidebarBackground)
        .focusable()
        .focused($sheetFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sheetFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            guard !customFieldFocused else { return .ignored }
            moveFocus(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !customFieldFocused else { return .ignored }
            moveFocus(delta: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !customFieldFocused else { return .ignored }
            if let idx = focusedIndex, idx < options.count {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(options[idx]) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard !customFieldFocused else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= options.count else { return .ignored }
            if let option = options.first(where: { $0.label == String(num) }) {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(option) }
                return .handled
            }
            let idx = num - 1
            if idx < options.count {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(options[idx]) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet.letters, phases: .down) { press in
            guard !customFieldFocused else { return .ignored }
            let char = String(press.characters).uppercased()
            if let option = options.first(where: { $0.label.uppercased() == char }) {
                withAnimation(.easeOut(duration: 0.15)) { onSelect(option) }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab) {
            if !customFieldFocused {
                customFieldFocused = true
                focusedIndex = nil
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if customFieldFocused {
                customFieldFocused = false
                sheetFocused = true
                return .handled
            }
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            Text(cleanContext(contextText))
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Colors.hoverFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Compact Options

    private var compactOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                CompactOptionRow(
                    option: option,
                    isFocused: focusedIndex == idx,
                    onSelect: { onSelect(option) },
                    onHover: { hovering in
                        if hovering { focusedIndex = idx }
                    }
                )
                if idx < options.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        .padding(.horizontal, 10)
                }
            }
        }
    }

    // MARK: - Detailed Options

    private var detailedOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, option in
                DetailedOptionCard(
                    option: option,
                    isFocused: focusedIndex == idx,
                    onSelect: { onSelect(option) },
                    onHover: { hovering in
                        if hovering { focusedIndex = idx }
                    }
                )
                if idx < options.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Custom Text Field

    private var customTextField: some View {
        HStack(spacing: 8) {
            Text("\u{270E}")  // pencil icon
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 22, height: 22)

            TextField(options.isEmpty ? "Type your answer..." : "Something else...", text: $customText)
                .font(Theme.body(13))
                .foregroundColor(Theme.Colors.textPrimary)
                .textFieldStyle(.plain)
                .focused($customFieldFocused)
                .onSubmit {
                    let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCustomResponse(trimmed)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Keyboard Footer

    private var keyboardFooter: some View {
        HStack {
            Text("↑↓ navigate")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Enter select")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Esc skip")
                .font(Theme.label(11))
                .foregroundColor(Theme.Colors.textTertiary)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Text("Skip")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.hoverFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Focus Navigation

    private func moveFocus(delta: Int) {
        guard !options.isEmpty else { return }
        if let current = focusedIndex {
            focusedIndex = (current + delta + options.count) % options.count
        } else {
            focusedIndex = delta > 0 ? 0 : options.count - 1
        }
    }

    // MARK: - Helpers

    private func cleanContext(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .components(separatedBy: "\n")
            .map { line in
                var l = line
                if l.hasPrefix("• ") { l = String(l.dropFirst(2)) }
                if l.hasPrefix("- ") { l = String(l.dropFirst(2)) }
                return l
            }
            .joined(separator: "\n")
    }
}

private struct CompactOptionRow: View {
    let option: AgentSession.DetectedOption
    let isFocused: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            HStack(spacing: 10) {
                // Badge
                Text(option.label)
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHighlighted
                                  ? Color(hex: 0xc4785c).opacity(0.15)
                                  : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isHighlighted
                                          ? Color(hex: 0xc4785c).opacity(0.3)
                                          : Color.white.opacity(0.1),
                                          lineWidth: 1)
                    )

                // Option text
                Text(option.text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Arrow indicator
                Text("→")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.accent)
                    .opacity(isHighlighted ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(isFocused ? 0.06 : 0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

private struct DetailedOptionCard: View {
    let option: AgentSession.DetectedOption
    let isFocused: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isFocused || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { onSelect() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Header: badge + title + arrow
                HStack(spacing: 10) {
                    Text(option.label)
                        .font(Theme.label(11))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isHighlighted
                                      ? Color(hex: 0xc4785c).opacity(0.15)
                                      : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(isHighlighted
                                              ? Color(hex: 0xc4785c).opacity(0.3)
                                              : Color.white.opacity(0.1),
                                              lineWidth: 1)
                        )

                    Text(option.text)
                        .font(Theme.label(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Text("→")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.accent)
                        .opacity(isHighlighted ? 1 : 0)
                }
                .padding(.bottom, 6)

                // Description + Pros/Cons
                if !option.description.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(parsedDescription.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .plain(let text):
                                Text(text)
                                    .font(Theme.body(12))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .lineLimit(3)
                            case .pros(let text):
                                (Text("Pros: ").font(Theme.label(11)).foregroundColor(Theme.Colors.statusDone)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            case .cons(let text):
                                (Text("Cons: ").font(Theme.label(11)).foregroundColor(Theme.Colors.error)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            }
                        }
                    }
                    .padding(.leading, 32) // past badge width
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(isFocused ? 0.04 : 0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }

    // MARK: - Description Parsing

    private enum DescriptionLine {
        case plain(String)
        case pros(String)
        case cons(String)
    }

    private var parsedDescription: [DescriptionLine] {
        option.description.components(separatedBy: "\n").compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { return nil }
            if l.lowercased().hasPrefix("pros:") {
                return .pros(String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if l.lowercased().hasPrefix("cons:") {
                return .cons(String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else {
                return .plain(l)
            }
        }
    }
}

// MARK: - Inline Bold Text

/// Parses **bold** markers in a string and renders them as bold Text segments
private struct InlineBoldText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        parsedText
    }

    private var parsedText: Text {
        var result = Text("")
        var remaining = source[source.startIndex..<source.endIndex]

        while let boldStart = remaining.range(of: "**") {
            // Text before the bold marker
            let before = remaining[remaining.startIndex..<boldStart.lowerBound]
            if !before.isEmpty {
                result = result + Text(before)
            }

            // Find closing **
            let afterOpen = boldStart.upperBound
            guard afterOpen < remaining.endIndex,
                  let boldEnd = remaining[afterOpen...].range(of: "**") else {
                // No closing marker — render the rest as plain text
                result = result + Text(remaining[boldStart.lowerBound...])
                return result
            }

            let boldContent = remaining[afterOpen..<boldEnd.lowerBound]
            result = result + Text(boldContent).bold()
            remaining = remaining[boldEnd.upperBound...]
        }

        // Remaining text after last bold
        if !remaining.isEmpty {
            result = result + Text(remaining)
        }

        return result
    }
}

// MARK: - Question Stepper Sheet

struct QuestionStepperSheet: View {
    let questions: [AgentSession.DetectedQuestionItem]
    let onComplete: ([String]) -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var answers: [String]
    @State private var customText = ""
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFocused: Bool

    init(questions: [AgentSession.DetectedQuestionItem], onComplete: @escaping ([String]) -> Void, onDismiss: @escaping () -> Void) {
        self.questions = questions
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self._answers = State(initialValue: Array(repeating: "", count: questions.count))
    }

    private var current: AgentSession.DetectedQuestionItem { questions[currentIndex] }
    private var isLast: Bool { currentIndex == questions.count - 1 }
    private var canAdvance: Bool { !answers[currentIndex].isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: step counter + dismiss
                HStack {
                    Text("Question \(currentIndex + 1) of \(questions.count)")
                        .font(Theme.label(12))
                        .foregroundColor(Theme.Colors.textTertiary)

                    // Step dots
                    HStack(spacing: 4) {
                        ForEach(0..<questions.count, id: \.self) { i in
                            Circle()
                                .fill(i < currentIndex ? Color(hex: 0x34a853) :
                                      i == currentIndex ? Theme.Colors.accent :
                                      Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 4)

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Theme.Colors.hoverFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

                // Question text
                Text(cleanBold(current.question))
                    .font(Theme.body(14))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Context (if any)
                if !current.context.isEmpty {
                    Text(current.context)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(3)
                }

                // Suggestion buttons
                if !current.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(current.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            SuggestionRow(
                                number: idx + 1,
                                text: suggestion,
                                isSelected: answers[currentIndex] == suggestion,
                                onSelect: {
                                    answers[currentIndex] = suggestion
                                    customText = ""
                                }
                            )
                            if idx < current.suggestions.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.5)
                                    .padding(.horizontal, 10)
                            }
                        }
                    }
                }

                // Custom text field
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 20)

                    TextField("Something else...", text: $customText)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($customFocused)
                        .onChange(of: customText) { _, newValue in
                            if !newValue.isEmpty {
                                answers[currentIndex] = newValue
                            }
                        }
                        .onSubmit {
                            if canAdvance { advance() }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

                // Navigation + keyboard hints
                HStack {
                    if !current.suggestions.isEmpty {
                        Text("1–\(current.suggestions.count) select")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                        + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
                        + Text("Enter next")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                HStack {
                    if currentIndex > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                customText = ""
                                currentIndex -= 1
                                loadCustomText()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9))
                                Text("Back")
                                    .font(Theme.body(12))
                            }
                            .foregroundColor(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        advance()
                    } label: {
                        HStack(spacing: 4) {
                            Text(isLast ? "Submit" : "Next")
                                .font(Theme.label(12))
                                .foregroundColor(canAdvance ? .black : .black.opacity(0.4))
                            if !isLast {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(canAdvance ? .black : .black.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canAdvance ? Color(white: 0.92) : Color(white: 0.92).opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdvance)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Theme.Colors.sidebarBackground)
        .focusable()
        .focused($sheetFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sheetFocused = true
            }
        }
        .onKeyPress(.return) {
            guard !customFocused, canAdvance else { return .ignored }
            advance()
            return .handled
        }
        .onKeyPress(.escape) {
            withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: .down) { press in
            guard !customFocused else { return .ignored }
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1, num <= current.suggestions.count else { return .ignored }
            withAnimation(.easeOut(duration: 0.1)) {
                answers[currentIndex] = current.suggestions[num - 1]
                customText = ""
            }
            return .handled
        }
    }

    private func advance() {
        if isLast {
            withAnimation(.easeOut(duration: 0.15)) { onComplete(answers) }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                customText = ""
                currentIndex += 1
                loadCustomText()
            }
        }
    }

    private func loadCustomText() {
        let answer = answers[currentIndex]
        if !answer.isEmpty && !current.suggestions.contains(answer) {
            customText = answer
        } else {
            customText = ""
        }
    }

    private func cleanBold(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
    }
}

private struct SuggestionRow: View {
    let number: Int
    let text: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false
    private var isHighlighted: Bool { isSelected || isHovered }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.1)) { onSelect() }
        } label: {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(Theme.label(11))
                    .foregroundColor(isSelected ? .white : Theme.Colors.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected
                                  ? Theme.Colors.accent
                                  : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.15) : Color.white.opacity(0.06)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isSelected
                                          ? Theme.Colors.accent
                                          : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.3) : Color.white.opacity(0.1)),
                                          lineWidth: 1)
                    )

                Text(text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Confirm Button

struct ConfirmButton: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    var externalTrigger: Bool = false

    @State private var isHovered = false
    @State private var accepted = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { accepted = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    onConfirm()
                }
            } label: {
                HStack(spacing: 5) {
                    if accepted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Accepted")
                            .font(Theme.label(12))
                            .foregroundColor(.white)
                    } else {
                        Text("Confirm")
                            .font(Theme.label(12))
                            .foregroundColor(.black)
                        Text("\u{2318}\u{21A9}")
                            .font(Theme.caption(10))
                            .foregroundColor(.black.opacity(0.45))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accepted
                              ? Color(hex: 0x34a853)
                              : (isHovered ? Color.white : Color(white: 0.92)))
                )
            }
            .buttonStyle(.plain)
            .disabled(accepted)
            .onHover { isHovered = $0 }

            if !accepted {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                } label: {
                    Text("Skip")
                        .font(Theme.body(12))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .onChange(of: externalTrigger) { _, triggered in
            if triggered && !accepted {
                withAnimation(.easeOut(duration: 0.2)) { accepted = true }
            }
        }
    }
}

// PlanModelSelectorMenu moved to Shared/ChatInputBar.swift as ModelSelectorMenu

// MARK: - Pipeline Stage Bar

private struct PipelineStageBar: View {
    @ObservedObject var pipeline: MultiModelPipeline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pipeline.stageResults.enumerated()), id: \.element.id) { index, result in
                stageIndicator(index: index, result: result)
                if index < pipeline.stageResults.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: 0x938d8d).opacity(0.4))
                        .padding(.horizontal, 4)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func stageIndicator(index: Int, result: PipelineStageResult) -> some View {
        let isActive = pipeline.currentStageIndex == index && !result.status.isTerminal
        HStack(spacing: 4) {
            Circle()
                .fill(stageColor(for: result.status, active: isActive))
                .frame(width: 6, height: 6)
            Text("\(result.stageName) (\(result.model.displayName))")
                .font(Theme.caption(10))
                .foregroundColor(isActive ? .white : Color(hex: 0x938d8d))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                : nil
        )
    }

    private func stageColor(for status: PipelineStageStatus, active: Bool) -> Color {
        switch status {
        case .pending:
            return Color(hex: 0x938d8d).opacity(0.3)
        case .running:
            return Theme.Colors.accent
        case .completed:
            return Color(hex: 0x7ab5a0)
        case .failed:
            return .red
        }
    }
}

// MARK: - Slash Popover State (class for NSEvent monitor capture)

final class SlashPopoverState: ObservableObject {
    @Published var isVisible = false
    @Published var commands: [String] = []
    @Published var selectedIndex: Int = 0

    func moveUp() {
        guard !commands.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + commands.count) % commands.count
    }

    func moveDown() {
        guard !commands.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % commands.count
    }

    var selectedCommand: String? {
        guard !commands.isEmpty, selectedIndex < commands.count else { return nil }
        return commands[selectedIndex]
    }
}

// MARK: - Spec Complete Sheet

/// Modal shown when the agent indicates the spec is complete.
/// Three actions: Approve & Build, Hand off, Continue.
private struct SpecCompleteSheet: View {
    let siblingTabs: [PlanTabInfo]
    let onApproveAndBuild: () -> Void
    var onHandOff: ((UUID) -> Void)? = nil
    /// Called when user picks "Hand off" but no sibling tabs exist — creates a new tab with the chosen role.
    var onCreateAndHandOff: ((AgentMode) -> Void)? = nil
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("Spec Complete")
                    .font(.custom("Geist-SemiBold", size: 13))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button { onContinue() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            // Action row
            HStack(spacing: 16) {
                // Continue Iterating — secondary
                Button(action: onContinue) {
                    Text("Continue Iterating")
                        .font(.custom("Geist-Medium", size: 12))
                        .foregroundColor(Color(hex: 0x888888))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(hex: 0x1e1e1e))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                // Hand off — dropdown
                Menu {
                    if siblingTabs.isEmpty {
                        Section("Create new agent") {
                            ForEach(AgentMode.allCases) { mode in
                                Button {
                                    onCreateAndHandOff?(mode)
                                } label: {
                                    Label(mode.displayName, systemImage: mode.iconName)
                                }
                            }
                        }
                    } else {
                        ForEach(siblingTabs) { tab in
                            Button {
                                onHandOff?(tab.id)
                            } label: {
                                Label(tab.title, systemImage: tab.role.iconName)
                            }
                        }
                        Divider()
                        Section("New agent") {
                            ForEach(AgentMode.allCases) { mode in
                                Button {
                                    onCreateAndHandOff?(mode)
                                } label: {
                                    Label(mode.displayName, systemImage: mode.iconName)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text("Hand-Off")
                            .font(.custom("Geist-Medium", size: 12))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(Color(hex: 0x888888))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: 0x1e1e1e))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }

                Spacer()

                // Start Build — primary (white bg, dark text)
                Button(action: onApproveAndBuild) {
                    HStack(spacing: 6) {
                        Text("Start Build")
                            .font(.custom("Geist-SemiBold", size: 9))
                            .foregroundColor(Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.8))
                        Text("⌘↵")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.8))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 30)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 601)
        .background(Color(hex: 0x1c1f25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onKeyPress(.escape) {
            onContinue()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onApproveAndBuild()
            return .handled
        }
    }
}

// ContextMemoryOverlay moved to Shared/ChatInputBar.swift

// MARK: - Hand-Off Banner

private struct HandOffBanner: View {
    let roleName: String
    let content: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.accent)
                Text("Handed off from \(roleName)")
                    .font(Theme.label(12))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(content.prefix(500) + (content.count > 500 ? "..." : ""))
                    .font(Theme.body(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(nil)
            } else {
                Text(content.prefix(120) + (content.count > 120 ? "..." : ""))
                    .font(Theme.body(12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
    }
}
