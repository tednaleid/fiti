// ABOUTME: Swift-side property tests for the algorithm — invariants that must
// ABOUTME: hold regardless of fixture. Expanded across the port commits.

import Foundation
import Testing
@testable import PerfectFreehand

@Suite("Properties")
struct PropertyTests {
    @Test("StrokeOptions() defaults match TS getStroke fallback values")
    func defaults() {
        let opts = StrokeOptions()
        // From getStrokeOutlinePoints.ts destructuring (authoritative).
        #expect(opts.size == 16)
        #expect(opts.thinning == 0.5)
        #expect(opts.smoothing == 0.5)
        #expect(opts.streamline == 0.5)
        #expect(opts.simulatePressure == true)
        #expect(opts.last == false)
        #expect(opts.easing == nil)

        // TS `start = {}` / `end = {}` → cap: true, taper: undefined (→ none),
        // per-end easing is supplied internally by the algorithm (Swift treats nil
        // as "use the built-in linear/per-end default").
        #expect(opts.start.taper == .none)
        #expect(opts.start.cap == true)
        #expect(opts.start.easing == nil)
        #expect(opts.end.taper == .none)
        #expect(opts.end.cap == true)
        #expect(opts.end.easing == nil)
    }

    // MARK: - Invariants

    @Test("empty input produces empty output")
    func emptyInputEmptyOutput() {
        let result = getStroke(points: [InputPoint](), options: StrokeOptions())
        #expect(result.isEmpty)
    }

    @Test("single point produces a closed polygon centered near the input")
    func singlePointClosedPolygon() {
        let pt = InputPoint(x: 50, y: 50, pressure: 0.5)
        let opts = StrokeOptions(size: 8)
        let polygon = getStroke(points: [pt], options: opts)

        #expect(polygon.count >= 3, "expected a closed polygon, got \(polygon.count) vertices")

        // All vertices should sit within `size` distance of the input point
        // (a small disk; the cap rounding only adds ≤ size/2, but allow some
        // slack for the synthesized UNIT_OFFSET second point used internally).
        let maxDist = opts.size + 2.0
        for v in polygon {
            let dx = v.x - pt.x
            let dy = v.y - pt.y
            let dist = (dx * dx + dy * dy).squareRoot()
            #expect(dist <= maxDist, "vertex (\(v.x), \(v.y)) is \(dist) from (\(pt.x), \(pt.y)) > \(maxDist)")
        }
    }

    @Test("output polygon is closed for a non-empty stroke")
    func polygonIsClosed() {
        let input = [
            InputPoint(x: 10, y: 10, pressure: 0.5),
            InputPoint(x: 50, y: 10, pressure: 0.5),
            InputPoint(x: 90, y: 10, pressure: 0.5),
        ]
        var opts = StrokeOptions(size: 8)
        opts.last = true
        let polygon = getStroke(points: input, options: opts)

        #expect(polygon.count >= 3)

        // The polygon is "closed" in the topological sense: walking the vertex
        // list and back to vertex[0] traces a closed loop. The TS algorithm
        // doesn't duplicate the first vertex at the end, so we check that the
        // last vertex is reasonably close to the first (within roughly one
        // stroke-size of geometric closure).
        let first = polygon[0]
        let last = polygon[polygon.count - 1]
        let dx = last.x - first.x
        let dy = last.y - first.y
        let gap = (dx * dx + dy * dy).squareRoot()
        #expect(gap < opts.size, "polygon doesn't close: gap=\(gap) > size=\(opts.size)")
    }

