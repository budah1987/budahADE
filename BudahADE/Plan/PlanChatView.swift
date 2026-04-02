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
    @State private var pendingImage: NSImage?
    @State private var pendingImagePath: String?
    @State private var showFilePicker = false
    @State private var showModelMenu: Bool = false
    @State private var inputTextHeight: CGFloat = 36
    @State private var thinkingStartDate: Date?
    @State private var slashPopoverIndex: Int = 0
    @State private var keyMonitor: Any?
    @StateObject private var slashState = SlashPopoverState()
    @FocusState private var inputFocused: Bool
    @State private var confirmTriggered = false
    @State private var confirmedMessageIds: Set<UUID> = []

    @State private var slashCommandSelected = false
    @State private var scrollToMessage: UUID?

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

    private struct InputHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

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

            // Messages + turn scrubber
            ZStack(alignment: .trailing) {
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

                if !state.turnMarkers.isEmpty {
                    ChatTurnScrubber(
                        markers: state.turnMarkers,
                        onMarkerTap: { messageId in
                            scrollToMessage = messageId
                        }
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 14)
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
                        .frame(maxWidth: 640)
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
                        .frame(maxWidth: 640)
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
                .frame(maxWidth: 640)
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
                .frame(maxWidth: 640)
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
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                inputArea
            }
        }
        .background(Theme.contentBg)
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
        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            if pasteImageFromClipboard() { return .handled }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            inputFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                inputFocused = true
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session == nil || (session?.messages.isEmpty == true && !isRunning) {
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
                            // Check markers first, then regex fallback
                            if message.role == .assistant,
                               !message.content.isEmpty,
                               (session.parseInteractiveMarkers(in: message.content).contains(where: {
                                   if case .confirm = $0 { return true }; return false
                               }) || session.detectConfirmation(in: message.content) != nil),
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
            .onChange(of: session?.messages.count) { _, _ in
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
            .onChange(of: session?.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session?.activityFeed.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session?.status) { _, newValue in
                if newValue == .connecting {
                    thinkingStartDate = Date()
                    session?.activityFeed = []
                    session?.isThinking = false
                } else if newValue == .idle || newValue == .done || newValue == nil {
                    thinkingStartDate = nil
                    // Scroll when response completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy: proxy)
                    }
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
                .foregroundColor(Theme.textMuted)
            Text("Start planning")
                .font(Theme.label(16))
                .foregroundColor(Theme.textSecondary)
            Text("Describe what you want to build. The planner will research your codebase and create a spec.")
                .font(Theme.body(13))
                .foregroundColor(Theme.textMuted)
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

    private var inputArea: some View {
        VStack(spacing: 0) {
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

            // Pending image preview
            if let img = pendingImage {
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        pendingImage = nil
                        pendingImagePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            // Pipeline stage indicator
            if let pipeline = state.activePipeline {
                PipelineStageBar(pipeline: pipeline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            // Model selector row
            HStack(spacing: 4) {
                if state.pipelineMode {
                    // Pipeline mode: show indicator instead of model picker
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.accent)
                        Text("pipeline")
                            .font(Theme.code(14))
                            .foregroundColor(Theme.accent)
                    }
                    .onTapGesture {
                        state.pipelineMode = false
                    }
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showModelMenu.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(state.selectedModel.displayName.lowercased())
                                .font(Theme.code(14))
                                .foregroundColor(Color(hex: 0x938d8d))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: 0x938d8d))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Pipeline toggle
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        state.pipelineMode.toggle()
                    }
                } label: {
                    Image(systemName: state.pipelineMode ? "arrow.triangle.branch" : "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundColor(state.pipelineMode ? Theme.accent : Color(hex: 0x938d8d).opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(state.pipelineMode ? "Pipeline mode ON" : "Pipeline mode OFF")

                // Token count
                if let pipeline = state.activePipeline, pipeline.totalTokens > 0 {
                    Text(pipeline.formattedTokenCount)
                        .font(Theme.caption(10))
                        .foregroundColor(Color(hex: 0x938d8d))
                } else if let session, session.totalTokens > 0 {
                    Text(session.formattedTokenCount)
                        .font(Theme.caption(10))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .overlay(alignment: .topLeading) {
                if showModelMenu {
                    PlanModelSelectorMenu(selectedModel: $state.selectedModel, isShowing: $showModelMenu)
                        .padding(.top, 30)
                        .padding(.leading, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                }
            }
            .zIndex(showModelMenu ? 100 : 0)

            // Text input
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("What do you want to build?")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    // Ghost text — shows autocomplete suggestion
                    if let ghost = ghostCompletion {
                        Text(ghost)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary.opacity(0.5))
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(height: min(max(inputTextHeight + 10, 36), 200))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($inputFocused)
                        .background(
                            Text(inputText.isEmpty ? "A" : inputText)
                                .font(.system(size: 14))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(0)
                                .background(GeometryReader { textGeo in
                                    Color.clear.preference(
                                        key: InputHeightKey.self,
                                        value: textGeo.size.height
                                    )
                                })
                        )
                        .onPreferenceChange(InputHeightKey.self) { h in
                            if h > 0 { inputTextHeight = h }
                        }
                        .onKeyPress(.return, phases: .down) { press in
                            guard !press.modifiers.contains(.shift) else { return .ignored }
                            // If slash popover is showing, select the command and dismiss
                            if showSlashPopover && !allCommands.isEmpty {
                                let idx = min(slashPopoverIndex, allCommands.count - 1)
                                inputText = "/\(allCommands[idx]) "
                                slashCommandSelected = true
                                return .handled
                            }
                            sendMessage()
                            return .handled
                        }
                        .onKeyPress(.tab, phases: .down) { _ in
                            // Tab auto-completes the selected command and dismisses
                            guard showSlashPopover && !allCommands.isEmpty else { return .ignored }
                            let idx = min(slashPopoverIndex, allCommands.count - 1)
                            inputText = "/\(allCommands[idx]) "
                            slashCommandSelected = true
                            return .handled
                        }
                        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
                            guard press.modifiers.contains(.command) else { return .ignored }
                            if pasteImageFromClipboard() { return .handled }
                            return .ignored
                        }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Action row
                HStack(spacing: 8) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x938d8d))
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")

                    Spacer()

                    if isRunning {
                        Button {
                            state.cancel()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(canSend ? Theme.accent : Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(Color(hex: 0x6e6e6e).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: 0x9b8989).opacity(0.45), lineWidth: 0.75)
            )
            .onTapGesture {
                if showModelMenu {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showModelMenu = false
                    }
                }
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Color.clear)
        .onDrop(of: ["public.image", "public.file-url"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.png, .jpeg, .tiff, .image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return }
            if let path = state.saveImage(data: data) {
                pendingImage = image
                pendingImagePath = path
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: inputText) { oldValue, newValue in
            // Reset selection flag if user edits the text (not just from our auto-fill)
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        # Spec: Debug Test

        ## Goals
        - Test the SpecCompleteSheet modal
        - Verify it renders correctly

        ## Implementation Checklist
        - Define the struct
        - Add methods

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

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImagePath != nil
    }

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

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        var prompt = trimmed

        if let imagePath = pendingImagePath {
            if prompt.isEmpty {
                prompt = "[Image: \(imagePath)]"
            } else {
                prompt += "\n[Image: \(imagePath)]"
            }
        }

        inputText = ""
        pendingImage = nil
        pendingImagePath = nil

        state.sendMessage(prompt)
    }

    @discardableResult
    private func pasteImageFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        guard let imageData = pb.data(forType: .png)
                ?? pb.data(forType: .tiff) else { return false }
        guard let image = NSImage(data: imageData) else { return false }
        let pngData: Data
        if let png = pb.data(forType: .png) {
            pngData = png
        } else if let tiffRep = NSBitmapImageRep(data: imageData),
                  let converted = tiffRep.representation(using: .png, properties: [:]) {
            pngData = converted
        } else {
            return false
        }
        if let path = state.saveImage(data: pngData) {
            pendingImage = image
            pendingImagePath = path
            return true
        }
        return false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        if let path = state.saveImage(data: data) {
                            pendingImage = image
                            pendingImagePath = path
                        }
                    }
                }
                return true
            }
        }
        return false
    }
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
                        .foregroundColor(Theme.textMuted)
                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
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
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
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
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var systemBubble: some View {
        Text(message.content)
            .font(Theme.caption(12))
            .foregroundColor(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundColor(Theme.borderSubtle)
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
                .fill(Theme.accent.opacity(0.4))
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
                        .background(Theme.builder)
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
        .background(Theme.sidebar)
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
                .foregroundColor(Theme.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Theme.hoverFill)
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
                .foregroundColor(Theme.textMuted)
                .frame(width: 22, height: 22)

            TextField(options.isEmpty ? "Type your answer..." : "Something else...", text: $customText)
                .font(Theme.body(13))
                .foregroundColor(Theme.textPrimary)
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
                .foregroundColor(Theme.textMuted)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Enter select")
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)
            + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
            + Text("Esc skip")
                .font(Theme.label(11))
                .foregroundColor(Theme.textMuted)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
            } label: {
                Text("Skip")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.hoverFill)
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
                    .foregroundColor(Theme.accent)
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
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Arrow indicator
                Text("→")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accent)
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
                        .foregroundColor(Theme.accent)
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
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Text("→")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
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
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(3)
                            case .pros(let text):
                                (Text("Pros: ").font(Theme.label(11)).foregroundColor(Theme.success)
                                 + Text(text).font(Theme.body(11)).foregroundColor(Color(hex: 0x777777)))
                            case .cons(let text):
                                (Text("Cons: ").font(Theme.label(11)).foregroundColor(Theme.error)
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
                        .foregroundColor(Theme.textMuted)

                    // Step dots
                    HStack(spacing: 4) {
                        ForEach(0..<questions.count, id: \.self) { i in
                            Circle()
                                .fill(i < currentIndex ? Color(hex: 0x34a853) :
                                      i == currentIndex ? Theme.accent :
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
                            .foregroundColor(Theme.textMuted)
                            .frame(width: 22, height: 22)
                            .background(Theme.hoverFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

                // Question text
                Text(cleanBold(current.question))
                    .font(Theme.body(14))
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Context (if any)
                if !current.context.isEmpty {
                    Text(current.context)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.textSecondary)
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
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 20)

                    TextField("Something else...", text: $customText)
                        .font(Theme.body(13))
                        .foregroundColor(Theme.textPrimary)
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
                            .foregroundColor(Theme.textMuted)
                        + Text("  ·  ").foregroundColor(Color.white.opacity(0.15))
                        + Text("Enter next")
                            .font(Theme.label(11))
                            .foregroundColor(Theme.textMuted)
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
                            .foregroundColor(Theme.textMuted)
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
        .background(Theme.sidebar)
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
                    .foregroundColor(isSelected ? .white : Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isSelected
                                  ? Theme.accent
                                  : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.15) : Color.white.opacity(0.06)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isSelected
                                          ? Theme.accent
                                          : (isHighlighted ? Color(hex: 0xc4785c).opacity(0.3) : Color.white.opacity(0.1)),
                                          lineWidth: 1)
                    )

                Text(text)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.textPrimary)
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
                        .foregroundColor(Theme.textMuted)
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

// MARK: - Plan Model Selector Menu

private struct PlanModelSelectorMenu: View {
    @Binding var selectedModel: AgentModel
    @Binding var isShowing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(AgentModel.allCases) { model in
                Button {
                    selectedModel = model
                    withAnimation(.easeOut(duration: 0.15)) {
                        isShowing = false
                    }
                } label: {
                    HStack {
                        Text(model.displayName)
                            .font(Theme.body(13))
                            .foregroundColor(model == selectedModel ? .white : Color(hex: 0x938d8d))
                        Spacer()
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(model == selectedModel ? Color.white.opacity(0.06) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            ZStack {
                GlassBackground(material: .popover, cornerRadius: 8)
                Color(hex: 0x1b1b1e).opacity(0.85)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .frame(width: 180)
        .shadow(color: .black.opacity(0.4), radius: 12)
    }
}

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
            return Theme.accent
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
        VStack(alignment: .leading, spacing: 0) {
            // Accent bar
            Rectangle()
                .fill(Theme.builder.opacity(0.6))
                .frame(height: 2)

            VStack(spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.success)
                    Text("Spec complete")
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        onContinue()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

                // Actions
                HStack(spacing: 8) {
                    // Continue — secondary
                    Button(action: onContinue) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                            Text("Continue")
                                .font(Theme.label(12))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    // Hand off — always visible
                    Menu {
                        if siblingTabs.isEmpty {
                            // No siblings — offer to create a new agent tab
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
                            // Existing siblings — pick one
                            ForEach(siblingTabs) { tab in
                                Button {
                                    onHandOff?(tab.id)
                                } label: {
                                    Label(tab.title, systemImage: tab.role.iconName)
                                }
                            }
                            Divider()
                            // Also offer to create a new tab
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
                            Text("Hand off")
                                .font(Theme.label(12))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surface3)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    // Approve & Build — primary
                    Button(action: onApproveAndBuild) {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 11))
                            Text("Approve & Build")
                                .font(Theme.label(13))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.builder)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Hint
                Text("Esc to continue  ·  ⌘↵ to approve")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Theme.sidebar)
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
