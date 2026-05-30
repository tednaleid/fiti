// ABOUTME: NSButton that accepts the first mouse click, so toolbar controls fire
// ABOUTME: immediately in the non-activating floating panel (no dead first click).
// ABOUTME: Also draws a brighter-accent hover ring so every toolbar button shows mouseover.

import AppKit

final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    /// Brighter-accent outline ring on hover. Sits over any active-state fill the
    /// owning controller sets (the fill is the layer background; this is the border).
    private func setHover(_ on: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = on ? 1.5 : 0
        layer?.borderColor = on
            ? NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            : NSColor.clear.cgColor
    }
}
