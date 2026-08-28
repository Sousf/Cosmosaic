import AppKit
import HyprmacCore

/// Orchestrates everything: reacts to window events, keeps workspace state,
/// computes layouts, and applies frames through AX. All dispatcher execution
/// lands here.
@MainActor
final class TilingController {

    let windowManager: WindowManager
    let state = WorkspaceState()
    private(set) var config = Config()
    private(set) var paused = false

    var onReloadRequested: (() -> Void)?
    var onStateChanged: (() -> Void)?  // menu bar + border overlay refresh

    private var gaps: Gaps {
        Gaps(inner: config.general.gapsIn, outer: config.general.gapsOut)
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        windowManager.onWindowAdded = { [weak self] managed in self?.windowAdded(managed) }
        windowManager.onWindowRemoved = { [weak self] id in self?.windowRemoved(id) }
        windowManager.onFocusChanged = { [weak self] id in self?.focusChanged(id) }
    }

    func apply(config: Config) {
        self.config = config
        relayout()
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if !paused { relayout() }
        onStateChanged?()
    }

    // MARK: - Window events

    private func windowAdded(_ managed: WindowManager.Managed) {
        guard !paused else { return }
        let floating = shouldFloat(appName: managed.appName)
        let frame = AX.frame(of: managed.element) ?? .zero
        let screen = Screens.screenContaining(axPoint: CGPoint(x: frame.midX, y: frame.midY))
            ?? NSScreen.main
        guard let screen else { return }

        state.add(managed.id, toWorkspace: state.current,
                  screen: Screens.key(for: screen),
                  floating: floating, after: windowManager.focusedID)
        relayout()
    }

    private func windowRemoved(_ id: WindowID) {
        state.remove(id)
        relayout()
    }

    private func focusChanged(_ id: WindowID?) {
        guard let id else {
            onStateChanged?()
            return
        }
        // Focusing a hidden-workspace window (Cmd-Tab, Dock) follows it there.
        if let workspace = state.workspace(of: id), workspace != state.current {
            switchWorkspace(to: workspace)
        } else {
            if let workspace = state.workspace(of: id) {
                state.setLastFocused(id, inWorkspace: workspace)
            }
            onStateChanged?()
        }
    }

