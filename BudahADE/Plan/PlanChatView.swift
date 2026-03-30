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

    @State private var inputText: String = ""
    @State private var pendingImage: NSImage?
    @State private var pendingImagePath: String?
    @State private var showFilePicker = false
    @State private var showModelMenu: Bool = false
    @State private var inputTextHeight: CGFloat = 36
    @State private var thinkingStartDate: Date?
    @FocusState private var inputFocused: Bool

    private var session: AgentSession? { state.plannerSession }
    private var isRunning: Bool {
        session?.status == .streaming || session?.status == .connecting
    }

    /// True when there's at least one assistant message — show action buttons
    private var hasAssistantMessage: Bool {
        session?.messages.contains { $0.role == .assistant } == true
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

            // Messages
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

            // Option buttons sheet — slides up from input
            if let session,
               !session.optionsDismissed,
               let lastMsg = session.messages.last,
               lastMsg.role == .assistant,
               !lastMsg.content.isEmpty,
               let options = session.detectOptions(in: lastMsg.content) {
                OptionButtonsSheet(
                    options: options,
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
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Action buttons — shown when there's at least one assistant message
            if hasAssistantMessage {
                PlanActionButtons(
                    onApprove: handleApprove,
                    onEdit: handleEdit,
                    onHandOff: { targetTabId in
                        onHandOff?(targetTabId)
                    },
                    siblingTabs: siblingTabs
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Input area
            inputArea
        }
        .background(Theme.contentBg)
        .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            cycleModel()
            return .handled
        }
        .onKeyPress(.escape) {
            guard isRunning else { return .ignored }
            state.cancel()
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
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onChange(of: session?.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session?.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
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

            // Model selector row
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showModelMenu.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.selectedModel.displayName.lowercased())
                            .font(Theme.mono(14))
                            .foregroundColor(Color(hex: 0x938d8d))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: 0x938d8d))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Token count
                if let session, session.totalTokens > 0 {
                    Text(session.formattedTokenCount)
                        .font(Theme.mono(10))
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
                            sendMessage()
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
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12
                )
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
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImagePath != nil
    }

    private func handleApprove() {
        guard let lastAssistant = session?.messages.last(where: { $0.role == .assistant }),
              !lastAssistant.content.isEmpty else { return }
        let version = SpecVersionManager.approve(content: lastAssistant.content, in: state.worktreePath)
        state.sendMessage("✓ Spec approved and saved as version \(version).")
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

private struct PlanMessageBubble: View {
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
                    if isSpec {
                        specActionButtons
                    }
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
                        .font(Theme.mono(10))
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

private struct OptionButtonsSheet: View {
    let options: [AgentSession.DetectedOption]
    let onSelect: (AgentSession.DetectedOption) -> Void
    let onDismiss: () -> Void
    let onCustomResponse: (String) -> Void

    @State private var customText: String = ""
    @FocusState private var sheetFocused: Bool
    @FocusState private var customFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header with close button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { onDismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Theme.hoverFill)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)

            // Option rows
            ForEach(options) { option in
                OptionSheetRow(option: option, onSelect: onSelect)
            }

            // "Something else" free-text input
            HStack(spacing: 8) {
                Text("↵")
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 18, alignment: .trailing)
                TextField("Something else...", text: $customText)
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
            .background(Theme.hoverFill.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface2.opacity(0.6))
        .focusable()
        .focused($sheetFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                sheetFocused = true
            }
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
}

private struct OptionSheetRow: View {
    let option: AgentSession.DetectedOption
    let onSelect: (AgentSession.DetectedOption) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                onSelect(option)
            }
        } label: {
            HStack(spacing: 8) {
                Text(option.label)
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.accent)
                    .frame(width: 18, alignment: .trailing)
                InlineBoldText(option.text)
                    .font(Theme.body(13))
                    .foregroundColor(isHovered ? .white : Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovered ? Theme.hoverFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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
                            .font(Theme.mono(13))
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
