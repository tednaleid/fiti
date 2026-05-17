// ABOUTME: Ported from perfect-freehand@1.2.3/getStroke.ts (MIT, Steve Ruiz).
// ABOUTME: Composition root — feeds input through getStrokePoints + getStrokeOutlinePoints.

import Foundation

/// ## getStroke
///
/// Get an array of points describing a polygon that surrounds the input points.
///
/// Mirrors `getStroke` from perfect-freehand@1.2.3 — feeds the input through
/// `getStrokePoints` and then `getStrokeOutlinePoints`, mapping the internal
/// `[[Double]]` polygon to the public `[Point2D]` output shape.
///
/// - Parameters:
///   - points: An array of input points conforming to `StrokeInputPoint`.
///   - options: Stroke options. Defaults match the TS source's destructured
///     defaults (size 16, thinning 0.5, smoothing 0.5, streamline 0.5,
///     simulatePressure true, last false).
/// - Returns: A closed polygon's vertices, suitable for filling on any 2D canvas.
public func getStroke<P: StrokeInputPoint>(
    points: [P],
    options: StrokeOptions = StrokeOptions()
) -> [Point2D] {
    let strokePoints = getStrokePoints(points: points, options: options)
    let outline = getStrokeOutlinePoints(points: strokePoints, options: options)
    return outline.map { Point2D(x: $0[0], y: $0[1]) }
}
