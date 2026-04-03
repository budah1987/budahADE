import SwiftUI

/// Full-width app bar: traffic lights area, project dropdown, resource meter.
/// Conversation tabs live in the terminal area for natural alignment with content.
struct AppBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        HStack(spacing: 0) {
            // Left zone: traffic lights + project dropdown (matches sidebar width)
            HStack(spacing: 0) {
                Color.clear.frame(width: 68)
                WorkspaceDropdown()
                Spacer(minLength: 0)
            }
            .frame(width: Theme.Layout.sidebarWidth)

            Spacer(minLength: 0)

            // Right: resource meter placeholder
            ResourceMeterPlaceholder()
                .padding(.trailing, Theme.Spacing.lg)
        }
        .frame(height: Theme.Layout.appBarHeight)
    }
}

// MARK: - Resource Meter

private struct ResourceMeterPlaceholder: View {
    @State private var isHovering = false
    @State private var showOverlay = false
    @State private var cpuUsage: Double = 0
    @State private var memoryMB: Double = 0
    @State private var refreshTimer: Timer?

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                showOverlay.toggle()
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 10))
                Text(String(format: "%.1f", memoryMB))
                    .font(Theme.code(11))
                Text("MB")
                    .font(Theme.caption(11))
            }
            .foregroundColor(isHovering ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(isHovering ? Color.white.opacity(0.08) : Theme.Colors.hoverFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .overlay(alignment: .topTrailing) {
            if showOverlay {
                ResourceOverlay(
                    cpuUsage: cpuUsage,
                    memoryMB: memoryMB,
                    onDismiss: { showOverlay = false }
                )
                .offset(y: 30)
                .fixedSize()
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .zIndex(showOverlay ? 100 : 0)
        .onAppear { startMonitoring() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private func startMonitoring() {
        updateMetrics()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            DispatchQueue.main.async { updateMetrics() }
        }
    }

    private func updateMetrics() {
        // Memory usage via task_info
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryMB = Double(info.resident_size) / (1024 * 1024)
        }

        // CPU usage approximation via rusage
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        // Use user+system time delta as a rough CPU indicator
        let userTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let sysTime = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        let totalTime = userTime + sysTime
        // Approximate CPU% from process uptime
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime > 0 {
            cpuUsage = (totalTime / uptime) * 100
        }
    }
}

// MARK: - Resource Overlay

private struct ResourceOverlay: View {
    let cpuUsage: Double
    let memoryMB: Double
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("RESOURCES")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(0.5)
                Spacer()
            }

            // Summary line
            HStack(spacing: 12) {
                Text("CPU")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(String(format: "%.1f%%", cpuUsage))
                    .font(Theme.code(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fontWeight(.bold)

                Text("Memory")
                    .font(Theme.label(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(String(format: "%.1f MB", memoryMB))
                    .font(Theme.code(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .fontWeight(.bold)
            }

            Divider().background(Color.white.opacity(0.08))

            // Table header
            HStack {
                Text("Name")
                    .font(Theme.caption(10))
                    .foregroundColor(Color(hex: 0x938d8d))
                    .frame(width: 100, alignment: .leading)
                Spacer()
                Text("CPU")
                    .font(Theme.caption(10))
                    .foregroundColor(Color(hex: 0x938d8d))
                    .frame(width: 50, alignment: .trailing)
                Text("Mem")
                    .font(Theme.caption(10))
                    .foregroundColor(Color(hex: 0x938d8d))
                    .frame(width: 60, alignment: .trailing)
            }

            // App process row
            HStack {
                Text("App")
                    .font(Theme.body(11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 100, alignment: .leading)
                Spacer()
                Text(String(format: "%.1f%%", cpuUsage))
                    .font(Theme.code(11))
                    .foregroundColor(Color(hex: 0x938d8d))
                    .frame(width: 50, alignment: .trailing)
                Text(String(format: "%.1f MB", memoryMB))
                    .font(Theme.code(11))
                    .foregroundColor(Color(hex: 0x938d8d))
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(
            ZStack {
                GlassBackground(material: .popover, cornerRadius: 10)
                Color(hex: 0x1b1b1e).opacity(0.9)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 16)
    }
}
