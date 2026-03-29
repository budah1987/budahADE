import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - PlanChatView

struct PlanChatView: View {
    @ObservedObject var state: PlanChatState

    @State private var inputText: String = ""
    @State private var pendingImage: NSImage?
    @State private var pendingImagePath: String?
    @State private var showFilePicker = false
    @State private var showModelMenu: Bool = false
    @State private var inputTextHeight: CGFloat = 36
    @State private var thinkingStartDate: Date?
    @State private var activityLog: [ActivityEntry] = []
    @State private var lastToolCallCount: Int = 0

    private var session: AgentSession? { state.plannerSession }
    private var isRunning: Bool {
        session?.status == .streaming || session?.status == .connecting
    }

    private struct InputHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                            PlanMessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming text bubble
                        if session.status == .streaming && !session.currentStreamingText.isEmpty {
                            streamingBubble(session.currentStreamingText)
                                .id("streaming")
                        }

                        // Unified thinking indicator — connecting, thinking, or tool activity
                        if session.status == .connecting ||
                           (session.status == .streaming && session.currentStreamingText.isEmpty) {
                            ThinkingIndicator(
                                activityLog: activityLog,
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
            .onChange(of: session?.currentStreamingText) { _, newText in
                scrollToBottom(proxy: proxy)
                // When streaming text begins, mark it in the activity log
                if let text = newText, !text.isEmpty,
                   activityLog.last?.label != "Responding..." {
                    activityLog.append(ActivityEntry(label: "Responding..."))
                }
            }
            .onChange(of: session?.status) { oldValue, newValue in
                if newValue == .connecting {
                    thinkingStartDate = Date()
                    activityLog = [ActivityEntry(label: "Connecting...")]
                    lastToolCallCount = 0
                } else if newValue == .streaming && oldValue == .connecting {
                    activityLog.append(ActivityEntry(label: "Thinking..."))
                } else if newValue == .idle || newValue == .done || newValue == nil {
                    thinkingStartDate = nil
                } else if case .error = newValue {
                    thinkingStartDate = nil
                }
            }
            .onChange(of: session?.pendingToolCalls.count) { oldCount, newCount in
                guard let tools = session?.pendingToolCalls,
                      let newCount, let oldCount,
                      newCount > oldCount else { return }
                // Append new tool calls as activity entries
                for tool in tools.suffix(newCount - oldCount) {
                    let label = ActivityEntry.label(for: tool.name)
                    // Avoid duplicating the same label consecutively
                    if activityLog.last?.label != label {
                        activityLog.append(ActivityEntry(label: label))
                    }
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

    var body: some View {
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

// MARK: - Activity Entry

struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let timestamp = Date()

    static func == (lhs: ActivityEntry, rhs: ActivityEntry) -> Bool {
        lhs.id == rhs.id
    }

    static func label(for toolName: String) -> String {
        switch toolName {
        case "Read", "Glob":
            return "Reading files..."
        case "Grep":
            return "Searching codebase..."
        case "Edit", "Write":
            return "Editing code..."
        case "Bash":
            return "Running command..."
        case "Agent":
            return "Researching..."
        case "WebSearch", "WebFetch":
            return "Browsing web..."
        default:
            return "Working..."
        }
    }
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {
    let activityLog: [ActivityEntry]
    let startDate: Date?

    // Carousel shows up to 5 rows: 2 past (faded) + current (white) + 2 future (empty/dim)
    private let visibleSlots = 5
    private let rowHeight: CGFloat = 20

    private static let brailleFrames: [String] = [
        "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}",
        "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}",
        "\u{2807}", "\u{280F}"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Activity carousel
            activityCarousel

            // Braille spinner + timer row
            HStack(spacing: 8) {
                TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                    let idx = Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % Self.brailleFrames.count
                    Text(Self.brailleFrames[idx])
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }

                if let startDate {
                    TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        Text(String(format: "%.1fs", elapsed))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var activityCarousel: some View {
        let activeIndex = activityLog.count - 1

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { offset, entry in
                let slotIndex = offset
                let distanceFromActive = slotIndex - activeSlotPosition

                Text(entry.label)
                    .font(Theme.caption(12))
                    .foregroundColor(colorForDistance(distanceFromActive))
                    .frame(height: rowHeight, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeOut(duration: 0.3), value: activityLog.count)
        .mask(
            VStack(spacing: 0) {
                // Top fade — past items fade out
                LinearGradient(
                    colors: [.clear, .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: rowHeight)

                // Full opacity middle
                Rectangle().fill(.white)

                // Bottom fade — subtle shadow
                LinearGradient(
                    colors: [.white, .white.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: rowHeight * 0.5)
            }
        )
    }

    /// The entries visible in the carousel window
    private var visibleEntries: [ActivityEntry] {
        let count = activityLog.count
        if count == 0 { return [ActivityEntry(label: "Thinking...")] }

        // Show up to 2 previous + current
        let startIdx = max(0, count - 3)
        return Array(activityLog[startIdx..<count])
    }

    /// Position of the active (latest) entry within visibleEntries
    private var activeSlotPosition: Int {
        visibleEntries.count - 1
    }

    private func colorForDistance(_ distance: Int) -> Color {
        if distance == 0 {
            // Active — subtle white
            return Color.white.opacity(0.85)
        } else if distance < 0 {
            // Past — progressively faded
            let fade = max(0.15, 0.4 + Double(distance) * 0.15)
            return Color.white.opacity(fade)
        } else {
            // Future placeholder slots
            return Color.white.opacity(0.1)
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