    private func shouldFloat(appName: String) -> Bool {
        for rule in config.windowRules where rule.effect == .float {
            if appName.range(of: rule.appPattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Layout

    /// Computed tiled frames for the current workspace, keyed by window.
    private func currentTiledFrames() -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        for (screenKey, tree) in state.currentWorkspace.trees {
            guard let screen = Screens.screen(for: screenKey) else { continue }
            let area = AX.tileableArea(of: screen)
            frames.merge(tree.frames(in: area, gaps: gaps)) { a, _ in a }
        }
        return frames
    }

    func relayout() {
        guard !paused else { return }

        let workspace = state.currentWorkspace
        for (id, frame) in currentTiledFrames() {
            guard let managed = windowManager.windows[id] else { continue }
            AX.setFrame(managed.element, to: frame)
        }

        // Fullscreen window covers its whole screen, above the tiled layer.
        if let fullscreenID = workspace.fullscreen,
           let managed = windowManager.windows[fullscreenID],
           let screenKey = state.screenOf[fullscreenID],
           let screen = Screens.screen(for: screenKey) {
            AX.setFrame(managed.element, to: AX.tileableArea(of: screen))
            AX.raise(managed.element)
        }

        onStateChanged?()
    }

    // MARK: - Workspace switching

    func switchWorkspace(to number: Int) {
        guard (1...9).contains(number), number != state.current else { return }

        let leaving = state.currentWorkspace.allWindows
        state.switchTo(number)

        for id in leaving {
            guard let managed = windowManager.windows[id] else { continue }
            park(managed)
        }
        relayout()
        for id in state.currentWorkspace.allWindows {
            guard let managed = windowManager.windows[id] else { continue }
            AX.raise(managed.element)
        }

        let target = state.currentWorkspace.lastFocused
            ?? state.currentWorkspace.allWindows.first
        if let target, let managed = windowManager.windows[target] {
            AX.focus(managed.element, pid: managed.pid)
        }
        onStateChanged?()
    }

    /// Hide a window by parking it at the bottom-right corner of its screen
    /// with only a sliver on screen (macOS refuses fully off-screen positions).
    private func park(_ managed: WindowManager.Managed) {
        let screenKey = state.screenOf[managed.id]
        let screen = screenKey.flatMap { Screens.screen(for: $0) } ?? NSScreen.main
        guard let screen else { return }
        let area = AX.axRect(fromAppKit: screen.frame)
        AX.setPosition(managed.element, to: CGPoint(x: area.maxX - 2, y: area.maxY - 2))
    }

    func moveToWorkspace(_ number: Int, id: WindowID) {
        guard (1...9).contains(number), number != state.workspace(of: id),
              let managed = windowManager.windows[id],
              let screenKey = state.screenOf[id] else { return }

        let floating = state.isFloating(id)
        state.remove(id)
        state.add(id, toWorkspace: number, screen: screenKey,
                  floating: floating, after: nil)
        park(managed)
        relayout()

        // Focus falls to what remains on the current workspace.
        if let next = state.currentWorkspace.lastFocused
            ?? state.currentWorkspace.allWindows.first,
           let nextManaged = windowManager.windows[next] {
            AX.focus(nextManaged.element, pid: nextManaged.pid)
        }
    }

    // MARK: - Dispatchers

    func execute(_ dispatcher: Dispatcher) {
        switch dispatcher {
        case .exec(let command):
            run(command: command)

        case .killactive:
            guard let focused = focusedManaged() else { return }
            AX.close(focused.element)

        case .movefocus(let direction):
            moveFocus(direction)

        case .movewindow(let direction):
            moveWindow(direction)

        case .workspace(let number):
            switchWorkspace(to: number)

        case .movetoworkspace(let number):
            guard let focused = focusedManaged() else { return }
            moveToWorkspace(number, id: focused.id)

        case .togglefloating:
            guard let focused = focusedManaged() else { return }
            let nowFloating = !state.isFloating(focused.id)
            state.setFloating(focused.id, nowFloating, after: nil)
            relayout()

        case .fullscreen:
            guard let focused = focusedManaged(),
                  let workspace = state.workspace(of: focused.id) else { return }
            let current = state.workspaces[workspace]?.fullscreen
            state.setFullscreen(current == focused.id ? nil : focused.id,
                                inWorkspace: workspace)
            relayout()

        case .resizeactive(let dx, let dy):
            guard let focused = focusedManaged(),
                  let screenKey = state.screenOf[focused.id],
                  let screen = Screens.screen(for: screenKey) else { return }
            state.resizeInTree(focused.id, dx: dx, dy: dy,
                               in: AX.tileableArea(of: screen), gaps: gaps)
            relayout()

        case .reload:
            onReloadRequested?()
        }
    }

    private func focusedManaged() -> WindowManager.Managed? {
        windowManager.focusedID.flatMap { windowManager.windows[$0] }
    }

    private func run(command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
    }

    private func moveFocus(_ direction: Direction) {
        guard let focusedID = windowManager.focusedID else {
            // Nothing focused: focus anything on the current workspace.
            if let id = state.currentWorkspace.allWindows.first,
               let managed = windowManager.windows[id] {
                AX.focus(managed.element, pid: managed.pid)
            }
            return
        }
        var frames = currentTiledFrames()
        for id in state.currentWorkspace.floating {
            guard let managed = windowManager.windows[id],
                  let frame = AX.frame(of: managed.element) else { continue }
            frames[id] = frame
        }
        guard let neighbor = LayoutGeometry.neighbor(of: focusedID, direction: direction,
                                                     in: frames),
              let managed = windowManager.windows[neighbor] else { return }
        AX.focus(managed.element, pid: managed.pid)
    }

    private func moveWindow(_ direction: Direction) {
        guard let focusedID = windowManager.focusedID,
              !state.isFloating(focusedID) else { return }
        let frames = currentTiledFrames()
        guard let neighbor = LayoutGeometry.neighbor(of: focusedID, direction: direction,
                                                     in: frames) else { return }
        state.swapInTree(focusedID, neighbor)
        relayout()
    }
}
