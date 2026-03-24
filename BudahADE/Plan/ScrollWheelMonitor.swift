import SwiftUI
import WebKit

struct CanvasInputMonitor: NSViewRepresentable {
    let onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool, _ isShiftPan: Bool) -> Void
    let onPanDrag: (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Void
    let onSpaceStateChanged: (_ isHeld: Bool) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> CanvasInputNSView {
        CanvasInputNSView(
            onScroll: onScroll,
            onPanDrag: onPanDrag,
            onSpaceStateChanged: onSpaceStateChanged,
            onEscape: onEscape
        )
    }

    func updateNSView(_ nsView: CanvasInputNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onPanDrag = onPanDrag
        nsView.onSpaceStateChanged = onSpaceStateChanged
        nsView.onEscape = onEscape
    }

    class CanvasInputNSView: NSView {
        var onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool, _ isShiftPan: Bool) -> Void
        var onPanDrag: (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Void
        var onSpaceStateChanged: (_ isHeld: Bool) -> Void
        var onEscape: () -> Void

        private var isSpaceHeld = false
        private var lastDragPoint: NSPoint?
        private var scrollMonitor: Any?
        private var keyDownMonitor: Any?
        private var keyUpMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        init(
            onScroll: @escaping (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool, _ isShiftPan: Bool) -> Void,
            onPanDrag: @escaping (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Void,
            onSpaceStateChanged: @escaping (_ isHeld: Bool) -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.onScroll = onScroll
            self.onPanDrag = onPanDrag
            self.onSpaceStateChanged = onSpaceStateChanged
            self.onEscape = onEscape
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil {
                installMonitors()
            } else {
                removeMonitors()
            }
        }

        override func removeFromSuperview() {
            removeMonitors()
            super.removeFromSuperview()
        }

        /// Whether the current first responder is a text input (terminal, TextEditor, or any NSTextView)
        private func textInputHasFocus() -> Bool {
            guard let responder = window?.firstResponder else { return false }
            // NSTextView is the underlying view for SwiftUI TextEditor and TextField
            if responder is NSTextView { return true }
            // Also check the view hierarchy for terminal surfaces
            if let view = responder as? NSView {
                var current: NSView? = view
                while let v = current {
                    if v is TerminalSurfaceView { return true }
                    if v is WKWebView { return true }
                    current = v.superview
                }
            }
            return false
        }

        private func installMonitors() {
            guard scrollMonitor == nil else { return }

            // Scroll monitor: Cmd+scroll → zoom, Shift+scroll → pan (even over tiles)
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                if event.modifierFlags.contains(.command) {
                    self.onScroll(event.scrollingDeltaX, event.scrollingDeltaY, true, false)
                    return nil
                }
                if event.modifierFlags.contains(.shift) {
                    self.onScroll(event.scrollingDeltaX, event.scrollingDeltaY, false, true)
                    return nil
                }
                return event
            }

            // Key-down monitor: only handle space/escape when terminal doesn't have focus
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // If a terminal has focus, let ALL keys pass through
                if self.textInputHasFocus() { return event }

                if event.keyCode == 53 {  // Escape
                    self.onEscape()
                    return nil
                } else if event.keyCode == 49 && !event.isARepeat {  // Spacebar
                    self.isSpaceHeld = true
                    NSCursor.openHand.push()
                    self.onSpaceStateChanged(true)
                    return nil
                }
                return event
            }

            // Key-up monitor: match space release
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else { return event }
                if self.textInputHasFocus() { return event }

                if event.keyCode == 49 {
                    self.isSpaceHeld = false
                    NSCursor.pop()
                    self.onSpaceStateChanged(false)
                    return nil
                }
                return event
            }
        }

        private func removeMonitors() {
            if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
            if let m = keyDownMonitor { NSEvent.removeMonitor(m); keyDownMonitor = nil }
            if let m = keyUpMonitor { NSEvent.removeMonitor(m); keyUpMonitor = nil }
        }

        // MARK: - Scroll Wheel (zoom + pan)

        override func scrollWheel(with event: NSEvent) {
            let isZoom = event.modifierFlags.contains(.command)
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY, isZoom, false)
        }

        // Key handling moved to local monitors (installMonitors)
        // so terminal tiles receive Cmd/Opt key combos normally

        // MARK: - Mouse drag for space-panning

        override func mouseDown(with event: NSEvent) {
            if isSpaceHeld {
                lastDragPoint = event.locationInWindow
                NSCursor.closedHand.push()
            } else {
                super.mouseDown(with: event)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard isSpaceHeld, let last = lastDragPoint else {
                super.mouseDragged(with: event)
                return
            }
            let current = event.locationInWindow
            let dx = current.x - last.x
            let dy = -(current.y - last.y)  // flip Y for screen coords
            lastDragPoint = current
            onPanDrag(dx, dy)
        }

        override func mouseUp(with event: NSEvent) {
            if isSpaceHeld && lastDragPoint != nil {
                lastDragPoint = nil
                NSCursor.pop()  // remove closedHand, openHand remains
            } else {
                super.mouseUp(with: event)
            }
        }
    }
}

// Keep backward compatibility alias
typealias ScrollWheelMonitor = CanvasInputMonitor
