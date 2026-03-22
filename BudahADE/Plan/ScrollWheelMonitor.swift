import SwiftUI

struct CanvasInputMonitor: NSViewRepresentable {
    let onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool) -> Void
    let onPanDrag: (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Void
    let onSpaceStateChanged: (_ isHeld: Bool) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> CanvasInputNSView {
        let view = CanvasInputNSView(
            onScroll: onScroll,
            onPanDrag: onPanDrag,
            onSpaceStateChanged: onSpaceStateChanged,
            onEscape: onEscape
        )
        // Ensure we can receive key events
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: CanvasInputNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onPanDrag = onPanDrag
        nsView.onSpaceStateChanged = onSpaceStateChanged
        nsView.onEscape = onEscape
    }

    class CanvasInputNSView: NSView {
        var onScroll: (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool) -> Void
        var onPanDrag: (_ deltaX: CGFloat, _ deltaY: CGFloat) -> Void
        var onSpaceStateChanged: (_ isHeld: Bool) -> Void
        var onEscape: () -> Void

        private var isSpaceHeld = false
        private var lastDragPoint: NSPoint?
        private var scrollMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        init(
            onScroll: @escaping (_ deltaX: CGFloat, _ deltaY: CGFloat, _ isZoom: Bool) -> Void,
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
            window?.makeFirstResponder(self)

            // Install/remove Shift+scroll monitor with window lifecycle
            if window != nil && scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self else { return event }
                    // Cmd+scroll → zoom (even over tiles)
                    if event.modifierFlags.contains(.command) {
                        self.onScroll(event.scrollingDeltaX, event.scrollingDeltaY, true)
                        return nil
                    }
                    // Shift+scroll → canvas pan (even over tiles)
                    if event.modifierFlags.contains(.shift) {
                        self.onScroll(event.scrollingDeltaX, event.scrollingDeltaY, false)
                        return nil
                    }
                    return event
                }
            } else if window == nil, let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }

        override func removeFromSuperview() {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            super.removeFromSuperview()
        }

        // MARK: - Scroll Wheel (zoom + pan)

        override func scrollWheel(with event: NSEvent) {
            let isZoom = event.modifierFlags.contains(.command)
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY, isZoom)
        }

        // MARK: - Spacebar tracking

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {  // 53 = Escape
                onEscape()
            } else if event.keyCode == 49 && !event.isARepeat {  // 49 = spacebar
                isSpaceHeld = true
                NSCursor.openHand.push()
                onSpaceStateChanged(true)
            }
            // Don't call super — prevents system beep for unhandled keys
        }

        override func keyUp(with event: NSEvent) {
            if event.keyCode == 49 {
                isSpaceHeld = false
                NSCursor.pop()
                onSpaceStateChanged(false)
            }
        }

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
