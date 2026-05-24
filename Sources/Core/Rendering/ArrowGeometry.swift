// ABOUTME: Pure geometry for the arrow tool: builds the merged shaft+head outline.
// ABOUTME: One closed polygon so the seam never double-darkens and hit-test is single.

import Foundation

public enum ArrowGeometry {
    // Proportions as multiples of stroke width, tuned to the approved mockup.
    static let headLengthFactor = 4.5   // head length along the shaft
    static let barbSpanFactor = 2.6     // barb half-span perpendicular to the shaft
    static let sweepFraction = 0.25     // notch depth as a fraction of head length
    static let tailHalfFactor = 0.275   // shaft half-width at the tail
    static let baseHalfFactor = 0.5     // shaft half-width where it meets the head

    /// Merged arrow outline (local space) from `tail` to `head` at `width`.
    /// Seven vertices, counterclockwise; empty when degenerate.
    public static func outline(tail: Point, head: Point, width: Double) -> [Point] {
        let dx = head.x - tail.x, dy = head.y - tail.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0, width > 0 else { return [] }
        let ux = dx / len, uy = dy / len     // unit axis, tail -> head
        let nx = -uy, ny = ux                // left normal

        let headLen = min(headLengthFactor * width, len)
        let barb = barbSpanFactor * width
        let notch = sweepFraction * headLen
        let tailH = tailHalfFactor * width
        let baseH = baseHalfFactor * width

        func along(_ p: Point, _ d: Double) -> Point { Point(x: p.x - ux * d, y: p.y - uy * d) }
        func offset(_ p: Point, _ d: Double) -> Point { Point(x: p.x + nx * d, y: p.y + ny * d) }

        let base = along(head, headLen)      // backmost of the head, on axis
        let notchPt = along(head, notch)     // inner back vertex, forward of base

        return [
            offset(tail, tailH),     // 0 tail left
            offset(notchPt, baseH),  // 1 shaft/head join left
            offset(base, barb),      // 2 left barb tip
            head,                    // 3 tip
            offset(base, -barb),     // 4 right barb tip
            offset(notchPt, -baseH), // 5 shaft/head join right
            offset(tail, -tailH)     // 6 tail right
        ]
    }
}
