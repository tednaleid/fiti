// ABOUTME: HotkeyRegistry adapter using sindresorhus/KeyboardShortcuts.
// ABOUTME: Default activation hotkey is Opt+F; user-rebindable via Preferences UI (planned).

import AppKit
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    /// System-wide hotkey that toggles fiti's activation state.
    /// Default: Opt+F. Persisted to UserDefaults under this name once the user rebinds.
    static let toggleActivation = Self(
        "toggleActivation",
        default: .init(.f, modifiers: [.option])
    )
}

@MainActor
public final class KeyboardShortcutsHotkeys: HotkeyRegistry {
    public init() {}

    public func onActivation(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .toggleActivation, action: handler)
    }
}
