import AppKit

/// Hyprland-style hover focus: a global mouse-move monitor hit-tests the
/// pointer and focuses the window underneath. Global monitors exclude our own
/// app's events, so hovering hyprmac's windows never steals focus, and mouse
/// monitors need no extra permissions.
@MainActor
final class FocusFollowsMouse {

    private weak var controller: TilingController?
    private var monitor: Any?
    private var lastProcessed = ContinuousClock.now

    init(controller: TilingController) {
        self.controller = controller
    }

    var enabled: Bool { monitor != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func mouseMoved() {
        // Throttle to ~20 Hz; hover focus doesn't need per-pixel updates.
        let now = ContinuousClock.now
        guard now - lastProcessed > .milliseconds(50) else { return }
        lastProcessed = now

        // A held button means a drag (moving/resizing/selecting) — never
        // shift focus mid-drag.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        // NSEvent.mouseLocation is bottom-left-origin screen coords; flip to AX.
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = CGPoint(x: location.x, y: primaryHeight - location.y)
        controller?.hoverFocus(at: axPoint)
    }
}
