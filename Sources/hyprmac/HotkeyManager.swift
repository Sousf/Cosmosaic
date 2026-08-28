import Carbon.HIToolbox
import AppKit
import HyprmacCore

/// Registers global hotkeys with Carbon's RegisterEventHotKey — no extra
/// permissions needed, and bound keys are consumed before reaching apps.
@MainActor
final class HotkeyManager {

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var actions: [UInt32: Dispatcher] = [:]
    private var currentBinds: [Keybind] = []

    var onDispatch: ((Dispatcher) -> Void)?

    /// Keys that failed to register (name unknown or already taken system-wide).
    private(set) var bindErrors: [String] = []

    /// Release all hotkeys while the keybindings UI records a shortcut, so the
    /// combo being recorded isn't swallowed by an existing bind.
    func suspend() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    func resume() {
        rebind(to: currentBinds)
    }

    func rebind(to binds: [Keybind]) {
        currentBinds = binds
        unbindAll()
        installHandlerIfNeeded()

        var nextID: UInt32 = 1
        for bind in binds {
            guard let keyCode = KeyCodes.keyCode(for: bind.key) else {
                bindErrors.append("unknown key '\(bind.key)'")
                continue
            }
            let hotKeyID = EventHotKeyID(signature: OSType(0x484D_4143) /* "HMAC" */,
                                         id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(keyCode,
                                             KeyCodes.carbonFlags(for: bind.mods),
                                             hotKeyID,
                                             GetApplicationEventTarget(),
                                             0, &ref)
            if status == noErr, let ref {
                actions[nextID] = bind.dispatcher
                hotKeyRefs.append(ref)
                nextID += 1
            } else {
                bindErrors.append("could not register \(bind.mods.map(\.rawValue).sorted().joined(separator: "+"))+\(bind.key)")
            }
        }
    }

    private func unbindAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()
        bindErrors.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon in
            guard let event, let refcon else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let dispatcher = manager.actions[hotKeyID.id] {
                    manager.onDispatch?(dispatcher)
                }
            }
            return noErr
        }, 1, &eventType, refcon, &handlerRef)
    }
}
