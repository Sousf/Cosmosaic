import AppKit
import ApplicationServices

/// Thin wrapper over the Accessibility API. All AX coordinates are top-left
/// origin with y increasing downward; AppKit screens are bottom-left origin.
/// Everything here runs on the main actor (AX observers fire on the main
/// run loop).
@MainActor
enum AX {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Coordinate conversion

    /// Height of the primary screen (the one holding the global origin), used
    /// to flip between AppKit (bottom-left) and AX (top-left) coordinates.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Convert an AppKit rect (bottom-left origin) to AX space (top-left origin).
    static func axRect(fromAppKit rect: NSRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// The tileable area of a screen (excludes menu bar and Dock), in AX space.
    static func tileableArea(of screen: NSScreen) -> CGRect {
        axRect(fromAppKit: screen.visibleFrame)
    }

    // MARK: - Application elements

    static func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let list: [AXUIElement] = copyAttribute(app, kAXWindowsAttribute) else {
            return []
        }
        return list
    }

    static func focusedWindow(ofPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return copyAttribute(app, kAXFocusedWindowAttribute)
    }

    // MARK: - Window attributes

    static func role(_ element: AXUIElement) -> String? {
        copyAttribute(element, kAXRoleAttribute) as CFString? as String?
    }

    static func subrole(_ element: AXUIElement) -> String? {
        copyAttribute(element, kAXSubroleAttribute) as CFString? as String?
    }

    static func title(_ element: AXUIElement) -> String {
        (copyAttribute(element, kAXTitleAttribute) as CFString? as String?) ?? ""
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        (copyAttribute(element, kAXMinimizedAttribute) as CFBoolean?) == kCFBooleanTrue
    }

    /// A window hyprmac should tile: a standard, non-minimized window.
    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        role(element) == kAXWindowRole
            && subrole(element) == kAXStandardWindowSubrole
            && !isMinimized(element)
    }

    /// A popup the app owns (save prompt, alert, floating panel): never tiled,
    /// but kept above the tiled layer. Sheets are excluded — macOS attaches
    /// them to their parent window itself.
    static func isDialog(_ element: AXUIElement) -> Bool {
        guard role(element) == kAXWindowRole else { return false }
        switch subrole(element) {
        case kAXDialogSubrole, kAXSystemDialogSubrole, kAXFloatingWindowSubrole:
            return true
        default:
            return false
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = copyAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = copyAttribute(element, kAXSizeAttribute) else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ element: AXUIElement, to rect: CGRect) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let posValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        // Size → position → size: some apps clamp position by current size.
        let s1 = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let p = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        let s2 = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return p == .success && (s1 == .success || s2 == .success)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, to point: CGPoint) -> Bool {
        var origin = point
        guard let posValue = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue) == .success
    }

    // MARK: - Window actions

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func focus(_ element: AXUIElement, pid: pid_t) {
        raise(element)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Focus for follow-mouse: make the window key without an explicit raise,
    /// X11-style. Cross-app hovers still raise the target window as a side
    /// effect of app activation — macOS offers no way around that.
    static func focusWithoutRaise(_ element: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    static func close(_ element: AXUIElement) {
        guard let button: AXUIElement = copyAttribute(element, kAXCloseButtonAttribute) else {
            return
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    // MARK: - Plumbing

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }
}
