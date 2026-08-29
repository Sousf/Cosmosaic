import AppKit
import QuartzCore

/// Animates window frames through AX, paced by a display link (120Hz on
/// ProMotion) with ease-in-out — the float-over feel for swaps and
/// fullscreen transitions. Scoped to one or two windows at a time;
/// whole-layout changes stay instant by design.
@MainActor
final class WindowAnimator: NSObject {

    struct Item {
        let element: AXUIElement
        let from: CGRect
        let to: CGRect
        let isFocused: Bool

        /// Same-size moves need only one AX call per tick.
        var resizes: Bool {
            abs(from.width - to.width) > 0.5 || abs(from.height - to.height) > 0.5
        }
    }

    /// Interpolated frame of the focused item each tick (border glide).
    var onFocusedFrame: ((CGRect) -> Void)?

    private var displayLink: CADisplayLink?
    private var completion: (() -> Void)?
    private var items: [Item] = []
    private var startTime: CFTimeInterval = 0
    private var duration: Double = 0

    var isAnimating: Bool { displayLink != nil }

    func animate(_ items: [Item], durationMs: Int, completion: @escaping () -> Void) {
        cancel()
        guard durationMs > 0, !items.isEmpty else {
            for item in items { AX.setFrame(item.element, to: item.to) }
            completion()
            return
        }
        self.items = items
        self.completion = completion
        startTime = CACurrentMediaTime()
        duration = Double(durationMs) / 1000.0

        let link = (NSScreen.main ?? NSScreen.screens.first)?
            .displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        displayLink = link
        if link == nil {
            // No display link available: land instantly rather than hang.
            for item in items { AX.setFrame(item.element, to: item.to) }
            finish()
        }
    }

    @objc private func tick() {
        MainActor.assumeIsolated {
            let progress = min(1, (CACurrentMediaTime() - startTime) / duration)
            let eased = Self.easeInOutCubic(progress)
            for item in items {
                let frame = Self.lerp(item.from, item.to, eased)
                // Slim writes during flight; the finish sets exact frames.
                if item.resizes {
                    AX.setSize(item.element, to: frame.size)
                }
                AX.setPosition(item.element, to: frame.origin)
                if item.isFocused { onFocusedFrame?(frame) }
            }
            if progress >= 1 { finish() }
        }
    }

    /// Stop without calling the completion — the caller is superseding the
    /// animation (usually with an instant relayout).
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        completion = nil
        items = []
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        for item in items { AX.setFrame(item.element, to: item.to) }
        items = []
        let done = completion
        completion = nil
        done?()
    }

    private static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.origin.x + (b.origin.x - a.origin.x) * t,
               y: a.origin.y + (b.origin.y - a.origin.y) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}
