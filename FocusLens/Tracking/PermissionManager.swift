import AppKit
import ApplicationServices

@Observable
final class PermissionManager {
    private(set) var accessibilityGranted: Bool

    init() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        accessibilityGranted = AXIsProcessTrusted()
    }

    // Returns nil if permission denied or no usable title.
    // Tries focused window → main window → first window in windows list.
    // Some Chromium-based browsers (Brave) return "" from kAXFocusedWindow,
    // so we fall through to the next strategy when the title is empty.
    static func windowTitle(for app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let title = titleFromWindowAttribute(axApp: axApp, attribute: attribute as CFString),
               !title.isEmpty { return title }
        }

        // Last resort: first window in the windows list
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let first = windows.first else { return nil }
        return titleFromAXElement(first)
    }

    private static func titleFromWindowAttribute(axApp: AXUIElement, attribute: CFString) -> String? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, attribute, &windowRef) == .success,
              let ref = windowRef else { return nil }
        return titleFromAXElement(unsafeBitCast(ref, to: AXUIElement.self))
    }

    private static func titleFromAXElement(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }
}
