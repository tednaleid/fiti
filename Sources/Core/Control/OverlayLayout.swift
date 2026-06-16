// ABOUTME: Pure decision for the full-screen overlay's frame after a display
// ABOUTME: change — which screen to cover, and whether a resize is even needed.

import Foundation

public enum OverlayLayout {
    /// The frame the overlay window should adopt so it exactly covers the screen
    /// hosting the toolbar, or `nil` when no change is needed (the current frame
    /// already matches) or there is no screen to target.
    ///
    /// - toolbarScreen: frame of the screen currently hosting the toolbar, or
    ///   `nil` if that screen is gone (e.g. just disconnected).
    /// - fallbackScreen: frame to cover when `toolbarScreen` is `nil` — the
    ///   caller supplies the primary/main screen.
    /// - current: the overlay window's current frame.
    public static func targetFrame(toolbarScreen: Rect?, fallbackScreen: Rect?, current: Rect) -> Rect? {
        guard let target = toolbarScreen ?? fallbackScreen else { return nil }
        return target == current ? nil : target
    }
}
