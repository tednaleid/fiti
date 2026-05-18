// ABOUTME: Renders a CursorSpec into an NSCursor (filled circle + adaptive
// ABOUTME: 1pt outline) and installs it on the CanvasInputView's cursor rect.

import AppKit

@MainActor
public final class CursorRenderer {
    private weak var view: CanvasInputView?
    private let outlineWidth: CGFloat = 1.0

    public init(view: CanvasInputView) {
        self.view = view
    }

    public func setSpec(_ spec: CursorSpec?) {
        view?.updateCursor(spec.map { makeCursor(for: $0) })
    }

    private func makeCursor(for spec: CursorSpec) -> NSCursor {
        // Inner ≈ visible stroke diameter. perfect-freehand's `size=N` produces
        // strokes ~N/2 wide at typical (slow-stroke, low-pressure) rendering
        // under our FitiStrokeOptions (thinning=0.5, simulatePressure=true),
        // so we halve the spec to match what users actually see drawn. Outline
        // lives OUTSIDE the inner diameter so it can't tint the user's color
        // choice. Even-odd fill on the ring keeps the inner pixels transparent
        // until we draw the fill, preserving alpha.
        let fillDiameter = max(1.0, CGFloat(spec.diameter) / 2)
        let outerDiameter = fillDiameter + outlineWidth * 2
        let size = NSSize(width: outerDiameter, height: outerDiameter)
        let outline = CursorSpec.outlineColor(for: spec.color)
        let outerRect = NSRect(x: 0, y: 0, width: outerDiameter, height: outerDiameter)
        let innerRect = NSRect(x: outlineWidth, y: outlineWidth, width: fillDiameter, height: fillDiameter)

        let image = NSImage(size: size, flipped: false) { _ in
            let ring = NSBezierPath()
            ring.append(NSBezierPath(ovalIn: outerRect))
            ring.append(NSBezierPath(ovalIn: innerRect))
            ring.windingRule = .evenOdd
            NSColor(srgbRed: outline.r, green: outline.g, blue: outline.b, alpha: outline.a).setFill()
            ring.fill()

            NSColor(srgbRed: spec.color.r, green: spec.color.g, blue: spec.color.b, alpha: spec.color.a).setFill()
            NSBezierPath(ovalIn: innerRect).fill()
            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: outerDiameter / 2, y: outerDiameter / 2))
    }
}
