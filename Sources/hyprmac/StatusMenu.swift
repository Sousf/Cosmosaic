import AppKit

/// Menu bar item: shows the current workspace number and offers the few
/// controls that shouldn't require editing the config file.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: TilingController
    private let configManager: ConfigManager

    init(controller: TilingController, configManager: ConfigManager) {
        self.controller = controller
        self.configManager = configManager
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        let workspace = controller.state.current
        let badge = controller.paused ? "⏸" : "◫"
        statusItem.button?.title = "\(badge) \(workspace)"
        if configManager.lastError != nil {
            statusItem.button?.title = "⚠︎ \(workspace)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: "hyprmac — workspace \(controller.state.current)",
                     action: nil, keyEquivalent: "")

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
