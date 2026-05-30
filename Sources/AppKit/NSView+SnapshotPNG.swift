// ABOUTME: Render an on-screen NSView's hierarchy to a PNG via cacheDisplay — used by
// ABOUTME: the dev HTTP introspection endpoints that capture toolbar/popover chrome.

import AppKit

extension NSView {
    /// PNG of this view's current rendering (layer-backed content included), or nil
    /// when the view has no area. Permission-free (no screen-recording); offscreen.
    func snapshotPNG() -> Data? {
        let area = bounds
        guard area.width > 0, area.height > 0,
              let rep = bitmapImageRepForCachingDisplay(in: area) else { return nil }
        cacheDisplay(in: area, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
