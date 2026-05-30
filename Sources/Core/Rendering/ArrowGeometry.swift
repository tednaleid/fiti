// ABOUTME: Pure geometry for the arrow tool: builds the merged shaft+head outline.
// ABOUTME: One closed polygon so the seam never double-darkens and hit-test is single.

import Foundation
import PerfectFreehand

public enum ArrowGeometry {
    // Head proportions as multiples of stroke width, tuned to the approved mockup.
    static let headLengthFactor = 1.17  // head length along the shaft
    static let barbSpanFactor = 0.70    // barb half-span perpendicular to the shaft
    static let sweepFraction = 0.17     // notch depth as a fraction of head length (ratio, unscaled)
    static let tailCapSegments = 8      // line segments approximating the round tail cap

    // Fixed shaft pressure. The pen uses simulatePressure (velocity-derived), but an
    // arrow is a single rubber-banded segment, so velocity == drag length: the same
    // options make a long arrow's shaft far fatter than a short one's. We instead pin
    // one pressure so the shaft is a consistent width per stroke-width setting, chosen
    // to sit in the pen's typical rendered range.
    static let shaftPressure = 0.1

    /// One reference input point carrying an explicit pressure. getStroke strips
    /// pressure from a 2-point input, so shaftHalfWidth feeds three points.
    private struct ShaftInput: StrokeInputPoint {
        let x: Double
        let y: Double
        let pressure: Double?
    }

    /// The shaft half-width perfect-freehand renders for a straight stroke at `width`,
    /// taken from getStroke's own output (not a duplicated formula) on the shared
    /// `FitiStrokeOptions` with simulation off and a fixed pressure, so the shaft stays
    /// on the same pipeline as the pen while being length-independent.
    /// Public so the toolbar preview can reserve room for the round tail cap.
    public static func shaftHalfWidth(width: Double) -> Double {
        var opts = FitiStrokeOptions.make(width: width, last: true)
        opts.simulatePressure = false
        let inputs = [ShaftInput(x: 0, y: 0, pressure: shaftPressure),
                      ShaftInput(x: 50, y: 0, pressure: shaftPressure),
                      ShaftInput(x: 100, y: 0, pressure: shaftPressure)]
        let poly = getStroke(points: inputs, options: opts)
        return poly.map { abs($0.y) }.max() ?? width / 2   // axis on x, half-width = max |y|
    }

    /// Merged arrow outline (local space) from `tail` to `head` at `width`.
    /// Empty when degenerate.
    public static func outline(tail: Point, head: Point, width: Double) -> [Point] {
        let dx = head.x - tail.x, dy = head.y - tail.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0, width > 0 else { return [] }
        let ux = dx / len, uy = dy / len     // unit axis, tail -> head
        let nx = -uy, ny = ux                // left normal

        let headLen = min(headLengthFactor * width, len)
        let barb = barbSpanFactor * width
        let tailH = shaftHalfWidth(width: width)
        let baseH = tailH

        func along(_ p: Point, _ d: Double) -> Point { Point(x: p.x - ux * d, y: p.y - uy * d) }
        func offset(_ p: Point, _ d: Double) -> Point { Point(x: p.x + nx * d, y: p.y + ny * d) }

        let base = along(head, headLen)      // backmost of the head, on axis
        // inner back vertex: sits `sweepFraction` of the head length forward of the base,
        // giving the head a shallow concave back (solid swept head, not an open chevron).
        let notchPt = along(head, headLen - sweepFraction * headLen)

        var pts: [Point] = [
            offset(tail, tailH),     // 0 tail left
            offset(notchPt, baseH),  // 1 shaft/head join left
            offset(base, barb),      // 2 left barb tip
            head,                    // 3 tip
            offset(base, -barb),     // 4 right barb tip
            offset(notchPt, -baseH), // 5 shaft/head join right
            offset(tail, -tailH)     // 6 tail right
        ]
        // Rounded tail cap: a semicircle of radius `tailH` bulging backward (away from
        // the head) from tail-right (6) round to tail-left (0), so the start reads as a
        // round cap like a pen line, not a squared-off edge. Interior points only; the
        // endpoints are already vertices 6 and 0.
        for i in 1..<tailCapSegments {
            let angle = Double.pi * Double(i) / Double(tailCapSegments)
            let dx = -nx * cos(angle) - ux * sin(angle)
            let dy = -ny * cos(angle) - uy * sin(angle)
            pts.append(Point(x: tail.x + tailH * dx, y: tail.y + tailH * dy))
        }
        return pts
    }
}
