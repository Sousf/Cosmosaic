import AppKit
import QuartzCore

/// Animates window frames through AX at ~60fps with ease-in-out — the
/// float-over feel for swaps and fullscreen transitions. Scoped to one or
/// two windows at a time; whole-layout changes stay instant by design.
@MainActor
final class WindowAnimator {

    struct Item {
        let element: AXUIElement
        let from: CGRect
        let to: CGRect
        let isFocused: Bool
    }

    /// Interpolated frame of the focused item each tick (border glide).
    var onFocusedFrame: ((CGRect) -> Void)?

    private var timer: Timer?
    private var completion: (() -> Void)?
    private var items: [Item] = []

    var isAnimating: Bool { timer != nil }

    func animate(_ items: [Item], durationMs: Int, completion: @escaping () -> Void) {
        cancel()
        guard durationMs > 0, !items.isEmpty else {
            for item in items { AX.setFrame(item.element, to: item.to) }
            completion()
            return
        }
        self.items = items
        self.completion = completion
        let start = CACurrentMediaTime()
        let duration = Double(durationMs) / 1000.0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0,
                                     repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let progress = min(1, (CACurrentMediaTime() - start) / duration)
                let eased = Self.easeInOutCubic(progress)
                for item in self.items {
                    let frame = Self.lerp(item.from, item.to, eased)
                    AX.setFrame(item.element, to: frame)
                    if item.isFocused { self.onFocusedFrame?(frame) }
                }
                if progress >= 1 { self.finish() }
            }
        }
    }

    /// Stop without calling the completion — the caller is superseding the
    /// animation (usually with an instant relayout).
    func cancel() {
        timer?.invalidate()
        timer = nil
        completion = nil
        items = []
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
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
