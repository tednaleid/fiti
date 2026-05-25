// ABOUTME: Renders a CursorSpec into an NSCursor (filled circle + adaptive
// ABOUTME: 1pt outline) and installs it on the CanvasInputView's cursor rect.

import AppKit

/// Draws the filled brush dab (inner color disc + outside contrast ring) used by
/// both the brush cursor and the size picker's pen preview. `diameter` is the
/// brush spec; the visible fill is half that (matching what gets drawn).
///
/// Inner ≈ visible stroke diameter. perfect-freehand's `size=N` produces
/// strokes ~N/2 wide at typical (slow-stroke, low-pressure) rendering
/// under our FitiStrokeOptions (thinning=0.5, simulatePressure=true),
/// so we halve the spec to match what users actually see drawn. Outline
/// lives OUTSIDE the inner diameter so it can't tint the user's color
/// choice. Even-odd fill on the ring keeps the inner pixels transparent
/// until we draw the fill, preserving alpha.
@MainActor
func fitiBrushDabImage(color: RGBA, diameter: Double, outlineWidth: CGFloat) -> NSImage {
    let fillDiameter = max(1.0, CGFloat(diameter) / 2)
    let outerDiameter = fillDiameter + outlineWidth * 2
    let size = NSSize(width: outerDiameter, height: outerDiameter)
    let outline = CursorSpec.outlineColor(for: color)
    let outerRect = NSRect(x: 0, y: 0, width: outerDiameter, height: outerDiameter)
    let innerRect = NSRect(x: outlineWidth, y: outlineWidth, width: fillDiameter, height: fillDiameter)
    return NSImage(size: size, flipped: false) { _ in
        let ring = NSBezierPath()
        ring.append(NSBezierPath(ovalIn: outerRect))
        ring.append(NSBezierPath(ovalIn: innerRect))
        ring.windingRule = .evenOdd
        NSColor(srgbRed: outline.r, green: outline.g, blue: outline.b, alpha: outline.a).setFill()
        ring.fill()
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
        NSBezierPath(ovalIn: innerRect).fill()
        return true
    }
}

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
        switch spec {
        case .brush(let color, let diameter):
            return makeBrushCursor(color: color, diameter: diameter)
        case .arrowhead(let color):
            return makeArrowheadCursor(color: color)
        case .system(let system):
            return nsCursor(for: system)
        }
    }

    func nsCursor(for system: SystemCursor) -> NSCursor {
        switch system {
        case .arrow: return .arrow
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .iBeam: return .iBeam
        case .crosshair: return .crosshair
        case .rotate: return Self.rotateCursor
        case .resize(let angle): return Self.resizeCursor(angle: angle)
        }
    }

    private static func resizeCursor(angle: Double) -> NSCursor {
        switch Int(angle.rounded()) {
        case 0: return .resizeLeftRight
        case 90: return .resizeUpDown
        case 45: return privateCursor("_windowResizeNorthEastSouthWestCursor") ?? .arrow
        case 135: return privateCursor("_windowResizeNorthWestSouthEastCursor") ?? .arrow
        default: return .arrow
        }
    }

    /// Calls an undocumented NSCursor class selector by name; nil if unavailable.
    private static func privateCursor(_ name: String) -> NSCursor? {
        let sel = NSSelectorFromString(name)
        guard NSCursor.responds(to: sel) else { return nil }
        return NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor
    }

    /// A rotate cursor drawn programmatically (two curved arrows). No bundled asset.
    private static let rotateCursor: NSCursor = {
        let d: CGFloat = 20
        let image = NSImage(size: NSSize(width: d, height: d), flipped: false) { _ in
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: d / 2, y: d / 2), radius: d / 2 - 3,
                           startAngle: 40, endAngle: 320)
            path.lineWidth = 2
            NSColor.black.setStroke()
            // soft white halo for contrast
            guard let halo = path.copy() as? NSBezierPath else { return true }
            halo.lineWidth = 4
            NSColor(white: 1, alpha: 0.8).setStroke(); halo.stroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: d / 2, y: d / 2))
    }()

    private func makeBrushCursor(color: RGBA, diameter: Double) -> NSCursor {
        let image = fitiBrushDabImage(color: color, diameter: diameter, outlineWidth: outlineWidth)
        let center = image.size.width / 2
        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }

    /// A solid arrowhead filled with the current color and a 1pt adaptive outline,
    /// mirroring the brush cursor so the active color is visible while the arrow tool
    /// is selected. Drawn flipped (origin top-left) to match NSCursor's hot-spot space;
    /// the hot spot is the tip, where a press starts the arrow's tail.
    private func makeArrowheadCursor(color: RGBA) -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let outlineWidth = self.outlineWidth
        let outline = CursorSpec.outlineColor(for: color)
        let tip = NSPoint(x: 2, y: 2)
        let image = NSImage(size: size, flipped: true) { _ in
            let p = NSBezierPath()
            p.move(to: tip)                          // tip (hot spot), pointing up-left
            p.line(to: NSPoint(x: 2, y: 15.5))       // left edge down
            p.line(to: NSPoint(x: 5.8, y: 11.8))     // notch in
            p.line(to: NSPoint(x: 9, y: 18))         // out to tail barb
            p.line(to: NSPoint(x: 11.5, y: 16.8))
            p.line(to: NSPoint(x: 8.2, y: 10.8))
            p.line(to: NSPoint(x: 13, y: 10.3))      // right shoulder
            p.close()
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
            p.fill()
            NSColor(srgbRed: outline.r, green: outline.g, blue: outline.b, alpha: outline.a).setStroke()
            p.lineWidth = outlineWidth
            p.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: tip)
    }
}
