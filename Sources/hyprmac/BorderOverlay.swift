import AppKit
import HyprmacCore

/// Hyprland-style colored border around the focused window: a transparent,
/// click-through panel floating just above the window layer.
@MainActor
final class BorderOverlay {

    private let panel: NSPanel
    private let borderView = BorderView()

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = borderView
    }

    func update(around axFrame: CGRect?, color: ConfigColor, width: Int) {
        guard let axFrame, width > 0, color.a > 0 else {
            panel.orderOut(nil)
            return
        }
        let borderWidth = CGFloat(width)
        let outset = axFrame.insetBy(dx: -borderWidth, dy: -borderWidth)

        // AX top-left origin → AppKit bottom-left origin.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitRect = NSRect(x: outset.origin.x,
                                y: primaryHeight - outset.maxY,
                                width: outset.width,
                                height: outset.height)

        borderView.color = NSColor(red: CGFloat(color.r) / 255,
                                   green: CGFloat(color.g) / 255,
                                   blue: CGFloat(color.b) / 255,
                                   alpha: CGFloat(color.a) / 255)
        borderView.borderWidth = borderWidth
        panel.setFrame(appKitRect, display: true)
        panel.orderFrontRegardless()
        borderView.needsDisplay = true
    }

    func hide() {
        panel.orderOut(nil)
    }

    private final class BorderView: NSView {
        var color: NSColor = .cyan
        var borderWidth: CGFloat = 2

        override func draw(_ dirtyRect: NSRect) {
            let inset = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = NSBezierPath(roundedRect: inset, xRadius: 9, yRadius: 9)
            path.lineWidth = borderWidth
            color.setStroke()
            path.stroke()
        }
    }
}
