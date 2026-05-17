// ABOUTME: Ported from perfect-freehand@1.2.3/getStrokeOutlinePoints.ts (MIT, Steve Ruiz).
// ABOUTME: Outline polygon construction — left/right offset, caps, tapers.

import Foundation

// Scratch buffers for allocation-free hot loop calculations.
// Function-local to keep the port thread-safe (TS module-level vars work in
// single-threaded JS; in Swift we keep them per-call as locals).

/// Draw a dot (circle) for very short strokes.
private func drawDot(center: [Double], radius: Double) -> [[Double]] {
    let offsetPoint = Vec.add(center, PFConstants.UNIT_OFFSET)
    let start = Vec.prj(center, Vec.uni(Vec.per(Vec.sub(center, offsetPoint))), -radius)
    var dotPts: [[Double]] = []
    let step = 1.0 / Double(PFConstants.START_CAP_SEGMENTS)
    var t = step
    while t <= 1 {
        dotPts.append(Vec.rotAround(start, center, PFConstants.FIXED_PI * 2 * t))
        t += step
    }
    return dotPts
}

/// Draw a rounded start cap by rotating points from right to left around the start point.
private func drawRoundStartCap(
    center: [Double],
    rightPoint: [Double],
    segments: Int
) -> [[Double]] {
    var cap: [[Double]] = []
    let step = 1.0 / Double(segments)
    var t = step
    while t <= 1 {
        cap.append(Vec.rotAround(rightPoint, center, PFConstants.FIXED_PI * t))
        t += step
    }
    return cap
}

/// Draw a flat start cap with squared-off edges.
private func drawFlatStartCap(
    center: [Double],
    leftPoint: [Double],
    rightPoint: [Double]
) -> [[Double]] {
    let cornersVector = Vec.sub(leftPoint, rightPoint)
    let offsetA = Vec.mul(cornersVector, 0.5)
    let offsetB = Vec.mul(cornersVector, 0.51)
    return [
        Vec.sub(center, offsetA),
        Vec.sub(center, offsetB),
        Vec.add(center, offsetB),
        Vec.add(center, offsetA),
    ]
}

/// Draw a rounded end cap (1.5 turns to handle sharp end turns correctly).
private func drawRoundEndCap(
    center: [Double],
    direction: [Double],
    radius: Double,
    segments: Int
) -> [[Double]] {
    var cap: [[Double]] = []
    let start = Vec.prj(center, direction, radius)
    let step = 1.0 / Double(segments)
    var t = step
    while t < 1 {
        cap.append(Vec.rotAround(start, center, PFConstants.FIXED_PI * 3 * t))
        t += step
    }
    return cap
}

/// Draw a flat end cap with squared-off edges.
private func drawFlatEndCap(
    center: [Double],
    direction: [Double],
    radius: Double
) -> [[Double]] {
    return [
        Vec.add(center, Vec.mul(direction, radius)),
        Vec.add(center, Vec.mul(direction, radius * 0.99)),
        Vec.sub(center, Vec.mul(direction, radius * 0.99)),
        Vec.sub(center, Vec.mul(direction, radius)),
    ]
}

/// Compute the taper distance from a `TaperValue`.
/// - `.none` → `0` (TS `false` / `undefined`)
/// - `.auto` → `max(size, totalLength)` (TS `true`)
/// - `.length(n)` → `n` (TS `number`)
private func computeTaperDistance(
    _ taper: TaperValue,
    size: Double,
    totalLength: Double
) -> Double {
    switch taper {
    case .none: return 0
    case .auto: return max(size, totalLength)
    case .length(let n): return n
    }
}

/// Compute the initial pressure by averaging the first few points.
/// This prevents "fat starts" since drawn lines almost always start slow.
private func computeInitialPressure(
    points: [StrokePoint],
    shouldSimulatePressure: Bool,
    size: Double
) -> Double {
    let head = points.prefix(10)
    var acc = points[0].pressure
    for curr in head {
        var pressure = curr.pressure
        if shouldSimulatePressure {
            pressure = simulatePressure(prevPressure: acc, distance: curr.distance, size: size)
        }
        acc = (acc + pressure) / 2
    }
    return acc
}

/// Default per-end easings — match TS's destructured defaults in
/// `getStrokeOutlinePoints.ts`:
///   start.easing default: `t => t * (2 - t)`
///   end.easing default:   `t => --t * t * t + 1`
@Sendable private func defaultStartTaperEase(_ t: Double) -> Double { t * (2 - t) }
@Sendable private func defaultEndTaperEase(_ t: Double) -> Double {
    let u = t - 1
    return u * u * u + 1
}

