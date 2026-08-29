import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar agent: no Dock icon, no app menu.
app.setActivationPolicy(.accessory)
app.run()
