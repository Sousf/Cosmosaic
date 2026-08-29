import AppKit
import HyprmacCore

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
    private var permissionGranted = false
    private var dragTimer: Timer?

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
            // AX move events arrive too sparsely to track a live drag; poll
            // at 60 Hz while the button stays down so the border keeps up.
            if NSEvent.pressedMouseButtons != 0 {
                self.startDragTracking()
            }
        }

        focusFollowsMouse = FocusFollowsMouse(controller: controller)

        configManager.onConfigChanged = { [weak self] config in
            guard let self else { return }
            self.controller.apply(config: config)
            self.hotkeyManager.rebind(to: config.binds)
            self.statusMenu.refresh()
            self.keybindingsModel.refresh()
            self.focusFollowsMouse.setEnabled(self.permissionGranted && config.input.followMouse)
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
            self.refreshBorder()
        }

        // Config (and the keybindings UI it feeds) needs no permissions —
        // load it immediately. Only window management waits for the grant.
        configManager.start()

        onboarding.ensurePermission { [weak self] in
            guard let self else { return }
            self.permissionGranted = true
            self.windowManager.start()
            self.statusMenu.refresh()
            self.keybindingsModel.refresh()
            self.focusFollowsMouse.setEnabled(self.configManager.config.input.followMouse)
        }
    }

    private func startDragTracking() {
        guard dragTimer == nil else { return }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0,
                                         repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshBorder()
                if NSEvent.pressedMouseButtons == 0 {
                    self.dragTimer?.invalidate()
                    self.dragTimer = nil
                    self.refreshBorder()
                }
            }
        }
    }

    private func refreshBorder() {
        guard !controller.paused,
              let focusedID = windowManager.focusedID,
              let managed = windowManager.windows[focusedID],
              controller.state.workspace(of: focusedID) == controller.state.current,
              let frame = AX.frame(of: managed.element) else {
            borderOverlay.hide()
            return
        }
        borderOverlay.update(around: frame,
                             color: controller.config.general.activeBorderColor,
                             width: controller.config.general.borderSize)
    }

    func applicationWillTerminate(_ notification: Notification) {
        borderOverlay.hide()
    }
}
