import CoreGraphics

/// Pure directional geometry over window frames. Frames use top-left-origin
/// screen coordinates with y increasing downward (the AX convention).
public enum LayoutGeometry {

    /// The window adjacent to `id` in `direction`: nearest edge first, then
    /// largest perpendicular overlap, then topmost/leftmost. Windows with no
    /// perpendicular overlap (diagonal neighbors) are never returned.
    public static func neighbor(of id: WindowID, direction: Direction,
                                in frames: [WindowID: CGRect]) -> WindowID? {
        guard let focused = frames[id] else { return nil }

        struct Candidate {
            let id: WindowID
            let distance: CGFloat
            let overlap: CGFloat
            let position: CGFloat
        }

        var candidates: [Candidate] = []
        for (other, frame) in frames where other != id {
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case .left:
                distance = focused.minX - frame.maxX
                overlap = verticalOverlap(focused, frame)
            case .right:
                distance = frame.minX - focused.maxX
                overlap = verticalOverlap(focused, frame)
            case .up:
                distance = focused.minY - frame.maxY
                overlap = horizontalOverlap(focused, frame)
            case .down:
                distance = frame.minY - focused.maxY
                overlap = horizontalOverlap(focused, frame)
            }
            guard distance >= 0, overlap > 0 else { continue }
            let position = (direction == .left || direction == .right) ? frame.minY : frame.minX
            candidates.append(Candidate(id: other, distance: distance,
                                        overlap: overlap, position: position))
        }

        return candidates.min { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            if a.overlap != b.overlap { return a.overlap > b.overlap }
            return a.position < b.position
        }?.id
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    private static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }
}

extension LayoutTree {

    /// Exchange the tree positions of two windows.
    public mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let root, contains(a), contains(b), a != b else { return }
        self.root = Self.swapping(root, a, b)
    }

    private static func swapping(_ node: Node, _ a: WindowID, _ b: WindowID) -> Node {
        switch node {
        case .leaf(a): return .leaf(b)
        case .leaf(b): return .leaf(a)
        case .leaf: return node
        case .split(let ratio, let first, let second):
            return .split(ratio: ratio,
                          first: swapping(first, a, b),
                          second: swapping(second, a, b))
        }
    }

    /// Grow `id`'s region by `dx`/`dy` pixels by adjusting the ratio of the
    /// deepest ancestor split along each axis. Ratios clamp to 0.1...0.9.
    public mutating func resize(_ id: WindowID, dx: Int, dy: Int,
                                in rect: CGRect, gaps: Gaps) {
        guard let root, contains(id) else { return }
        let outer = CGFloat(gaps.outer)
        var handledH = dx == 0
        var handledV = dy == 0
        self.root = Self.resizing(root, region: rect.insetBy(dx: outer, dy: outer),
                                  id: id, dx: CGFloat(dx), dy: CGFloat(dy),
                                  inner: CGFloat(gaps.inner),
                                  handledH: &handledH, handledV: &handledV).node
    }

    private static func resizing(_ node: Node, region: CGRect, id: WindowID,
                                 dx: CGFloat, dy: CGFloat, inner: CGFloat,
                                 handledH: inout Bool, handledV: inout Bool)
        -> (node: Node, found: Bool) {
        switch node {
        case .leaf(id):
            return (node, true)
        case .leaf:
            return (node, false)
        case .split(var ratio, let first, let second):
            let (rectA, rectB) = divide(region, ratio: ratio, inner: inner)
            let horizontal = region.width >= region.height
            let available = (horizontal ? region.width : region.height) - inner

            let resizedFirst = resizing(first, region: rectA, id: id, dx: dx, dy: dy,
                                        inner: inner, handledH: &handledH, handledV: &handledV)
            let resizedSecond = resizing(second, region: rectB, id: id, dx: dx, dy: dy,
                                         inner: inner, handledH: &handledH, handledV: &handledV)
            let found = resizedFirst.found || resizedSecond.found

            if found, available > 0 {
                // The deepest qualifying ancestor adjusts first and marks the
                // axis handled; shallower ancestors then leave it alone.
                let growFirst: CGFloat = resizedFirst.found ? 1 : -1
                if horizontal, !handledH {
                    ratio = clampRatio(ratio + growFirst * dx / available)
                    handledH = true
                } else if !horizontal, !handledV {
                    ratio = clampRatio(ratio + growFirst * dy / available)
                    handledV = true
                }
            }
            return (.split(ratio: ratio, first: resizedFirst.node, second: resizedSecond.node), found)
        }
    }

    private static func clampRatio(_ ratio: Double) -> Double {
        min(0.9, max(0.1, ratio))
    }
}
