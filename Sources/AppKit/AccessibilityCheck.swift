// ABOUTME: Checks Accessibility permission, the prerequisite for
// ABOUTME: global NSEvent monitors (needed by the Cmd+Opt+Z hotkey).

import AppKit
import ApplicationServices

public enum AccessibilityCheck {
    /// Returns true if accessibility permission is currently granted.
    /// Pass `prompt: true` to show the system permission alert if not granted.
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
