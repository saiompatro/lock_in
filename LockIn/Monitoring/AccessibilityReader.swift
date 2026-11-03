import AppKit
import ApplicationServices

/// Thin helpers over the C Accessibility API.
enum AX {
    /// Upper bound for a single AX call so a hung app cannot freeze Lock In.
    static let messagingTimeout: Float = 0.5

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return (error == .success ? ref : nil, error)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute).value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute).value as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let ref = value(element, attribute).value, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = value(element, attribute).value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            let ref = item as CFTypeRef
            guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(ref, to: AXUIElement.self)
        }
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ newValue: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, newValue) == .success
    }

    /// Windows of an app (including minimized ones), with the per-call timeout applied.
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = application(pid: pid)
        return elements(app, kAXWindowsAttribute)
    }
}

/// What the Accessibility API says about the focused window of one app.
struct WindowState: Sendable, Equatable {
    var title: String?
    var hasVisibleWindow: Bool
}

enum AccessibilityReader {
    /// Reads the focused window's title and visibility. Call only when Accessibility is trusted.
    static func windowState(pid: pid_t, isHidden: Bool) -> WindowState {
        if isHidden { return WindowState(title: nil, hasVisibleWindow: false) }
        let app = AX.application(pid: pid)

        let focused = AX.value(app, kAXFocusedWindowAttribute)
        if let ref = focused.value, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            return state(of: unsafeDowncast(ref, to: AXUIElement.self))
        }
        // The app is unresponsive or does not speak AX: do not claim the window is gone.
        if focused.error == .cannotComplete || focused.error == .apiDisabled
            || focused.error == .notImplemented || focused.error == .attributeUnsupported {
            return WindowState(title: nil, hasVisibleWindow: true)
        }
        if let main = AX.element(app, kAXMainWindowAttribute) {
            return state(of: main)
        }
        // No focused/main window: visible only if some window is not minimized.
        for window in AX.elements(app, kAXWindowsAttribute) where AX.bool(window, kAXMinimizedAttribute) != true {
            return WindowState(title: AX.string(window, kAXTitleAttribute), hasVisibleWindow: true)
        }
        return WindowState(title: nil, hasVisibleWindow: false)
    }

    private static func state(of window: AXUIElement) -> WindowState {
        if AX.bool(window, kAXMinimizedAttribute) == true {
            return WindowState(title: nil, hasVisibleWindow: false)
        }
        return WindowState(title: AX.string(window, kAXTitleAttribute), hasVisibleWindow: true)
    }
}
