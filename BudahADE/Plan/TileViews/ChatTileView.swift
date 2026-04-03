import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var showFilePicker = false
    @State private var glowBreathPhase: Bool = false
    @State private var statusDismissed: Bool = false
    @State private var showModelMenu: Bool = false
    @State private var inputTextHeight: CGFloat = 36

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

    private var isRunning: Bool { session.status == .streaming || session.status == .connecting }

    private var statusText: String {
        switch session.status {
        case .connecting: return "Connecting"
        case .streaming:  return "Running"
        case .done:       return statusDismissed ? "" : "Completed"
        case .error:      return "Error"
        case .idle:       return session.messages.isEmpty ? "Ready" : (statusDismissed ? "" : "Completed")
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .connecting: return Color(hex: 0x68ce6a).opacity(0.6)
        case .streaming:  return Color(hex: 0x68ce6a)
        case .done:       return Color(hex: 0x4264ef)
        case .error:      return .red
        case .idle:       return session.messages.isEmpty ? Theme.Colors.textTertiary : Color(hex: 0x4264ef)
        }
    }

    private var glowColor: Color? {
        if statusDismissed { return nil }
        switch session.status {
        case .connecting: return Color(hex: 0x4e9a4f).opacity(0.5)
        case .streaming:  return Color(hex: 0x4e9a4f)
        case .done:       return Color(hex: 0x4264ef)
        case .idle:       return session.messages.isEmpty ? nil : Color(hex: 0x4264ef)
        case .error:      return nil
        }
    }

    private var breathOpacity: Double {
        glowBreathPhase ? 0.21 : 0.08
    }

    private struct InputHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Circle()
                    .fill(role.color)
                    .frame(width: 10, height: 10)

                Text(role.name)
                    .font(Theme.label(13))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText)
                        .font(Theme.body(13))
                        .foregroundColor(statusColor)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Colors.surface)

            // Messages with fade-out at bottom into input
            messageList
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.clear, Color(hex: 0x0b0a0e)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)
                }

            // Two-layer glassmorphic input
            inputArea(tileHeight: geo.size.height)
        }
        .background(Color(hex: 0x0b0a0e))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0x796e6e).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: (glowColor ?? .clear).opacity(breathOpacity), radius: 47)
        .shadow(color: (glowColor ?? .clear).opacity(breathOpacity * 0.7), radius: 15)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowBreathPhase = true
            }
        }
        .onChange(of: session.status) { _, newStatus in
            if newStatus == .streaming || newStatus == .connecting { statusDismissed = false }
        }
        .simultaneousGesture(TapGesture().onEnded {
            switch session.status {
            case .done, .idle where !session.messages.isEmpty:
                statusDismissed = true
            default: break
            }
        })
        // Opt+P — cycle model
        .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            cycleModel()
            return .handled
        }
        // Esc — cancel streaming agent
        .onKeyPress(.escape) {
            guard session.status == .streaming || session.status == .connecting else { return .ignored }
            canvas.chatManager.cancel(sessionId: session.id)
            return .handled
        }
        // Ctrl+V — paste image from clipboard
        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            if pasteImageFromClipboard() { return .handled }
            return .ignored
        }
        } // GeometryReader
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty && session.status != .streaming && session.status != .connecting {
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
                    if session.status == .streaming || session.status == .connecting {
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
                                    .font(Theme.caption(12))
                                    .foregroundColor(Theme.Colors.textTertiary)
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
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Send a message to start the conversation")
                .font(Theme.body(14))
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
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
                session.status = .idle
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

    private var streamingBubble: some View {
        HStack {
            Text(session.currentStreamingText)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(Color(hex: 0x1b1b1e))
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
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .opacity(i == phase ? 0.8 : 0.2)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color(hex: 0x1b1b1e))
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

    @ViewBuilder
    private func inputArea(tileHeight: CGFloat) -> some View {
        let maxInputHeight = max(60, tileHeight * 0.15)
        VStack(spacing: 0) {
            // Pending image preview
            if let img = pendingImage {
                HStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button {
                        pendingImage = nil
                        pendingImagePath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }

            // Staged content preview
            if let staged = session.stagedContent {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From \(staged.fromAgent)")
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text(staged.content.prefix(100) + (staged.content.count > 100 ? "..." : ""))
                            .font(Theme.body(12))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        session.stagedContent = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(Theme.Colors.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            // Layer 1: Model selector row (dark background)
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showModelMenu.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedModel.displayName.lowercased())
                            .font(Theme.label(14))
                            .foregroundColor(Color(hex: 0x938d8d))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: 0x938d8d))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Token count
                if session.totalTokens > 0 {
                    Text(session.formattedTokenCount)
                        .font(Theme.caption(10))
                        .foregroundColor(Color(hex: 0x938d8d))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(alignment: .topLeading) {
                if showModelMenu {
                    ModelSelectorMenu(selectedModel: $selectedModel, isShowing: $showModelMenu)
                        .padding(.top, 30)
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                }
            }
            .zIndex(showModelMenu ? 100 : 0)

            // Layer 2: Text input (lighter glassmorphic surface)
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text(session.stagedContent != nil
                            ? "What should \(role.name) do with this?"
                            : "Hi, \(role.name). I need help with something")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(height: min(max(inputTextHeight + 10, 34), maxInputHeight))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .background(
                            // Hidden text mirror to measure natural content height
                            Text(inputText.isEmpty ? "A" : inputText)
                                .font(.system(size: 13))
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
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Action row: paperclip left, send/stop right
                HStack(spacing: 8) {
                    Button { showFilePicker = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x938d8d))
                    }
                    .buttonStyle(.plain)
                    .help("Attach image")

                    Spacer()

                    if session.status == .streaming {
                        Button {
                            canvas.chatManager.cancel(sessionId: session.id)
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(
                                    canSend ? Theme.Colors.accent : Theme.Colors.textTertiary
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .background(Color(hex: 0x6e6e6e).opacity(0.2))
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
                .strokeBorder(Color(hex: 0x9b8989).opacity(0.55), lineWidth: 0.75)
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
            if let path = saveImage(data: data) {
                pendingImage = image
                pendingImagePath = path
            }
        }
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImagePath != nil
            || session.stagedContent != nil
    }

    private func cycleModel() {
        let all = AgentModel.allCases
        guard let idx = all.firstIndex(of: selectedModel) else { return }
        selectedModel = all[(idx + 1) % all.count]
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        var prompt = trimmed

        // Prepend connected tile context
        if let connectedContext = canvas.assembleConnectedContext(for: elementId) {
            prompt = "\(connectedContext)\n\n\(prompt)"
        }

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
        if let path = saveImage(data: pngData) {
            pendingImage = image
            pendingImagePath = path
            return true
        }
        return false
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
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(Color(hex: 0x30221f))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    // Tool calls — compact inline
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
                        Text(message.content)
                            .font(Theme.body(14))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(Color(hex: 0x1b1b1e))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 40)
            }

            // Send-to button — only on hover
            if !message.content.isEmpty && isHovered {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showSendToMenu = showSendToMenu == message.id ? nil : message.id
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                        Text("Send to")
                            .font(Theme.caption(11))
                    }
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
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

// ModelSelectorMenu moved to Shared/ChatInputBar.swift
