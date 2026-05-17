// ABOUTME: Ported from perfect-freehand@1.2.3/getStrokeRadius.ts (MIT, Steve Ruiz).
// ABOUTME: Computes per-point stroke radius from pressure, thinning, easing.

import Foundation

/// Compute a radius based on the pressure.
///
/// Mirrors TS `getStrokeRadius(size, thinning, pressure, easing = (t) => t)`.
/// When `easing` is `nil`, the linear identity `t => t` is used — matching
/// the TS default-argument behavior.
///
/// - Parameters:
///   - size: The base stroke diameter.
///   - thinning: How much pressure affects thickness (negative inverts).
///   - pressure: The point's pressure value in [0, 1].
///   - easing: Optional pressure-shaping function; defaults to linear.
/// - Returns: The stroke radius at this point.
func getStrokeRadius(
    size: Double,
    thinning: Double,
    pressure: Double,
    easing: ((Double) -> Double)? = nil
) -> Double {
    let ease = easing ?? { t in t }
    return size * ease(0.5 - thinning * (0.5 - pressure))
}