    @Test("a straight horizontal stroke is symmetric about its centerline")
    func horizontalStrokeSymmetry() {
        let input = [
            InputPoint(x: 0, y: 0, pressure: 0.5),
            InputPoint(x: 50, y: 0, pressure: 0.5),
            InputPoint(x: 100, y: 0, pressure: 0.5),
        ]
        var opts = StrokeOptions(size: 8)
        opts.last = true
        let polygon = getStroke(points: input, options: opts)

        // The polygon's vertical extent must be symmetric about y=0: max y
        // above the line equals max |y| below the line within tight epsilon.
        // (The cap arcs aren't built with vertex-level mirror symmetry — the
        // start cap walks CCW from the left side, the end cap walks CCW from
        // the right side — so we assert the looser bounding-shape invariant
        // rather than vertex-by-vertex mirror.)
        let above = polygon.filter { $0.y > 0 }
        let below = polygon.filter { $0.y < 0 }
        #expect(!above.isEmpty)
        #expect(!below.isEmpty)
        let maxAbove = above.map { $0.y }.max() ?? 0
        let maxBelow = below.map { -$0.y }.max() ?? 0
        #expect(Swift.abs(maxAbove - maxBelow) <= 1e-9,
                "asymmetric peaks: above=\(maxAbove) below=\(maxBelow)")
    }

    @Test("scaling size by N scales max-perpendicular distance by ~N")
    func scaleByN() {
        let input = [
            InputPoint(x: 0, y: 0, pressure: 0.5),
            InputPoint(x: 100, y: 0, pressure: 0.5),
            InputPoint(x: 200, y: 0, pressure: 0.5),
        ]
        var small = StrokeOptions(size: 4)
        small.last = true
        var large = StrokeOptions(size: 8)
        large.last = true

        let polyS = getStroke(points: input, options: small)
        let polyL = getStroke(points: input, options: large)

        // Centerline is y=0; max perpendicular distance is max |y|.
        let maxS = polyS.map { Swift.abs($0.y) }.max() ?? 0
        let maxL = polyL.map { Swift.abs($0.y) }.max() ?? 0

        #expect(maxS > 0)
        #expect(maxL > 0)

        // size doubled → max |y| doubled. Allow ±5% slack for the streamline
        // / smoothing interactions that aren't perfectly linear.
        let ratio = maxL / maxS
        #expect(Swift.abs(ratio - 2.0) < 0.1, "ratio \(ratio) not within 0.1 of 2.0")
    }

    @Test("last: false vs last: true produce different tail geometry")
    func lastFlagChangesGeometry() {
        let input = [
            InputPoint(x: 10, y: 10, pressure: 0.5),
            InputPoint(x: 50, y: 30, pressure: 0.5),
            InputPoint(x: 90, y: 10, pressure: 0.5),
        ]
        var optsFalse = StrokeOptions(size: 8)
        optsFalse.last = false
        var optsTrue = StrokeOptions(size: 8)
        optsTrue.last = true

        let polyFalse = getStroke(points: input, options: optsFalse)
        let polyTrue = getStroke(points: input, options: optsTrue)

        // Both should be non-empty closed polygons.
        #expect(polyFalse.count >= 3)
        #expect(polyTrue.count >= 3)

        // The vertex arrays must differ — last: true emits the final input
        // point exactly while last: false interpolates via streamline.
        let equal = polyFalse.count == polyTrue.count
            && zip(polyFalse, polyTrue).allSatisfy { a, b in
                Swift.abs(a.x - b.x) <= 1e-12 && Swift.abs(a.y - b.y) <= 1e-12
            }
        #expect(!equal, "polygons unexpectedly equal for last:false vs last:true")
    }

    @Test("a monotonic straight-line input produces a non-self-intersecting side body")
    func monotonicNonSelfIntersecting() {
        let input = [
            InputPoint(x: 0, y: 0, pressure: 0.5),
            InputPoint(x: 50, y: 0, pressure: 0.5),
            InputPoint(x: 100, y: 0, pressure: 0.5),
            InputPoint(x: 150, y: 0, pressure: 0.5),
            InputPoint(x: 200, y: 0, pressure: 0.5),
        ]
        var opts = StrokeOptions(size: 8)
        opts.last = true
        let polygon = getStroke(points: input, options: opts)

        guard polygon.count >= 4 else {
            Issue.record("polygon too small: \(polygon.count)")
            return
        }

        // The perfect-freehand algorithm allows minor self-intersection inside
        // the rounded end-cap regions (adjacent cap-arc steps can produce
        // overlapping triangles when the cap walks around the final input
        // point with fine angular steps). The body of the stroke — the two
        // long side runs joining the caps — must NOT self-intersect.
        //
        // We isolate the body by keeping only edges where |y| > size/2 - cap
        // tolerance, i.e. the long side runs that ride near the offset
        // distance. The cap regions sweep across y=0 so all cap edges have an
        // endpoint with |y| < size/2.
        let bodyThreshold = (opts.size / 2) - 1.5
        let n = polygon.count
        var bodyEdges: [(Point2D, Point2D)] = []
        for i in 0..<n {
            let a = polygon[i]
            let b = polygon[(i + 1) % n]
            // Keep edges where both endpoints sit clearly on a side run.
            if Swift.abs(a.y) > bodyThreshold && Swift.abs(b.y) > bodyThreshold {
                // Both on same side (no cap-traversal edge).
                if (a.y > 0) == (b.y > 0) {
                    bodyEdges.append((a, b))
                }
            }
        }

        #expect(bodyEdges.count >= 2, "found only \(bodyEdges.count) body edges; cap-isolation logic broke")

        // Skip pairs whose endpoints are near-coincident: the cap/side boundary
        // produces edges that share an endpoint within ~1e-3 (the algorithm
        // walks the cap with fine angular steps that arrive close to but not
        // exactly at the side-run vertex).
        let coincidentEps = 1e-2
        func near(_ p: Point2D, _ q: Point2D) -> Bool {
            Swift.abs(p.x - q.x) <= coincidentEps && Swift.abs(p.y - q.y) <= coincidentEps
        }
        for i in 0..<bodyEdges.count {
            for j in (i + 1)..<bodyEdges.count {
                let (a, b) = bodyEdges[i]
                let (c, d) = bodyEdges[j]
                if near(a, c) || near(a, d) || near(b, c) || near(b, d) { continue }
                #expect(
                    !segmentsCross(a, b, c, d),
                    "body edges \(i) and \(j) cross: (\(a.x),\(a.y))->(\(b.x),\(b.y)) vs (\(c.x),\(c.y))->(\(d.x),\(d.y))"
                )
            }
        }
    }

    @Test("getStroke on 1000-point input completes in reasonable time")
    func perfSanity() {
        let input = (0..<1000).map { i in
            InputPoint(x: Double(i), y: sin(Double(i) / 50) * 100, pressure: nil)
        }
        let start = Date()
        _ = getStroke(points: input, options: StrokeOptions())
        let elapsed = Date().timeIntervalSince(start)
        print("getStroke 1000pts: \(elapsed * 1000) ms")
        #expect(elapsed < 0.5) // catches really-broken-only failures
    }
}

// MARK: - Geometry helpers

/// Returns true when segments (a,b) and (c,d) properly intersect (strict —
/// shared endpoints don't count). Uses the standard CCW / parametric form.
private func segmentsCross(_ a: Point2D, _ b: Point2D, _ c: Point2D, _ d: Point2D) -> Bool {
    func ccw(_ p: Point2D, _ q: Point2D, _ r: Point2D) -> Double {
        return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
    }
    let d1 = ccw(c, d, a)
    let d2 = ccw(c, d, b)
    let d3 = ccw(a, b, c)
    let d4 = ccw(a, b, d)
    // Strict crossing: endpoints on opposite sides of the other segment.
    let eps = 1e-12
    if ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps))
        && ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps)) {
        return true
    }
    return false
}
