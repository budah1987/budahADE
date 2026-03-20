import SwiftUI

// MARK: - Agent Status View

struct AgentStatusView: View {
    let status: AgentStatus

    var body: some View {
        Group {
            switch status {
            case .inactive:  InactiveIndicator()
            case .thinking:  ActiveIndicator()
            case .working:   WorkingIndicator()
            case .completed: CompletedIndicator()
            }
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Inactive — Breathing dashed circle

private struct InactiveIndicator: View {
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .foregroundColor(Theme.textMuted.opacity(0.4))
                .frame(width: 18, height: 18)

            Circle()
                .fill(Theme.textMuted.opacity(0.4))
                .frame(width: 4, height: 4)
        }
        .opacity(breathing ? 0.5 : 0.25)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - Active — Green dot with expanding ring

private struct ActiveIndicator: View {
    @State private var ringExpanding = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.success, lineWidth: 1.5)
                .scaleEffect(ringExpanding ? 1.8 : 1.0)
                .opacity(ringExpanding ? 0.0 : 0.6)
                .frame(width: 14, height: 14)

            Circle()
                .fill(Theme.success)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ringExpanding = true
            }
        }
    }
}

// MARK: - Working — Spinning arc + staggered dots

private struct WorkingIndicator: View {
    @State private var rotating = false
    @State private var dotsAnimating = false

    private let dotCount = 3

    var body: some View {
        ZStack {
            // Spinning arc
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color(hex: 0x6366f1), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(rotating ? 360 : 0))
                .frame(width: 20, height: 20)

            // Staggered dots
            HStack(spacing: 3) {
                ForEach(0..<dotCount, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: 0x6366f1))
                        .frame(width: 3, height: 3)
                        .scaleEffect(dotsAnimating ? 1.4 : 1.0)
                        .opacity(dotsAnimating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                            value: dotsAnimating
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotating = true
            }
            dotsAnimating = true
        }
    }
}

// MARK: - Completed — Checkmark with spring entrance

private struct CompletedIndicator: View {
    @State private var appeared = false
    @State private var checkDrawn = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Theme.success.opacity(0.12))
                .overlay(
                    Circle()
                        .stroke(Theme.success, lineWidth: 1.5)
                )
                .frame(width: 20, height: 20)
                .scaleEffect(appeared ? 1.0 : 0.5)
                .opacity(appeared ? 1.0 : 0.0)

            // Checkmark
            CheckmarkShape()
                .trim(from: 0, to: checkDrawn ? 1.0 : 0.0)
                .stroke(
                    Theme.success,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 10, height: 10)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                appeared = true
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
                checkDrawn = true
            }
        }
    }
}

// MARK: - Checkmark Shape

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(
            x: rect.minX + rect.width * 0.18,
            y: rect.midY + rect.height * 0.06
        ))
        p.addLine(to: CGPoint(
            x: rect.minX + rect.width * 0.42,
            y: rect.maxY - rect.height * 0.14
        ))
        p.addLine(to: CGPoint(
            x: rect.maxX - rect.width * 0.1,
            y: rect.minY + rect.height * 0.18
        ))
        return p
    }
}
