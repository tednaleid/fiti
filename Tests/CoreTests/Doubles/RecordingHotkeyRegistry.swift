// ABOUTME: In-memory HotkeyRegistry double for tests. Records the registered
// ABOUTME: activation handler and exposes fireActivation() to drive it.

import Foundation

@MainActor
public final class RecordingHotkeyRegistry: HotkeyRegistry {
    private var handler: (() -> Void)?
    public init() {}
    public func onActivation(_ handler: @escaping () -> Void) {
        self.handler = handler
    }
    /// Test helper: simulate a system-wide hotkey press.
    public func fireActivation() { handler?() }
}
