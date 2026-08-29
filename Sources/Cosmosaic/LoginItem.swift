import ServiceManagement

/// Launch-at-login via SMAppService: the system persists the setting and
/// shows it in System Settings › General › Login Items.
@MainActor
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Cosmosaic: launch-at-login change failed: \(error)")
            return false
        }
    }
}
