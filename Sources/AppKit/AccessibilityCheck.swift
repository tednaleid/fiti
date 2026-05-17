// ABOUTME: Checks Accessibility permission, the prerequisite for
// ABOUTME: global NSEvent monitors (needed by the Ctrl+F hotkey).

import AppKit
import ApplicationServices

public enum AccessibilityCheck {
    /// Returns true if accessibility permission is currently granted.
    /// Pass `prompt: true` to show the system permission alert if not granted.
    @MainActor
    public static func isTrusted(prompt: Bool) -> Bool {
        // Swift 6 strict concurrency rejects the `kAXTrustedCheckOptionPrompt`
        // CFString global as non-Sendable. The constant's value is the literal
        // string below; use it directly.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
