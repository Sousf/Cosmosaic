import AppKit
import CosmosaicCore

typealias ScreenKey = UInt32

@MainActor
enum Screens {
    static func key(for screen: NSScreen) -> ScreenKey {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for key: ScreenKey) -> NSScreen? {
        NSScreen.screens.first { self.key(for: $0) == key } ?? NSScreen.main
    }

    /// The screen whose AX-space frame contains the point, else the main screen.
    static func screenContaining(axPoint: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if AX.axRect(fromAppKit: screen.frame).contains(axPoint) { return screen }
        }
        return NSScreen.main
    }
}

/// Pure bookkeeping for the nine emulated workspaces. No AX calls — the
/// tiling controller reads this state and applies it to real windows.
struct Workspace {
    var trees: [ScreenKey: LayoutTree] = [:]
    var floating: Set<WindowID> = []
    var fullscreen: WindowID?
    var lastFocused: WindowID?

    var allWindows: [WindowID] {
        trees.values.flatMap(\.windows) + Array(floating)
    }
}

@MainActor
final class WorkspaceState {
    private(set) var workspaces: [Int: Workspace]
    private(set) var current = 1
    /// window → workspace number
    private(set) var membership: [WindowID: Int] = [:]
    /// window → screen it tiles on
    private(set) var screenOf: [WindowID: ScreenKey] = [:]

    init() {
        workspaces = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, Workspace()) })
    }

    var currentWorkspace: Workspace { workspaces[current]! }

    func workspace(of id: WindowID) -> Int? { membership[id] }

    func switchTo(_ number: Int) {
        guard (1...9).contains(number) else { return }
        current = number
    }

    func add(_ id: WindowID, toWorkspace number: Int, screen: ScreenKey,
             floating: Bool, after focused: WindowID?) {
        remove(id)
        membership[id] = number
        screenOf[id] = screen
        if floating {
            workspaces[number]!.floating.insert(id)
        } else {
            workspaces[number]!.trees[screen, default: LayoutTree()]
                .insert(id, after: focused)
        }
    }

    func remove(_ id: WindowID) {
        guard let number = membership.removeValue(forKey: id) else { return }
        screenOf.removeValue(forKey: id)
        workspaces[number]!.floating.remove(id)
        if workspaces[number]!.fullscreen == id { workspaces[number]!.fullscreen = nil }
        if workspaces[number]!.lastFocused == id { workspaces[number]!.lastFocused = nil }
        for key in workspaces[number]!.trees.keys {
            workspaces[number]!.trees[key]!.remove(id)
            if workspaces[number]!.trees[key]!.isEmpty {
                workspaces[number]!.trees.removeValue(forKey: key)
            }
        }
    }

    func isFloating(_ id: WindowID) -> Bool {
        guard let number = membership[id] else { return false }
        return workspaces[number]!.floating.contains(id)
    }

    func setFloating(_ id: WindowID, _ floating: Bool, after focused: WindowID?) {
        guard let number = membership[id], let screen = screenOf[id] else { return }
        if floating {
            for key in workspaces[number]!.trees.keys {
                workspaces[number]!.trees[key]!.remove(id)
                if workspaces[number]!.trees[key]!.isEmpty {
                    workspaces[number]!.trees.removeValue(forKey: key)
                }
            }
            workspaces[number]!.floating.insert(id)
        } else {
            workspaces[number]!.floating.remove(id)
            workspaces[number]!.trees[screen, default: LayoutTree()]
                .insert(id, after: focused)
        }
    }

    func setFullscreen(_ id: WindowID?, inWorkspace number: Int) {
        workspaces[number]?.fullscreen = id
    }

    func setLastFocused(_ id: WindowID, inWorkspace number: Int) {
        workspaces[number]?.lastFocused = id
    }

    func swapInTree(_ a: WindowID, _ b: WindowID) {
        guard let number = membership[a], membership[b] == number,
              let screen = screenOf[a], screenOf[b] == screen else { return }
        workspaces[number]!.trees[screen]?.swap(a, b)
    }

    func resizeInTree(_ id: WindowID, dx: Int, dy: Int, in rect: CGRect, gaps: Gaps) {
        guard let number = membership[id], let screen = screenOf[id] else { return }
        workspaces[number]!.trees[screen]?.resize(id, dx: dx, dy: dy, in: rect, gaps: gaps)
    }
}
