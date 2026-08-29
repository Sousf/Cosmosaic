import AppKit
import ApplicationServices
import QuartzCore

/// Animates window frames through AX, paced by a display link (120Hz on
/// ProMotion) with ease-in-out. The link only computes frames; the blocking
/// AX writes run on per-window background queues with latest-frame
/// coalescing, so a slow app drops its own frames instead of stalling the
/// other windows or the tick loop.
@MainActor
final class WindowAnimator: NSObject {

    struct Item {
        let element: AXUIElement
        let from: CGRect
        let to: CGRect
        let isFocused: Bool

        var resizes: Bool {
            abs(from.width - to.width) > 0.5 || abs(from.height - to.height) > 0.5
        }
    }

    /// AXUIElement is a thread-safe CFType; this wrapper carries it into the
    /// writer queues past Sendable checking.
    private struct ElementHandle: @unchecked Sendable {
        let element: AXUIElement
    }

    @MainActor
    private final class ItemState {
        let item: Item
        let queue: DispatchQueue
        var inFlight = false
        var latest: CGRect

        init(item: Item, index: Int) {
            self.item = item
            self.latest = item.from
            self.queue = DispatchQueue(label: "cosmosaic.animator.\(index)",
                                       qos: .userInteractive)
        }
    }

    /// Interpolated frame of the focused item each tick (border glide).
    var onFocusedFrame: ((CGRect) -> Void)?

    private var displayLink: CADisplayLink?
    private var completion: (() -> Void)?
    private var states: [ItemState] = []
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
        states = items.enumerated().map { ItemState(item: $1, index: $0) }
        self.completion = completion
        startTime = CACurrentMediaTime()
        duration = Double(durationMs) / 1000.0

        let link = (NSScreen.main ?? NSScreen.screens.first)?
            .displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        displayLink = link
        if link == nil {
            for item in items { AX.setFrame(item.element, to: item.to) }
            finish()
        }
    }

    @objc private func tick() {
        MainActor.assumeIsolated {
            let progress = min(1, (CACurrentMediaTime() - startTime) / duration)
            let eased = Self.easeInOutCubic(progress)
            for state in states {
                let frame = Self.lerp(state.item.from, state.item.to, eased)
                state.latest = frame
                if state.item.isFocused { onFocusedFrame?(frame) }
                dispatchWrite(state)
            }
            if progress >= 1 { finish() }
        }
    }

    /// Send the newest frame to the window's writer queue unless a write is
    /// already in flight — the next tick delivers the newer frame instead.
    private func dispatchWrite(_ state: ItemState) {
        guard !state.inFlight else { return }
        state.inFlight = true
        let handle = ElementHandle(element: state.item.element)
        let frame = state.latest
        let resizes = state.item.resizes
        state.queue.async {
            Self.applyFrame(handle, frame: frame, resizes: resizes)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { state.inFlight = false }
            }
        }
    }

    /// Raw AX writes, callable off the main actor.
    private nonisolated static func applyFrame(_ handle: ElementHandle,
                                               frame: CGRect, resizes: Bool) {
        var origin = frame.origin
        var size = frame.size
        if resizes, let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(handle.element,
                                         kAXSizeAttribute as CFString, sizeValue)
        }
        if let positionValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(handle.element,
                                         kAXPositionAttribute as CFString, positionValue)
        }
    }

    /// Stop without calling the completion — the caller is superseding the
    /// animation (usually with an instant relayout). Drains in-flight writes
    /// first so a stale interpolated frame can't land after the caller's.
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        completion = nil
        for state in states { state.queue.sync { } }
        states = []
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        // Final exact frames go through each window's own queue — serialized
        // behind any in-flight write — with the clamp-proof full sequence.
        // The completion fires only after every queue drains, so nothing
        // stale can overwrite the landing.
        let group = DispatchGroup()
        for state in states {
            let handle = ElementHandle(element: state.item.element)
            let target = state.item.to
            group.enter()
            state.queue.async {
                Self.applyFinalFrame(handle, frame: target)
                group.leave()
            }
        }
        states = []
        let done = completion
        completion = nil
        group.notify(queue: .main) { done?() }
    }

    /// Robust landing: size → position → size, matching AX.setFrame's dance
    /// for apps that clamp position against their current size.
    private nonisolated static func applyFinalFrame(_ handle: ElementHandle,
                                                    frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(handle.element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(handle.element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(handle.element, kAXSizeAttribute as CFString, sizeValue)
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
