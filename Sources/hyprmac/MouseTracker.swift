import AppKit
import ApplicationServices

/// Watches global mouse events (permission-free) to cover what AX events
/// can't: live border tracking during window drags, and re-asserting the
/// float-above-tiles z-order after clicks reorder windows behind our back.
@MainActor
final class MouseTracker {

    /// Returns the focused window's element, or nil when nothing is focused.
    var focusedElement: (() -> AXUIElement?)?
    /// A drag tick with the focused window's live frame (AX coordinates).
    var onDragTick: ((CGRect) -> Void)?
    /// The mouse settled (drag ended, or a click's reordering finished).
    var onSettled: (() -> Void)?

    private var monitor: Any?
    private var lastTick = ContinuousClock.now
    private var dragging = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let kind = event.type
            MainActor.assumeIsolated { self?.handle(kind) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        dragging = false
    }

    private func handle(_ kind: NSEvent.EventType) {
        switch kind {
        case .leftMouseDragged:
            // ~90 Hz cap; each tick reads the real frame, so a drag inside a
            // window (text selection) just redraws the border in place.
            let now = ContinuousClock.now
            guard now - lastTick > .milliseconds(11) else { return }
            lastTick = now
            dragging = true
            guard let element = focusedElement?(),
                  let frame = AX.frame(of: element) else { return }
            onDragTick?(frame)

        case .leftMouseUp:
            let wasDragging = dragging
            dragging = false
            if wasDragging {
                onSettled?()
            } else {
                // A plain click can still reorder windows (raising the
                // clicked app); let macOS finish, then re-assert order.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.onSettled?()
                }
            }

        default:
            break
        }
    }
}
