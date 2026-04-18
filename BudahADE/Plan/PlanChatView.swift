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
    /// Unified prompt queue — all interactive block types (choice, confirm, questions)
    /// funnel here as structured `QueuedPrompt`s. New prompts append without disrupting
    /// the current card — the `PromptDispatcher` chooses the right renderer (confirm,
    /// choice, question, or stepper) based on queue shape.
    @State private var promptQueue: [AgentSession.QueuedPrompt] = []
    @State private var promptQueueSeenIds: Set<String> = []
    @State private var slashCommandSelected = false
    @State private var scrollToMessage: UUID?
    @State private var fastThinkingEnabled = false
    @State private var planModeEnabled = false
    @State private var cachedAllCommands: [String] = []
    @State private var cachedHasAssistantMessage: Bool = false

    /// Active slash command context — finds the last `/` token in the input
    /// that is at start of text or preceded by whitespace, and hasn't been completed yet.
    private var activeSlashContext: (filter: String, range: Range<String.Index>)? {
        guard !isRunning, !slashCommandSelected else { return nil }
        let text = inputText

        // Find the last `/` that is at start or preceded by whitespace
        guard let slashIndex = text.lastIndex(of: "/") else { return nil }
        if slashIndex != text.startIndex {
            let before = text.index(before: slashIndex)
            guard text[before].isWhitespace || text[before] == "\n" else { return nil }
        }

        let afterSlash = text.index(after: slashIndex)
        guard afterSlash <= text.endIndex else { return nil }
        let querySubstring = text[afterSlash...]
        // If there's a space, the command token is complete — no popover
        if querySubstring.contains(" ") { return nil }

        let filter = String(querySubstring)
        return (filter: filter, range: slashIndex..<text.endIndex)
    }

    /// Whether the slash command popover should be visible
    private var showSlashPopover: Bool {
        activeSlashContext != nil
    }

    /// The filter text after the "/"
    private var slashFilter: String {
        activeSlashContext?.filter ?? ""
    }

    /// Default commands to show before CLI init event provides the real list
    private static let defaultRemoteCommands = [
        "update-config", "simplify", "loop", "schedule",
        "claude-api", "site-extract", "prepare-to-build",
        "handoff", "prd-to-plan", "find-skills",
        "figma-design-system", "qa", "design-apply",
        "design-an-interface", "grill-me",
        "design-extract", "kill-mcp", "notion-update", "figma-connect",
        "keybindings-help",
        "claude-hud:setup", "claude-hud:configure",
        "compact", "context", "cost", "heapdump", "init",
        "pr-comments", "release-notes", "review", "security-review",
        "extra-usage", "insights",
    ]

    /// Ghost text completion — shows the full input with slash command completed
    private var ghostCompletion: String? {
        guard let ctx = activeSlashContext, !allCommands.isEmpty else { return nil }
        let idx = min(slashPopoverIndex, allCommands.count - 1)
        let command = allCommands[idx]
        // Replace the slash token range with the full command
        var ghost = inputText
        ghost.replaceSubrange(ctx.range, with: "/\(command)")
        return ghost
    }

    /// Range of the selected slash command in inputText (e.g. "/grill-me" anywhere in text).
    /// Returns nil when no skill is selected.
    private var skillHighlightRange: (start: Int, length: Int)? {
        guard slashCommandSelected else { return nil }
        // Find the last "/" preceded by start-of-string or whitespace
        let text = inputText
        var searchFrom = text.endIndex
        while searchFrom > text.startIndex {
            guard let slashIdx = text[text.startIndex..<searchFrom].lastIndex(of: "/") else { return nil }
            // Validate: must be at start or preceded by whitespace
            if slashIdx == text.startIndex || text[text.index(before: slashIdx)].isWhitespace {
                let start = text.distance(from: text.startIndex, to: slashIdx)
                let afterSlash = text[text.index(after: slashIdx)...]
                // Find end of command token (next space or end of string)
                if let spaceIdx = afterSlash.firstIndex(of: " ") {
                    let length = text.distance(from: slashIdx, to: spaceIdx)
                    return (start: start, length: length)
                }
                return (start: start, length: text.count - start)
            }
            searchFrom = slashIdx
        }
        return nil
    }

    /// All available commands filtered by current slash input (reads from cache)
    private var allCommands: [String] {
        if slashFilter.isEmpty { return cachedAllCommands }
        return cachedAllCommands.filter { $0.localizedCaseInsensitiveContains(slashFilter) }
    }

    private func rebuildCommandCache() {
        let local = ["clear", "model"]
        let remote = session?.availableCommands.isEmpty == false
            ? session!.availableCommands
            : Self.defaultRemoteCommands
        cachedAllCommands = local + remote
    }

    private var session: AgentSession? { state.plannerSession }
    private var isRunning: Bool {
        session?.status == .streaming || session?.status == .connecting
    }

    private var hasAssistantMessage: Bool { cachedHasAssistantMessage }

    private func rebuildHasAssistant() {
        cachedHasAssistantMessage = session?.messages.contains { $0.role == .assistant } == true
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

            // Unified prompt queue — ALL interactive block types funnel through one
            // `PromptDispatcher` that picks the right card by queue shape.
            if !promptQueue.isEmpty {
                PromptDispatcher(
                    queue: promptQueue,
                    onAnswerPrompt: handleAnswer(prompt:answer:),
                    onAnswerAll: handleAnswerAll(answers:),
                    onApproveAndBuild: {
                        promptQueue.removeAll()
                        handleApprove()
                    },
                    onDismiss: {
                        promptQueue.removeAll()
                        // Keep promptQueueSeenIds — dismissing doesn't mean "ask me again later"
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
            // Cmd+Enter: universal "accept the obvious next action" shortcut.
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !isRunning else { return .ignored }

            // If a prompt is active, pick the obvious answer per kind.
            if let first = promptQueue.first {
                if let answer = obviousAnswer(for: first) {
                    handleAnswer(prompt: first, answer: answer)
                    return .handled
                }
            }

            // Regex fallback — confirm detection on the last assistant message.
            if let session,
               !session.confirmDismissed,
               let lastMsg = session.messages.last,
               lastMsg.role == .assistant,
               !lastMsg.content.isEmpty,
               session.detectConfirmation(in: lastMsg.content) != nil {
                session.confirmDismissed = true
                sendHiddenConfirmation()
                return .handled
            }

            return .ignored
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
                            // Confirms, choices, and questions are now rendered by PromptDispatcher
                            // above the input area — not inline next to the message.
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
            onSend: { prompt, attachments in state.sendMessage(prompt, attachments: attachments) },
            onCancel: { state.cancel() },
            saveImage: { data in state.saveImage(data: data) },
            ghostText: ghostCompletion,
            workingDirectory: state.repoPath,
            skillHighlightRange: skillHighlightRange,
            onReturnKey: { press in
                guard let ctx = activeSlashContext, !allCommands.isEmpty else { return .ignored }
                let idx = min(slashPopoverIndex, allCommands.count - 1)
                inputText.replaceSubrange(ctx.range, with: "/\(allCommands[idx]) ")
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
                guard let ctx = activeSlashContext, !allCommands.isEmpty else { return .ignored }
                let idx = min(slashPopoverIndex, allCommands.count - 1)
                inputText.replaceSubrange(ctx.range, with: "/\(allCommands[idx]) ")
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
                            if let ctx = activeSlashContext {
                                inputText.replaceSubrange(ctx.range, with: "/\(command) ")
                            }
                        },
                        onDismiss: {
                            if let ctx = activeSlashContext {
                                inputText.replaceSubrange(ctx.range, with: "")
                            }
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
        .onAppear {
            installKeyMonitor()
            rebuildCommandCache()
            rebuildHasAssistant()
        }
        .onChange(of: session?.availableCommands) { rebuildCommandCache() }
        .onChange(of: session?.messages.count) { rebuildHasAssistant() }

        .onChange(of: session?.status) { oldStatus, newStatus in
            // When streaming completes, scan all assistant messages for unseen prompts.
            guard oldStatus == .streaming, newStatus != .streaming,
                  let session = session else { return }
            for msg in session.messages where msg.role == .assistant && !msg.content.isEmpty {
                ingestPrompts(from: msg.content, messageId: msg.id, session: session)
            }
        }
        // Mid-stream detection — the biggest UX win. When the agent writes a long
        // message that includes a question halfway through, ingest the prompt as
        // soon as its closing marker is received, rather than waiting for the
        // whole message to finish streaming.
        .onChange(of: session?.currentStreamingText) { _, text in
            guard let text, let session,
                  let streamingId = session.streamingMessageId,
                  !text.isEmpty else { return }
            // Only consider blocks whose closing marker has already streamed in —
            // everything after the final `<!-- /INTERACTIVE -->` is incomplete and
            // must be discarded to avoid partial-parse churn.
            guard let lastClose = text.range(of: "<!-- /INTERACTIVE -->", options: .backwards) else { return }
            let completeText = String(text[..<lastClose.upperBound])
            ingestPrompts(from: completeText, messageId: streamingId, session: session)
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: inputText) { oldValue, newValue in
            // Reset slash selection when the "/" prefix is deleted or text is cleared
            if slashCommandSelected {
                if !newValue.contains("/") || newValue.isEmpty {
                    slashCommandSelected = false
                }
            }
            let visible = showSlashPopover
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

    // MARK: - Persistent Prompt Queue

    /// Ingest any un-seen interactive prompts from a message's content into the queue.
    /// Shared by the streaming-complete scan and the mid-stream detection path.
    private func ingestPrompts(from text: String, messageId: UUID, session: AgentSession) {
        guard !session.isLastBlockSelfAnswered(in: text) else { return }

        let blocks = session.parseInteractiveMarkers(in: text)
        let contextPrefix = session.questionBeforeMarker(in: text)
        let specReady = state.looksLikeSpec(text)

        for (idx, block) in blocks.enumerated() {
            let prompt = block.asQueuedPrompt(
                messageId: messageId,
                blockIndex: idx,
                context: contextPrefix,
                isSpecReady: specReady
            )
            if !promptQueueSeenIds.contains(prompt.id) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    promptQueue.append(prompt)
                }
                promptQueueSeenIds.insert(prompt.id)
            }
        }

        // Regex fallback — question series without marker wrapping. Only fires
        // when the message has no marker-based blocks (blocks.isEmpty).
        if blocks.isEmpty, let qs = session.detectQuestionSeries(in: text), !qs.isEmpty {
            let prompt = AgentSession.queuedPromptFromRegexSeries(qs, messageId: messageId)
            if !promptQueueSeenIds.contains(prompt.id) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    promptQueue.append(prompt)
                }
                promptQueueSeenIds.insert(prompt.id)
            }
        }
    }

    /// Handle an answer to a specific prompt. Removes it from the queue and sends the
    /// reply. Keeping the seen-id in place prevents the next scan from re-adding it.
    private func handleAnswer(prompt: AgentSession.QueuedPrompt, answer: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            promptQueue.removeAll { $0.id == prompt.id }
        }
        state.sendMessage(answer)
    }

    /// Handle answers for a stepper over a multi-prompt queue. Drains everything and
    /// sends a numbered-list reply so the agent can thread its follow-up properly.
    private func handleAnswerAll(answers: [String]) {
        let response = answers.count == 1
            ? answers[0]
            : answers.enumerated().map { i, a in "\(i + 1). \(a)" }.joined(separator: "\n")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            promptQueue.removeAll()
        }
        state.sendMessage(response)
    }

    /// Determine the "obvious" answer for Cmd+Enter acceptance, per kind.
    /// Confirm → "Yes", Choice → recommended option (or first), Question → first suggestion.
    private func obviousAnswer(for prompt: AgentSession.QueuedPrompt) -> String? {
        switch prompt.kind {
        case .confirm:
            return "Yes"
        case .choice(let options, let recommendedIndex, _):
            guard !options.isEmpty else { return nil }
            let idx = recommendedIndex ?? 0
            let bounded = max(0, min(idx, options.count - 1))
            let option = options[bounded]
            return "\(option.id + 1). \(option.text)"
        case .question(let suggestions):
            return suggestions.first
        case .questionSeries:
            return nil // Stepper handles its own submission flow
        }
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

    @State private var isHovered = false
    @State private var copied = false

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
                .contextMenu { copyContextMenu }
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
            .overlay(alignment: .topTrailing) {
                if isHovered && !isEditing && !message.content.isEmpty {
                    copyButton
                        .padding(.top, -2)
                        .padding(.trailing, -2)
                        .transition(.opacity)
                }
            }
            .onHover { isHovered = $0 }
            .contextMenu { copyContextMenu }
        case .system:
            systemBubble
                .contextMenu { copyContextMenu }
        }
    }

    private func copyMessageContent() {
        let content = parsedContent.displayText.isEmpty ? message.content : parsedContent.displayText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private var copyButton: some View {
        Button {
            copyMessageContent()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                Text(copied ? "Copied" : "Copy")
                    .font(Theme.caption(10))
            }
            .foregroundColor(copied ? Theme.Colors.accent : Theme.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var copyContextMenu: some View {
        Button {
            copyMessageContent()
        } label: {
            Label("Copy Message", systemImage: "doc.on.doc")
        }
    }

    /// Parsed display content and document attachments from message content
    private var parsedContent: (displayText: String, attachments: [(path: String, lineCount: Int)]) {
        let content = message.content
        // Fast path: no documents embedded
        guard content.contains("<document path=") else {
            return (content, [])
        }

        var displayText = content
        var attachments: [(path: String, lineCount: Int)] = []

        // Extract <document path="...">...</document> blocks
        let pattern = #"\n?<document path="([^"]+)">\n([\s\S]*?)\n</document>"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

            for match in matches.reversed() {
                let pathRange = match.range(at: 1)
                let bodyRange = match.range(at: 2)
                let path = nsContent.substring(with: pathRange)
                let body = nsContent.substring(with: bodyRange)
                let lines = body.components(separatedBy: "\n").count
                attachments.insert((path: path, lineCount: lines), at: 0)

                // Remove from display text
                displayText = (displayText as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        return (displayText.trimmingCharacters(in: .whitespacesAndNewlines), attachments)
    }

    private var userBubble: some View {
        // Prefer message.attachments (new flow); fall back to regex parsing (legacy messages)
        let attachments: [(path: String, lineCount: Int)]
        let displayText: String
        if !message.attachments.isEmpty {
            attachments = message.attachments.map { ($0.path, $0.lineCount) }
            displayText = message.content
        } else {
            let parsed = parsedContent
            attachments = parsed.attachments
            displayText = parsed.displayText
        }

        return HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 6) {
                // Main message text
                if !displayText.isEmpty {
                    Text(displayText)
                        .font(Theme.body(14))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: 0x30221f))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Document attachment chips
                if !attachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                            DocumentAttachmentChip(path: attachment.path, lineCount: attachment.lineCount)
                        }
                    }
                }
            }
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

// MARK: - Document Attachment Chip

struct DocumentAttachmentChip: View {
    let path: String
    let lineCount: Int
    @State private var isExpanded = false

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                    Text(fileName)
                        .font(Theme.code(11))
                        .lineLimit(1)
                    Text("\(lineCount) lines")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .foregroundColor(Theme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: 0x30221f).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(path)
                    .font(Theme.code(10))
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
    }
}


// MARK: - Confirm Button

struct ConfirmButton: View {
    var questionText: String? = nil
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    var externalTrigger: Bool = false

    @State private var isHovered = false
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let q = questionText, !q.isEmpty {
                Text(q)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        } // close VStack
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
