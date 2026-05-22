// ABOUTME: Region of an oriented selection box that a point falls in, plus
// ABOUTME: the pure cursor policy. Drives both hit-routing and hover cursors.

import Foundation

public enum Corner: Equatable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft
}

public enum SelectionRegion: Equatable, Sendable {
    case rotateHandle
    case corner(Corner)
    case body
    case outside
}

/// Pure cursor policy: the cursor to show for a region, given the box rotation
/// and whether a drag is active. Corner cursors are bucketed by screen-space
/// angle (the corner's local diagonal plus the box rotation) into the four
/// orientations the platform provides.
public func cursorFor(region: SelectionRegion, boxRotation: Double, dragging: Bool) -> SystemCursor {
    switch region {
    case .rotateHandle:
        return .rotate
    case .body:
        return dragging ? .closedHand : .openHand
    case .outside:
        return .arrow
    case .corner(let corner):
        let base: Double = (corner == .topLeft || corner == .bottomRight) ? 135 : 45
        return .resize(angle: bucketAngle(base + boxRotation))
    }
}

/// Reduces an angle (degrees) mod 180 and snaps to the nearest of {0,45,90,135}.
private func bucketAngle(_ degrees: Double) -> Double {
    var a = degrees.truncatingRemainder(dividingBy: 180)
    if a < 0 { a += 180 }
    let buckets: [Double] = [0, 45, 90, 135]
    // 180 wraps to 0; pick nearest including the 180==0 wrap.
    var best = buckets[0]
    var bestDist = Double.infinity
    for b in buckets + [180] {
        let d = abs(a - b)
        if d < bestDist { bestDist = d; best = b == 180 ? 0 : b }
    }
    return best
}
