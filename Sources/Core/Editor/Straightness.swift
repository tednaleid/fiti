// ABOUTME: Pure rubric for the hold-to-straighten gesture. Returns true when a
// ABOUTME: freehand path is straight enough that snapping to a line won't surprise
// ABOUTME: the user (rejects boxes, zigzags, arbitrary curves).

import Foundation

/// Returns true if `points` form a substantially-straight path. Uses the ratio
/// of accumulated path length to start->end Euclidean distance: 1.0 is perfect,
/// higher = more wandering. Default threshold of 1.20 accepts hand-drawn
/// straight-ish lines and rejects boxes/curves/zigzags.
public func isSubstantiallyStraight(points: [StrokePoint], threshold: Double = 1.20) -> Bool {
    guard points.count >= 2 else { return false }
    let dx = points.last!.x - points.first!.x
    let dy = points.last!.y - points.first!.y
    let euclidean = (dx * dx + dy * dy).squareRoot()
    guard euclidean > 0 else { return false }
    var pathLength = 0.0
    for i in 1..<points.count {
        let ddx = points[i].x - points[i - 1].x
        let ddy = points[i].y - points[i - 1].y
        pathLength += (ddx * ddx + ddy * ddy).squareRoot()
    }
    return pathLength / euclidean <= threshold
}
