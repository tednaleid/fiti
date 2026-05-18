// ABOUTME: System-wide hotkey port. AppKit adapter (KeyboardShortcuts-backed)
// ABOUTME: conforms; tests use RecordingHotkeyRegistry with a fireActivation() helper.

import Foundation

@MainActor
public protocol HotkeyRegistry: AnyObject {
    /// Register a handler that fires when the user's bound activation hotkey
    /// is pressed system-wide. Intended to be called once at composition time.
    /// Adapters may either replace any prior handler or compose; callers should
    /// not rely on a particular policy and should set the handler exactly once.
    func onActivation(_ handler: @escaping () -> Void)
}
