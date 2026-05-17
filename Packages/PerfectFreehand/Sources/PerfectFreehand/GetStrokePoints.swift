// ABOUTME: Ported from perfect-freehand@1.2.3/getStrokePoints.ts (MIT, Steve Ruiz).
// ABOUTME: Input sampling with streamline-aware low-pass filter; emits internal StrokePoints.

import Foundation

/// The internal per-sample shape produced by `getStrokePoints` and consumed by
/// `getStrokeOutlinePoints`. Mirrors upstream TS `StrokePoint`:
///   `{ point, pressure, distance, vector, runningLength }`.
///
/// Internal to the PerfectFreehand package — the public surface only exposes
/// `[Point2D]` via `getStroke`. Named `StrokePoint` here to match upstream;
/// there is no module-level collision with fiti's same-named type because the
/// two live in separate modules.
struct StrokePoint {
    var point: [Double]
    var pressure: Double
    var distance: Double
    var vector: [Double]
    var runningLength: Double
}

/// Input sampling with streamline-aware low-pass filter.
///
/// Takes raw input points (anything conforming to `StrokeInputPoint`) and emits
/// an array of `StrokePoint`s with adjusted positions, pressure, the unit
/// vector from the current point to the previous one, per-segment distance,
/// and cumulative running length.
///
/// Mirrors `getStrokePoints` from perfect-freehand@1.2.3.
///
/// Pressure-defaulting note: TS has two input shapes — array (`[x, y, p?]`)
/// and object (`{x, y, pressure?}`). On the object path, TS destructuring
/// fills `pressure = DEFAULT_PRESSURE (0.5)` for every point, so the first
/// point's pressure becomes `0.5`, not `DEFAULT_FIRST_PRESSURE (0.25)`. On
/// the array path, `pts[i][2]` stays `undefined`, so the first point falls
/// through to `DEFAULT_FIRST_PRESSURE (0.25)`.
///
/// Our `StrokeInputPoint` protocol is object-shaped (`{x, y, pressure?}`),
/// so we mirror the TS object path: a `nil` pressure becomes
/// `DEFAULT_PRESSURE (0.5)` for every point — including the first.
/// `DEFAULT_FIRST_PRESSURE (0.25)` only fires for synthesized points whose
/// pressure was stripped at a vector-arithmetic boundary (the 2-point
/// expansion path's interpolated tail, which the TS source also leaves
/// pressure-less by virtue of `lrp` returning a length-2 vector).
///
/// - Parameters:
///   - points: The raw input points.
///   - options: Stroke options (only `streamline`, `size`, `last` are read here).
/// - Returns: An array of internal `StrokePoint`s.
func getStrokePoints<P: StrokeInputPoint>(
    points: [P],
    options: StrokeOptions = StrokeOptions()
) -> [StrokePoint] {
    let streamline = options.streamline
    let size = options.size
    let isComplete = options.last

    // If we don't have any points, return an empty array.
    if points.isEmpty { return [] }

    // Find the interpolation level between points.
    let t = PFConstants.MIN_STREAMLINE_T + (1 - streamline) * PFConstants.STREAMLINE_T_RANGE

    // Two parallel arrays: pts holds [x, y] only; ptPressures carries pressure
    // separately. Following the TS object-path destructuring, a nil pressure
    // is materialised as DEFAULT_PRESSURE up front (and then later treated
    // as a valid pressure by isValidPressure at the strokePoint-creation
    // site, so the first point also gets DEFAULT_PRESSURE rather than
    // DEFAULT_FIRST_PRESSURE).
    var pts: [[Double]] = points.map { [$0.x, $0.y] }
    var ptPressures: [Double?] = points.map { $0.pressure ?? PFConstants.DEFAULT_PRESSURE }

    // Add extra points between the two, to help avoid "dash" lines for
    // strokes with tapered start and ends. Don't mutate the input array!
    if pts.count == 2 {
        let last = pts[1]
        pts = Array(pts.dropLast())
        ptPressures.removeLast()
        for i in 1..<5 {
            pts.append(Vec.lrp(pts[0], last, Double(i) / 4.0))
            // TS's lrp returns a length-2 array; the third coord is dropped.
            // Pressure for the interpolated tail is "undefined" in TS (the
            // Vec2 has no third element). The final i=4 point lands exactly
            // at `last`, but its pressure is likewise lost. Downstream
            // `isValidPressure(nil)` falls back to DEFAULT_PRESSURE.
            ptPressures.append(nil)
        }
    }

    // If there's only one point, add another point at a 1pt offset.
    // Don't mutate the input array!
    if pts.count == 1 {
        pts.append(Vec.add(pts[0], PFConstants.UNIT_OFFSET))
        // TS preserves the original pressure on the synthesized second point
        // via `...pts[0].slice(2)`; if pts[0] had no pressure, the slice is
        // empty and the synthesized point also has undefined pressure.
        ptPressures.append(ptPressures[0])
    }

    // The strokePoints array will hold the points for the stroke.
    // Start it out with the first point, which needs no adjustment.
    let firstPressure: Double = isValidPressure(ptPressures[0])
        ? ptPressures[0]!
        : PFConstants.DEFAULT_FIRST_PRESSURE
    var strokePoints: [StrokePoint] = [
        StrokePoint(
            point: [pts[0][0], pts[0][1]],
            pressure: firstPressure,
            distance: 0,
            vector: PFConstants.UNIT_OFFSET,
            runningLength: 0
        )
    ]

    // A flag to see whether we've already reached our minimum length.
    var hasReachedMinimumLength = false

    // We use the runningLength to keep track of the total distance.
    var runningLength: Double = 0

    // Latest point — used to compute the next point's distance and vector.
    var prev = strokePoints[0]

    let max = pts.count - 1

    // Scratch buffer for the vector difference (matches TS allocation pattern).
    var vectorDiff: [Double] = [0, 0]

    // Iterate through all of the points, creating StrokePoints.
    for i in 1..<pts.count {
        let point: [Double] = (isComplete && i == max)
            // If we're at the last point and `options.last` is true,
            // emit the actual input point.
            ? [pts[i][0], pts[i][1]]
            // Otherwise, using the streamline-derived t, interpolate a new
            // point between the previous point and the current input point.
            : Vec.lrp(prev.point, [pts[i][0], pts[i][1]], t)

        // If the new point is the same as the previous point, skip ahead.
        if Vec.isEqual(prev.point, point) { continue }

        // How far is the new point from the previous point?
        let distance = Vec.dist(point, prev.point)

        // Add this distance to the total running length.
        runningLength += distance

        // At the start of the line we wait until the new point is a certain
        // distance away from the original point to avoid noise.
        if i < max && !hasReachedMinimumLength {
            if runningLength < size { continue }
            hasReachedMinimumLength = true
            // TODO: TS source has the same TODO about backfilling missing
            // points so that tapering works correctly — we mirror it.
        }

        // Create a new strokepoint (it will be the new "previous" one).
        // Use the scratch buffer for the vector difference to mirror TS.
        Vec.subInto(&vectorDiff, prev.point, point)
        let pressure: Double = isValidPressure(ptPressures[i])
            ? ptPressures[i]!
            : PFConstants.DEFAULT_PRESSURE
        prev = StrokePoint(
            point: point,
            pressure: pressure,
            distance: distance,
            vector: Vec.uni(vectorDiff),
            runningLength: runningLength
        )

        strokePoints.append(prev)
    }

    // Set the vector of the first point to be the same as the second point.
    if strokePoints.count >= 2 {
        strokePoints[0].vector = strokePoints[1].vector
    } else {
        strokePoints[0].vector = [0, 0]
    }

    return strokePoints
}

/// Returns true when a pressure value is defined and non-negative.
/// Mirrors `isValidPressure` in the TS source.
private func isValidPressure(_ pressure: Double?) -> Bool {
    guard let pressure = pressure else { return false }
    if pressure.isNaN { return false }
    return pressure >= 0
}
