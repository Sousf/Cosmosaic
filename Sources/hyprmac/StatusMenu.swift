import AppKit

/// Menu bar item: shows the current workspace number and offers the few
/// controls that shouldn't require editing the config file.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: TilingController
    private let configManager: ConfigManager
    private let menu = NSMenu()

    /// Left-click on the icon opens the keybindings window.
    var onOpenKeybindings: (() -> Void)?

    init(controller: TilingController, configManager: ConfigManager) {
        self.controller = controller
        self.configManager = configManager
        super.init()

        menu.delegate = self
        // The menu is attached only for right-clicks (see statusClicked);
        // left-click runs the button action instead.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            onOpenKeybindings?()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach again so the next left-click reaches statusClicked.
        statusItem.menu = nil
    }

    func refresh() {
        guard AX.isTrusted else {
            statusItem.button?.title = "◫ ⚠"
            return
        }
        let workspace = controller.state.current
        let badge = controller.paused ? "⏸" : "◫"
        statusItem.button?.title = "\(badge) \(workspace)"
        if configManager.lastError != nil {
            statusItem.button?.title = "⚠︎ \(workspace)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Before the Accessibility grant nothing is running; say exactly that
        // instead of offering controls that would mislead.
        guard AX.isTrusted else {
            menu.addItem(withTitle: "Waiting for Accessibility permission…",
                         action: nil, keyEquivalent: "")
            let open = NSMenuItem(title: "Open Accessibility Settings",
                                  action: #selector(openAccessibilitySettings),
                                  keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit hyprmac", action: #selector(quit),
                                  keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            return
        }

        menu.addItem(withTitle: "hyprmac — workspace \(controller.state.current)",
                     action: nil, keyEquivalent: "")

        let keybindings = NSMenuItem(title: "Keybindings…",
                                     action: #selector(openKeybindings), keyEquivalent: "")
        keybindings.target = self
        menu.addItem(keybindings)

        if let error = configManager.lastError {
            let item = NSMenuItem(title: "Config error: \(error.description)",
                                  action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: "⚠︎ \(error.description)",
                attributes: [.foregroundColor: NSColor.systemRed])
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: controller.paused ? "Resume Tiling" : "Pause Tiling",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let reload = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig),
                                keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let edit = NSMenuItem(title: "Open Config File", action: #selector(openConfig),
                              keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit hyprmac", action: #selector(quit),
                              keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openKeybindings() {
        onOpenKeybindings?()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func togglePause() {
        controller.setPaused(!controller.paused)
    }

    @objc private func reloadConfig() {
        configManager.load()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configManager.configURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
