import CoreGraphics

/// Opaque handle for a managed window, assigned by the window manager.
public typealias WindowID = Int

public struct Gaps: Sendable, Equatable {
    public var inner: Int
    public var outer: Int

    public init(inner: Int, outer: Int) {
        self.inner = inner
        self.outer = outer
    }
}

/// Dwindle BSP tree: each insert splits the focused leaf. Split orientation is
/// not stored — it is derived from the region's aspect at layout time (wider →
/// side-by-side, taller → stacked), which yields the classic Hyprland spiral
/// and adapts automatically when the screen or ancestor ratios change.
public struct LayoutTree: Sendable, Equatable {

    indirect enum Node: Sendable, Equatable {
        case leaf(WindowID)
        case split(ratio: Double, first: Node, second: Node)
    }

    var root: Node?

    public init() {}

    public var isEmpty: Bool { root == nil }

    /// All windows in in-order traversal (insertion/spatial order).
    public var windows: [WindowID] {
        guard let root else { return [] }
        var result: [WindowID] = []
        Self.collectLeaves(root, into: &result)
        return result
    }

    public func contains(_ id: WindowID) -> Bool {
        windows.contains(id)
    }

    public mutating func insert(_ id: WindowID, after focused: WindowID?) {
        guard let root else {
            self.root = .leaf(id)
            return
        }
        let target = focused.flatMap { contains($0) ? $0 : nil } ?? windows.last!
        self.root = Self.splitting(root, at: target, adding: id)
    }

    public mutating func remove(_ id: WindowID) {
        guard let root else { return }
        self.root = Self.removing(root, id: id)
    }

    public func frames(in rect: CGRect, gaps: Gaps) -> [WindowID: CGRect] {
        guard let root else { return [:] }
        var result: [WindowID: CGRect] = [:]
        let outer = CGFloat(gaps.outer)
        Self.layout(root, in: rect.insetBy(dx: outer, dy: outer),
                    inner: CGFloat(gaps.inner), into: &result)
        return result
    }

    // MARK: - Node algorithms

    private static func collectLeaves(_ node: Node, into result: inout [WindowID]) {
        switch node {
        case .leaf(let id):
            result.append(id)
        case .split(_, let first, let second):
            collectLeaves(first, into: &result)
            collectLeaves(second, into: &result)
        }
    }

    private static func splitting(_ node: Node, at target: WindowID, adding id: WindowID) -> Node {
        switch node {
        case .leaf(target):
            return .split(ratio: 0.5, first: .leaf(target), second: .leaf(id))
        case .leaf:
            return node
        case .split(let ratio, let first, let second):
            return .split(ratio: ratio,
                          first: splitting(first, at: target, adding: id),
                          second: splitting(second, at: target, adding: id))
        }
    }

    private static func removing(_ node: Node, id: WindowID) -> Node? {
        switch node {
        case .leaf(id):
            return nil
        case .leaf:
            return node
        case .split(let ratio, let first, let second):
            switch (removing(first, id: id), removing(second, id: id)) {
            case (nil, let sibling?), (let sibling?, nil):
                return sibling
            case (let newFirst?, let newSecond?):
                return .split(ratio: ratio, first: newFirst, second: newSecond)
            case (nil, nil):
                return nil
            }
        }
    }

    private static func layout(_ node: Node, in rect: CGRect,
                               inner: CGFloat, into result: inout [WindowID: CGRect]) {
        switch node {
        case .leaf(let id):
            result[id] = rect
        case .split(let ratio, let first, let second):
            let (rectA, rectB) = divide(rect, ratio: ratio, inner: inner)
            layout(first, in: rectA, inner: inner, into: &result)
            layout(second, in: rectB, inner: inner, into: &result)
        }
    }

    static func divide(_ rect: CGRect, ratio: Double, inner: CGFloat) -> (CGRect, CGRect) {
        if rect.width >= rect.height {
            let available = rect.width - inner
            let firstWidth = (available * ratio).rounded()
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + inner, y: rect.minY,
                       width: available - firstWidth, height: rect.height)
            )
        } else {
            let available = rect.height - inner
            let firstHeight = (available * ratio).rounded()
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
                CGRect(x: rect.minX, y: rect.minY + firstHeight + inner,
                       width: rect.width, height: available - firstHeight)
            )
        }
    }
}
