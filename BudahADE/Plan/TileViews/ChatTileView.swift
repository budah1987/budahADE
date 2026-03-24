import SwiftUI
import AppKit

// MARK: - ChatTileView

struct ChatTileView: View {
    @ObservedObject var session: AgentSession
    let role: AgentRole
    @ObservedObject var canvas: PlanCanvasState
    let elementId: UUID
    let onClose: () -> Void

    @State private var inputText: String = ""
    @State private var selectedModel: AgentModel
    @State private var showSendToMenu: UUID?
    @State private var pendingImage: NSImage?
    @State private var pendingImagePath: String?

    init(
        session: AgentSession,
        role: AgentRole,
        canvas: PlanCanvasState,
        elementId: UUID,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.role = role
        self.canvas = canvas
        self.elementId = elementId
        self.onClose = onClose
        self._selectedModel = State(initialValue: role.defaultModel)
    }

    var body: some View {
        TileChrome(
            title: role.name,
            icon: "bubble.left.and.text.bubble.right",
            dotColor: role.color,
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                statusBar
                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
                messageList
                Rectangle().fill(Theme.borderSubtle).frame(height: 0.5)
                inputArea
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Model picker
            Picker("Model", selection: $selectedModel) {
                ForEach(AgentModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .pickerStyle(.menu)
            .font(Theme.caption(10))
            .labelsHidden()
            .frame(maxWidth: 80)

            Spacer()

            // Token count
            if session.totalTokens > 0 {
                Text(session.formattedTokenCount)
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.textMuted)
            }

            // Ellipsis menu
            Menu {
                Button("New Session") { newSession() }
                Button("Summarize & Compact") { }
                    .disabled(true)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var statusColor: Color {
        switch session.status {
        case .streaming: return .green
        case .error:     return .red
        default:         return Theme.textMuted
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty && session.status != .streaming {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    // Error banner
                    if case .error(let msg) = session.status {
                        errorBanner(msg)
                    }

                    ForEach(session.messages) { message in
                        MessageBubble(
                            message: message,
                            showSendToMenu: $showSendToMenu,
                            onSendToSpec: { sendToSpec(message.content) },
                            onSendToAgent: { agentMode in sendToAgent(message.content, agentMode: agentMode) }
                        )
                        .id(message.id)
                    }

                    // Streaming indicator
                    if session.status == .streaming {
                        if !session.currentStreamingText.isEmpty {
                            streamingBubble
                                .id("streaming")
                        } else if !session.pendingToolCalls.isEmpty {
                            // Tool activity — compact spinner with latest tool name
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                Text("Working... (\(session.pendingToolCalls.count) tool calls)")
                                    .font(Theme.caption(11))
                                    .foregroundColor(Theme.textMuted)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .id("tool-activity")
                        } else {
                            thinkingDots
                                .id("streaming")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session.currentStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(Theme.textMuted)
            Text("Send a message to start the conversation")
                .font(Theme.body(12))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
            Text(message)
                .font(Theme.body(11))
                .foregroundColor(.red)
                .lineLimit(3)
            Spacer()
            Button("Retry") {
                session.status = .idle
            }
            .font(Theme.caption(10))
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

    private var streamingBubble: some View {
        HStack {
            Text(session.currentStreamingText)
                .font(Theme.body(12))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surface2.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
        }
    }

    private var thinkingDots: some View {
        TimelineView(.animation(minimumInterval: 0.4)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.textMuted)
                        .frame(width: 5, height: 5)
                        .opacity(i == phase ? 1.0 : 0.3)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface2.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if session.status == .streaming {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        } else if let last = session.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
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
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button {
                        pendingImage = nil
                        pendingImagePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            // Staged content preview (from "Send to" action)
            if let staged = session.stagedContent {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From \(staged.fromAgent)")
                            .font(Theme.caption(10))
                            .foregroundColor(Theme.textMuted)
                        Text(staged.content.prefix(120) + (staged.content.count > 120 ? "..." : ""))
                            .font(Theme.body(11))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(3)
                    }
                    Spacer()
                    Button {
                        session.stagedContent = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Theme.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            HStack(spacing: 6) {
                TextField(
                    session.stagedContent != nil
                        ? "What should \(role.name) do with this?"
                        : "Message \(role.name)...",
                    text: $inputText,
                    axis: .vertical
                )
                    .font(Theme.body(12))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .onSubmit { sendMessage() }
                    .onKeyPress(.return) {
                        sendMessage()
                        return .handled
                    }

                if session.status == .streaming {
                    Button {
                        canvas.chatManager.cancel(sessionId: session.id)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(
                                canSend ? Theme.accent : Theme.textMuted
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Theme.surface2.opacity(0.4))
        .onDrop(of: ["public.image", "public.file-url"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImagePath != nil
            || session.stagedContent != nil
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        var prompt = trimmed

        // Handle staged content from "Send to" — frame as primary subject
        if let staged = session.stagedContent {
            let instruction = prompt.isEmpty
                ? "The following was shared with you from \(staged.fromAgent). Read it and respond."
                : prompt
            prompt = """
            \(instruction)

            --- Content from \(staged.fromAgent) ---
            \(staged.content)
            ---
            """
            session.stagedContent = nil
        }

        // Handle image attachment
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

        canvas.sendChatMessage(sessionId: session.id, prompt: prompt, model: selectedModel)
    }

    private func newSession() {
        session.messages = []
        session.claudeSessionId = nil
        session.totalInputTokens = 0
        session.totalOutputTokens = 0
        session.status = .idle
        session.currentStreamingText = ""
    }

    private func sendToSpec(_ content: String) {
        canvas.sendToSpec(content: content, fromAgent: role)
        showSendToMenu = nil
    }

    private func sendToAgent(_ content: String, agentMode: AgentMode) {
        canvas.sendToAgent(content: content, fromAgent: role, targetAgent: agentMode)
        showSendToMenu = nil
    }

    @discardableResult
    private func saveImage(data: Data) -> String? {
        let imageDir = "\(canvas.worktreePath)/.budahade/images"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: imageDir, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).png"
        let path = "\(imageDir)/\(filename)"
        guard fm.createFile(atPath: path, contents: data) else { return nil }
        return path
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        if let path = self.saveImage(data: data) {
                            self.pendingImage = image
                            self.pendingImagePath = path
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage
    @Binding var showSendToMenu: UUID?
    let onSendToSpec: () -> Void
    let onSendToAgent: (AgentMode) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: bubbleAlignment, spacing: 2) {
            bubbleContent
            if showSendToMenu == message.id {
                SendToMenu(
                    onSendToSpec: onSendToSpec,
                    onSendToAgent: onSendToAgent
                )
                .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.content)
                .font(Theme.body(12))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    // Tool calls disclosure
                    if let tools = message.toolCalls, !tools.isEmpty {
                        DisclosureGroup("> \(tools.count) tool call\(tools.count == 1 ? "" : "s")") {
                            ForEach(tools, id: \.id) { tool in
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .font(.system(size: 9))
                                        .foregroundColor(Theme.textMuted)
                                    Text("\(tool.name)")
                                        .font(Theme.mono(10))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .padding(.leading, 8)
                                .padding(.top, 2)
                            }
                        }
                        .font(Theme.caption(10))
                        .foregroundColor(Theme.textMuted)
                    }

                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(Theme.body(12))
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surface2.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 40)
            }

            // Send-to button (shows on hover, only for messages with text)
            if !message.content.isEmpty && (isHovered || showSendToMenu == message.id) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showSendToMenu = showSendToMenu == message.id ? nil : message.id
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                        Text("Send to")
                            .font(Theme.caption(10))
                    }
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.hoverFill)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var systemBubble: some View {
        Text(message.content)
            .font(Theme.caption(10))
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

    private var bubbleAlignment: HorizontalAlignment {
        switch message.role {
        case .user:      return .trailing
        case .assistant: return .leading
        case .system:    return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch message.role {
        case .user:      return .trailing
        case .assistant: return .leading
        case .system:    return .leading
        }
    }
}
