import AppKit

/// First-launch flow: explain the Accessibility permission, deep-link to the
/// right Settings pane, and poll until it's granted.
@MainActor
final class PermissionOnboarding {

    private var window: NSWindow?
    private var pollTimer: Timer?
    private var onGranted: (() -> Void)?

    /// Runs `onGranted` immediately if already trusted, otherwise after the
    /// user grants the permission.
    func ensurePermission(onGranted: @escaping () -> Void) {
        if AX.isTrusted {
            onGranted()
            return
        }
        self.onGranted = onGranted
        AX.promptForTrust()
        showExplainer()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AX.isTrusted else { return }
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.window?.close()
                self.window = nil
                self.onGranted?()
                self.onGranted = nil
            }
        }
    }

    private func showExplainer() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Cosmosaic"
        window.center()
        window.isReleasedWhenClosed = false
        // Stay above normal windows so this can't get buried and forgotten.
        window.level = .floating

        let text = NSTextField(wrappingLabelWithString: """
        Cosmosaic tiles your windows the way Hyprland does on Linux. To move and \
        resize other apps' windows, macOS requires you to grant it the \
        Accessibility permission:

        1. Open System Settings → Privacy & Security → Accessibility
        2. Enable Cosmosaic in the list

        Already enabled but this window is still here? The app was rebuilt, \
        which invalidates the old grant even though the switch still shows on. \
        Remove Cosmosaic from the list with the − button, then relaunch the app \
        and grant it again.

        This window closes by itself once the permission is granted.
        """)
        text.frame = NSRect(x: 24, y: 70, width: 412, height: 230)

        let button = NSButton(title: "Open Accessibility Settings",
                              target: self, action: #selector(openSettings))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 24, y: 24, width: 240, height: 32)

        window.contentView?.addSubview(text)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    @objc private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
