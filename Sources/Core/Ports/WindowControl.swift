// ABOUTME: Window port. AppKit adapter conforms; tests use a recording double.

import Foundation

@MainActor
public protocol WindowControl: AnyObject {
    func setClickThrough(_ enabled: Bool)
    /// Bring the fiti overlay to the front. Implementations should also record
    /// the currently-frontmost OTHER application so `releaseFocus()` can restore
    /// it on deactivate.
    func focus()
    /// Hand keyboard focus back to whatever was frontmost when `focus()` was
    /// last called. No-op if nothing was captured or the captured app is no
    /// longer running.
    func releaseFocus()
}
