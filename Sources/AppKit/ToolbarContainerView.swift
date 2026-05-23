// ABOUTME: Content view for the floating toolbar panel. Claims the arrow cursor
// ABOUTME: so the canvas's circle cursor doesn't linger over the toolbar.

import AppKit

/// Container for the toolbar's content view that claims the arrow cursor.
/// Without this, the canvas window's lingering `NSCursor.set()` for the fiti
/// circle cursor stays visible while the mouse is over the toolbar — the
/// canvas tracking area doesn't fire `mouseExited` for a different window
/// covering the same screen area, so it never gets a chance to revert.
@MainActor
final class ToolbarContainerView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
