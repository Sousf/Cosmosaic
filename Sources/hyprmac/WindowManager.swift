import AppKit
import ApplicationServices
import HyprmacCore

/// Discovers windows and watches AX events. Owns the WindowID registry and
/// emits add/remove/focus events; it makes no layout decisions itself.
@MainActor
final class WindowManager {

    struct Managed {
        let id: WindowID
        let element: AXUIElement
        let pid: pid_t
        let appName: String
    }

    private(set) var windows: [WindowID: Managed] = [:]
    private(set) var focusedID: WindowID?
    private var nextID: WindowID = 1
    private var observers: [pid_t: AXObserver] = [:]

    var onWindowAdded: ((Managed) -> Void)?
    var onWindowRemoved: ((WindowID) -> Void)?
    var onFocusChanged: ((WindowID?) -> Void)?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.adopt(app: app, retryDelays: [0.5, 1.5, 3.0]) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.dropApp(pid: app.processIdentifier) }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.syncFocus(pid: app.processIdentifier) }
        }

        for app in NSWorkspace.shared.runningApplications {
            adopt(app: app, retryDelays: [0])
        }
    }

    private func shouldManage(app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && !app.isTerminated
    }

    private func adopt(app: NSRunningApplication, retryDelays: [Double]) {
        guard shouldManage(app: app) else { return }
        let pid = app.processIdentifier
        attachObserver(pid: pid)
        // Apps publish their windows some time after launch; rescan a few times.
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.scanWindows(of: app)
            }
        }
    }

    private func scanWindows(of app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        for element in AX.windows(ofPID: app.processIdentifier)
        where AX.isStandardWindow(element) && findID(of: element) == nil {
            register(element: element, pid: app.processIdentifier,
                     appName: app.localizedName ?? "?")
        }
    }

    private func register(element: AXUIElement, pid: pid_t, appName: String) {
        let managed = Managed(id: nextID, element: element, pid: pid, appName: appName)
        nextID += 1
        windows[managed.id] = managed
        watchWindowElement(element, pid: pid)
        onWindowAdded?(managed)
        // Creation and focus-change events race in either order for brand-new
        // windows; if this window is already the app's focused one, adopt the
        // focus that would otherwise have been dropped.
        if let focusedElement = AX.focusedWindow(ofPID: pid),
           CFEqual(focusedElement, element) {
            setFocused(managed.id)
        }
    }

    /// Register an element we haven't seen if it's a tileable window.
    private func registerIfStandard(_ element: AXUIElement) {
        guard AX.isStandardWindow(element), findID(of: element) == nil else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        register(element: element, pid: pid, appName: appName)
    }

    private func unregister(_ id: WindowID) {
        guard windows.removeValue(forKey: id) != nil else { return }
        if focusedID == id { focusedID = nil }
        onWindowRemoved?(id)
    }

    func findID(of element: AXUIElement) -> WindowID? {
        windows.first { CFEqual($0.value.element, element) }?.key
    }

    // MARK: - Focus

    private func syncFocus(pid: pid_t) {
        guard let element = AX.focusedWindow(ofPID: pid) else { return }
        setFocused(findID(of: element))
    }

    private func setFocused(_ id: WindowID?) {
        guard focusedID != id else { return }
        focusedID = id
        onFocusChanged?(id)
    }

    // MARK: - AX observers

    private func attachObserver(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated {
                manager.handleAXEvent(name: name, element: element)
            }
        }, &observer)
        guard result == .success, let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .defaultMode)
        observers[pid] = observer
    }

    /// Register per-window notifications (destroy, minimize) on a window element.
    private func watchWindowElement(_ element: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXUIElementDestroyedNotification,
                             kAXWindowMiniaturizedNotification,
                             kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, element, notification as CFString, refcon)
        }
    }

    private func handleAXEvent(name: String, element: AXUIElement) {
        switch name {
        case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
            registerIfStandard(element)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if let id = findID(of: element) { unregister(id) }

        case kAXFocusedWindowChangedNotification:
            if let id = findID(of: element) {
                setFocused(id)
            } else {
                // Focus can land on a window we haven't registered yet (the
                // created event may follow the focus event). Adopt it instead
                // of dropping the focus on the floor; register() back-fills
                // the focused state.
                registerIfStandard(element)
            }

        default:
            break
        }
    }

    private func dropApp(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .defaultMode)
        }
        for (id, managed) in windows where managed.pid == pid {
            unregister(id)
        }
    }

    /// Drop windows whose AX element no longer responds (app crashed, etc.).
    func pruneDead() {
        for (id, managed) in windows where AX.frame(of: managed.element) == nil {
            unregister(id)
        }
    }
}
