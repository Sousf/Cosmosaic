import AppKit
import QuartzCore
import CosmosaicCore

/// Everything the border needs to draw itself.
struct BorderAppearance: Equatable {
    var fill: BorderFill
    var width: Int
    var animation: BorderAnimation
    var speed: Double

    init(general: GeneralConfig) {
        fill = general.activeBorder
        width = general.borderSize
        animation = general.borderAnimation
        speed = general.borderAnimationSpeed
    }
}

/// Hyprland-style border around the focused window: a transparent,
/// click-through panel whose ring is filled by a Core Animation gradient —
/// solid, angled multi-stop, or an infinitely rotating rainbow (GPU-driven,
/// no timers in-process).
@MainActor
final class BorderOverlay {

    private let panel: NSPanel
    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var currentAppearance: BorderAppearance?

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

        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content

        maskLayer.fillColor = NSColor.clear.cgColor
        maskLayer.strokeColor = NSColor.black.cgColor
        content.layer?.addSublayer(gradientLayer)
        content.layer?.mask = maskLayer
    }

    func update(around axFrame: CGRect?, appearance: BorderAppearance) {
        guard let axFrame, appearance.width > 0,
              !appearance.fill.colors.isEmpty else {
            panel.orderOut(nil)
            return
        }
        let borderWidth = CGFloat(appearance.width)
        let outset = axFrame.insetBy(dx: -borderWidth, dy: -borderWidth)

        // AX top-left origin → AppKit bottom-left origin.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitRect = NSRect(x: outset.origin.x,
                                y: primaryHeight - outset.maxY,
                                width: outset.width,
                                height: outset.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        panel.setFrame(appKitRect, display: false)
        let bounds = CGRect(origin: .zero, size: appKitRect.size)

        // The gradient sits on a centered square covering the diagonal, so
        // the rainbow's rotation never exposes uncovered corners.
        let side = hypot(bounds.width, bounds.height)
        gradientLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let ring = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        maskLayer.frame = bounds
        maskLayer.lineWidth = borderWidth
        // Concentric with modern macOS window corners (~16pt): the stroke
        // centerline sits half the border width outside the window edge, so
        // its radius grows by the same amount to keep the curves parallel.
        let radius = 16 + borderWidth / 2
        maskLayer.path = CGPath(roundedRect: ring, cornerWidth: radius,
                                cornerHeight: radius, transform: nil)

        if appearance != currentAppearance {
            currentAppearance = appearance
            applyStyle(appearance)
        }

        CATransaction.commit()
        panel.orderFrontRegardless()
    }

    private func applyStyle(_ appearance: BorderAppearance) {
        gradientLayer.removeAnimation(forKey: "rainbow")

        switch appearance.animation {
        case .rainbow:
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
            let hues: [NSColor] = [.systemRed, .systemYellow, .systemGreen,
                                   .systemTeal, .systemBlue, .systemPurple,
                                   .systemRed]
            gradientLayer.colors = hues.map(\.cgColor)

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi
            spin.duration = 6.0 / max(appearance.speed, 0.05)
            spin.repeatCount = .infinity
            gradientLayer.add(spin, forKey: "rainbow")

        case .none:
            gradientLayer.type = .axial
            var colors = appearance.fill.colors.map {
                NSColor(red: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255,
                        blue: CGFloat($0.b) / 255, alpha: CGFloat($0.a) / 255).cgColor
            }
            if colors.count == 1 { colors.append(colors[0]) }
            gradientLayer.colors = colors

            // CSS-style angle: 0° points up, clockwise.
            let radians = Double(appearance.fill.angleDegrees) * .pi / 180
            let dx = sin(radians) / 2
            let dy = cos(radians) / 2
            gradientLayer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
            gradientLayer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}
