import AppKit
import ApplicationServices

@Observable
final class PermissionManager {
    private(set) var accessibilityGranted: Bool

    init() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func checkAndRefresh() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        accessibilityGranted = AXIsProcessTrusted()
    }

    // Returns nil if permission denied or no focused window
    static func windowTitle(for app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindow = focusedWindowRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }
}