/// ## getStrokeOutlinePoints
/// Get an array of points (as `[x, y]`) representing the outline of a stroke.
///
/// Mirrors `getStrokeOutlinePoints` from perfect-freehand@1.2.3.
/// Returns `[[Double]]` (array of 2-element `[x, y]` arrays) to match the
/// algorithm's internal shape; the public `getStroke` adapter maps this to
/// `[Point2D]`.
///
/// - Parameters:
///   - points: An array of `StrokePoint`s as returned from `getStrokePoints`.
///   - options: Stroke options.
/// - Returns: The outline polygon vertices.
func getStrokeOutlinePoints(
    points: [StrokePoint],
    options: StrokeOptions = StrokeOptions()
) -> [[Double]] {
    let size = options.size
    let smoothing = options.smoothing
    let thinning = options.thinning
    let shouldSimulatePressure = options.simulatePressure
    let easing = options.easing ?? { t in t }
    let start = options.start
    let end = options.end
    let isComplete = options.last

    let capStart = start.cap
    let taperStartEase = start.easing ?? defaultStartTaperEase

    let capEnd = end.cap
    let taperEndEase = end.easing ?? defaultEndTaperEase

    // We can't do anything with an empty array or a stroke with negative size.
    if points.isEmpty || size <= 0 {
        return []
    }

    // The total length of the line
    let totalLength = points[points.count - 1].runningLength

    let taperStart = computeTaperDistance(start.taper, size: size, totalLength: totalLength)
    let taperEnd = computeTaperDistance(end.taper, size: size, totalLength: totalLength)

    // The minimum allowed distance between points (squared)
    let minDistance = pow(size * smoothing, 2)

    // Our collected left and right points
    var leftPts: [[Double]] = []
    var rightPts: [[Double]] = []

    // Previous pressure (averaged from first few points to prevent fat starts)
    var prevPressure = computeInitialPressure(
        points: points,
        shouldSimulatePressure: shouldSimulatePressure,
        size: size
    )

    // The current radius
    var radius = getStrokeRadius(
        size: size,
        thinning: thinning,
        pressure: points[points.count - 1].pressure,
        easing: easing
    )

    // The radius of the first saved point
    var firstRadius: Double? = nil

    // Previous vector
    var prevVector = points[0].vector

    // Previous left and right points
    var prevLeftPoint = points[0].point
    var prevRightPoint = prevLeftPoint

    // Temporary left and right points
    var tempLeftPoint: [Double] = prevLeftPoint
    var tempRightPoint: [Double] = prevRightPoint

    // Keep track of whether the previous point is a sharp corner
    // ... so that we don't detect the same corner twice
    var isPrevPointSharpCorner = false

    // Scratch buffers for allocation-free hot loop calculations.
    var _offset: [Double] = [0, 0]
    var _tl: [Double] = [0, 0]
    var _tr: [Double] = [0, 0]

    /*
      Find the outline's left and right points

      Iterating through the points and populate the rightPts and leftPts arrays,
      skipping the first and last pointsm, which will get caps later on.
    */

    for i in 0..<points.count {
        var pressure = points[i].pressure
        let point = points[i].point
        let vector = points[i].vector
        let distance = points[i].distance
        let runningLength = points[i].runningLength
        let isLastPoint = i == points.count - 1

        // Removes noise from the end of the line
        if !isLastPoint && totalLength - runningLength < PFConstants.END_NOISE_THRESHOLD {
            continue
        }

        /*
          Calculate the radius

          If not thinning, the current point's radius will be half the size; or
          otherwise, the size will be based on the current (real or simulated)
          pressure.
        */

        if thinning != 0 {
            if shouldSimulatePressure {
                // If we're simulating pressure, then do so based on the distance
                // between the current point and the previous point, and the size
                // of the stroke. Otherwise, use the input pressure.
                pressure = simulatePressure(prevPressure: prevPressure, distance: distance, size: size)
            }

            radius = getStrokeRadius(size: size, thinning: thinning, pressure: pressure, easing: easing)
        } else {
            radius = size / 2
        }

        if firstRadius == nil {
            firstRadius = radius
        }

        /*
          Apply tapering

          If the current length is within the taper distance at either the
          start or the end, calculate the taper strengths. Apply the smaller
          of the two taper strengths to the radius.
        */

        let taperStartStrength = runningLength < taperStart
            ? taperStartEase(runningLength / taperStart)
            : 1.0

        let taperEndStrength = totalLength - runningLength < taperEnd
            ? taperEndEase((totalLength - runningLength) / taperEnd)
            : 1.0

        radius = max(
            PFConstants.MIN_RADIUS,
            radius * min(taperStartStrength, taperEndStrength)
        )

        /* Add points to left and right */

        /*
          Handle sharp corners

          Find the difference (dot product) between the current and next vector.
          If the next vector is at more than a right angle to the current vector,
          draw a cap at the current point.
        */

        let nextVector = (!isLastPoint ? points[i + 1] : points[i]).vector
        let nextDpr = !isLastPoint ? Vec.dpr(vector, nextVector) : 1.0
        let prevDpr = Vec.dpr(vector, prevVector)

        let isPointSharpCorner = prevDpr < 0 && !isPrevPointSharpCorner
        let isNextPointSharpCorner = nextDpr < 0

        if isPointSharpCorner || isNextPointSharpCorner {
            // It's a sharp corner. Draw a rounded cap and move on to the next point
            // Considering saving these and drawing them later? So that we can avoid
            // crossing future points.

            // Use mutable operations for the offset calculation
            Vec.perInto(&_offset, prevVector)
            Vec.mulInto(&_offset, _offset, radius)

            let step = 1.0 / Double(PFConstants.CORNER_CAP_SEGMENTS)
            var t = 0.0
            while t <= 1 {
                // Calculate left point: rotate (point - offset) around point
                Vec.subInto(&_tl, point, _offset)
                Vec.rotAroundInto(&_tl, _tl, point, PFConstants.FIXED_PI * t)
                tempLeftPoint = [_tl[0], _tl[1]]
                leftPts.append(tempLeftPoint)

                // Calculate right point: rotate (point + offset) around point
                Vec.addInto(&_tr, point, _offset)
                Vec.rotAroundInto(&_tr, _tr, point, PFConstants.FIXED_PI * -t)
                tempRightPoint = [_tr[0], _tr[1]]
                rightPts.append(tempRightPoint)

                t += step
            }

            prevLeftPoint = tempLeftPoint
            prevRightPoint = tempRightPoint

            if isNextPointSharpCorner {
                isPrevPointSharpCorner = true
            }
            continue
        }

        isPrevPointSharpCorner = false

        // Handle the last point
        if isLastPoint {
            Vec.perInto(&_offset, vector)
            Vec.mulInto(&_offset, _offset, radius)
            leftPts.append(Vec.sub(point, _offset))
            rightPts.append(Vec.add(point, _offset))
            continue
        }

        /*
          Add regular points

          Project points to either side of the current point, using the
          calculated size as a distance. If a point's distance to the
          previous point on that side greater than the minimum distance
          (or if the corner is kinda sharp), add the points to the side's
          points array.
        */

        // Use mutable operations for offset calculation
        Vec.lrpInto(&_offset, nextVector, vector, nextDpr)
        Vec.perInto(&_offset, _offset)
        Vec.mulInto(&_offset, _offset, radius)

        Vec.subInto(&_tl, point, _offset)
        tempLeftPoint = [_tl[0], _tl[1]]

        if i <= 1 || Vec.dist2(prevLeftPoint, tempLeftPoint) > minDistance {
            leftPts.append(tempLeftPoint)
            prevLeftPoint = tempLeftPoint
        }

        Vec.addInto(&_tr, point, _offset)
        tempRightPoint = [_tr[0], _tr[1]]

        if i <= 1 || Vec.dist2(prevRightPoint, tempRightPoint) > minDistance {
            rightPts.append(tempRightPoint)
            prevRightPoint = tempRightPoint
        }

        // Set variables for next iteration
        prevPressure = pressure
        prevVector = vector
    }

    /*
      Drawing caps

      Now that we have our points on either side of the line, we need to
      draw caps at the start and end. Tapered lines don't have caps, but
      may have dots for very short lines.
    */

    let firstPoint: [Double] = [points[0].point[0], points[0].point[1]]

    let lastPoint: [Double] = points.count > 1
        ? [points[points.count - 1].point[0], points[points.count - 1].point[1]]
        : Vec.add(points[0].point, PFConstants.UNIT_OFFSET)

    var startCap: [[Double]] = []
    var endCap: [[Double]] = []

    // Draw a dot for very short or completed strokes
    if points.count == 1 {
        if !(taperStart > 0 || taperEnd > 0) || isComplete {
            return drawDot(center: firstPoint, radius: firstRadius ?? radius)
        }
    } else {
        // Draw start cap (unless tapered)
        if taperStart > 0 || (taperEnd > 0 && points.count == 1) {
            // The start point is tapered, noop
        } else if capStart {
            startCap.append(contentsOf:
                drawRoundStartCap(center: firstPoint, rightPoint: rightPts[0], segments: PFConstants.START_CAP_SEGMENTS)
            )
        } else {
            startCap.append(contentsOf:
                drawFlatStartCap(center: firstPoint, leftPoint: leftPts[0], rightPoint: rightPts[0])
            )
        }

        // Draw end cap (unless tapered)
        let direction = Vec.per(Vec.neg(points[points.count - 1].vector))

        if taperEnd > 0 || (taperStart > 0 && points.count == 1) {
            // Tapered end - push the last point to the line
            endCap.append(lastPoint)
        } else if capEnd {
            endCap.append(contentsOf:
                drawRoundEndCap(center: lastPoint, direction: direction, radius: radius, segments: PFConstants.END_CAP_SEGMENTS)
            )
        } else {
            endCap.append(contentsOf:
                drawFlatEndCap(center: lastPoint, direction: direction, radius: radius)
            )
        }
    }

    /*
      Return the points in the correct winding order: begin on the left side, then
      continue around the end cap, then come back along the right side, and finally
      complete the start cap.
    */

    return leftPts + endCap + rightPts.reversed() + startCap
}
