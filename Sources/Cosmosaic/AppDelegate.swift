import AppKit
import CosmosaicCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let windowManager = WindowManager()
    private let configManager = ConfigManager()
    private let hotkeyManager = HotkeyManager()
    private let onboarding = PermissionOnboarding()
    private var controller: TilingController!
    private var statusMenu: StatusMenu!
    private var borderOverlay: BorderOverlay!
    private var keybindingsModel: KeybindingsModel!
    private var keybindingsWindow: KeybindingsWindowController!
    private var focusFollowsMouse: FocusFollowsMouse!
    private let mouseTracker = MouseTracker()
    private let island = NotchIsland()
    private let media = MediaController()
    private var permissionGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = TilingController(windowManager: windowManager)
        statusMenu = StatusMenu(controller: controller, configManager: configManager)
        borderOverlay = BorderOverlay()
        keybindingsModel = KeybindingsModel(configManager: configManager)
        keybindingsWindow = KeybindingsWindowController(model: keybindingsModel)

        keybindingsModel.onRecordingStarted = { [weak self] in
            self?.hotkeyManager.suspend()
        }
        keybindingsModel.onRecordingEnded = { [weak self] in
            self?.hotkeyManager.resume()
        }
        statusMenu.onOpenKeybindings = { [weak self] in
            self?.keybindingsWindow.show()
        }
        keybindingsModel.onSetTilingEnabled = { [weak self] enabled in
            self?.controller.setPaused(!enabled)
        }
        windowManager.onWindowMoved = { [weak self] id in
            guard let self, id == self.windowManager.focusedID else { return }
            self.refreshBorder()
        }
        // The border glides with the focused window during animations.
        controller.animator.onFocusedFrame = { [weak self] frame in
            guard let self, !self.controller.paused,
                  let id = self.windowManager.focusedID,
                  !self.controller.state.isFloating(id),
                  self.controller.state.currentWorkspace.fullscreen != id else { return }
            self.borderOverlay.update(
                around: frame,
                appearance: BorderAppearance(general: self.controller.config.general))
        }
        // Drags and clicks reorder windows without any AX event; the mouse
        // tracker drives live border tracking and z-order re-assertion.
        mouseTracker.focusedElement = { [weak self] in
            guard let self, let id = self.windowManager.focusedID else { return nil }
            return self.windowManager.windows[id]?.element
        }
        mouseTracker.onDragTick = { [weak self] frame in
            guard let self, !self.controller.paused,
                  let id = self.windowManager.focusedID,
                  !self.controller.state.isFloating(id),
                  // No border in fullscreen — clicks emit stray drag ticks
                  // that would flash it for a frame.
                  self.controller.state.currentWorkspace.fullscreen != id else { return }
            self.borderOverlay.update(
                around: frame,
                appearance: BorderAppearance(general: self.controller.config.general))
        }
        mouseTracker.onSettled = { [weak self] in
            guard let self else { return }
            self.controller.raiseFloatingWindows()
            self.controller.enforceFullscreenDominance()
            self.refreshBorder()
        }

        focusFollowsMouse = FocusFollowsMouse(controller: controller)

        island.model.onPlayPause = { [weak self] in self?.media.playPause() }
        island.model.onNext = { [weak self] in self?.media.nextTrack() }
        island.model.onPrevious = { [weak self] in self?.media.previousTrack() }
        island.model.onSelectWorkspace = { [weak self] number in
            self?.controller.switchWorkspace(to: number)
        }
        media.onUpdate = { [weak self] nowPlaying in
            guard let self else { return }
            self.island.model.nowPlaying = nowPlaying
            self.island.noteContentChanged()
        }

        configManager.onConfigChanged = { [weak self] config in
            guard let self else { return }
            self.controller.apply(config: config)
            self.hotkeyManager.rebind(to: config.binds)
            self.statusMenu.refresh()
            self.keybindingsModel.refresh()
            self.focusFollowsMouse.setEnabled(self.permissionGranted && config.input.followMouse)
            self.island.setEnabled(config.island.enabled)
            if config.island.enabled { self.media.start() } else { self.media.stop() }
        }
        configManager.onError = { [weak self] _ in
            self?.statusMenu.refresh()
        }
        hotkeyManager.onDispatch = { [weak self] dispatcher in
            self?.controller.execute(dispatcher)
        }
        controller.onReloadRequested = { [weak self] in
            self?.configManager.load()
        }
        controller.onStateChanged = { [weak self] in
            guard let self else { return }
            self.statusMenu.refresh()
            self.keybindingsModel.setTilingPaused(self.controller.paused)
            self.island.model.workspace = self.controller.state.current
            self.island.model.occupiedWorkspaces = Set(
                self.controller.state.workspaces.compactMap {
                    $0.value.allWindows.isEmpty ? nil : $0.key
                })
            self.island.noteContentChanged()
            self.refreshBorder()
        }

        // Config (and the keybindings UI it feeds) needs no permissions —
        // load it immediately. Only window management waits for the grant.
        configManager.start()

        onboarding.ensurePermission { [weak self] in
            guard let self else { return }
            self.permissionGranted = true
            self.windowManager.start()
            self.mouseTracker.start()
            self.statusMenu.refresh()
            self.keybindingsModel.refresh()
            self.focusFollowsMouse.setEnabled(self.configManager.config.input.followMouse)
        }
    }

    private var borderRecheck: DispatchWorkItem?

    private func refreshBorder() {
        borderRecheck?.cancel()
        guard !controller.paused,
              let focusedID = windowManager.focusedID,
              let managed = windowManager.windows[focusedID],
              controller.state.workspace(of: focusedID) == controller.state.current,
              // Tiled windows only: floating windows are draggable and can
              // legitimately stack, which made their border glitchy.
              !controller.state.isFloating(focusedID),
              // No border in fullscreen (Hyprland behavior): the window spans
              // the whole tileable area, so an outset border would clip at
              // the screen edges.
              controller.state.currentWorkspace.fullscreen != focusedID,
              let frame = AX.frame(of: managed.element) else {
            borderOverlay.hide()
            return
        }
        // Never draw around a buried window — a border hovering over
        // whatever covers its window is worse than no border. But burial is
        // often transient (a fresh window or raise hasn't reached the
        // WindowServer's list yet), so recheck until it surfaces.
        guard AX.isFrameFrontmost(frame, pid: managed.pid) else {
            borderOverlay.hide()
            let work = DispatchWorkItem { [weak self] in self?.refreshBorder() }
            borderRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        borderOverlay.update(around: frame,
                             appearance: BorderAppearance(general: controller.config.general))
    }

    func applicationWillTerminate(_ notification: Notification) {
        borderOverlay.hide()
    }
}
