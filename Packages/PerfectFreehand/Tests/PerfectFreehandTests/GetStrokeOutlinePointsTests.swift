// ABOUTME: Tests for getStrokeOutlinePoints — mirrors perfect-freehand@1.2.3's
// ABOUTME: getStrokeOutlinePoints.spec.ts shape/property cases; snapshot-based
// ABOUTME: byte-parity is deferred to the cross-language fixture work.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("GetStrokeOutlinePoints")
struct GetStrokeOutlinePointsTests {
    // MARK: - Helpers

    private struct P: StrokeInputPoint {
        let x: Double
        let y: Double
        let pressure: Double?
        init(_ x: Double, _ y: Double, _ pressure: Double? = nil) {
            self.x = x; self.y = y; self.pressure = pressure
        }
    }

    private func expectClose(_ a: Double, _ b: Double, abs tolerance: Double = 1e-9) {
        #expect(Swift.abs(a - b) <= tolerance, "\(a) vs \(b)")
    }

    private func containsNaN(_ v: [Double]) -> Bool {
        v.contains(where: { $0.isNaN })
    }

    private func anyNaN(_ outline: [[Double]]) -> Bool {
        outline.contains(where: containsNaN)
    }

    // Upstream inputs.json key fixtures inlined.
    private let onePoint: [P] = [P(464.91, 286.51)]
    private let twoPoints: [P] = [P(10, 200), P(10, 0)]
    private let twoEqualPoints: [P] = [P(1, 1), P(1, 1)]
    // Mirrors a slim slice of the upstream `manyPoints` fixture — enough
    // variation to exercise the corner/segment logic.
    private let manyPoints: [P] = [
        P(0, 0), P(10, 0), P(20, 0), P(25, 5), P(30, 5),
        P(40, 10), P(50, 12), P(60, 10), P(70, 5), P(80, 0),
    ]
    private let withDuplicates: [P] = [
        P(0, 0), P(0, 0), P(0, 0), P(0, 0), P(0, 0),
        P(10, 10), P(10, 10), P(10, 10), P(10, 10), P(10, 10),
        P(20, 5), P(30, 0), P(40, -5),
    ]

    // MARK: - Empty input

    @Test("empty input returns empty outline")
    func emptyInput() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: [P]()))
        #expect(result.isEmpty)
    }

    @Test("non-positive size returns empty outline")
    func nonPositiveSize() {
        var opts = StrokeOptions()
        opts.size = 0
        let result = getStrokeOutlinePoints(
            points: getStrokePoints(points: twoPoints, options: opts),
            options: opts
        )
        #expect(result.isEmpty)

        opts.size = -5
        let neg = getStrokeOutlinePoints(
            points: getStrokePoints(points: twoPoints, options: opts),
            options: opts
        )
        #expect(neg.isEmpty)
    }

    // MARK: - Mirrors `runs ${key} without generating NaN values`

    @Test("single point produces no NaN values")
    func singlePointNoNaN() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: onePoint))
        #expect(!result.isEmpty)
        #expect(!anyNaN(result))
    }

    @Test("two points produce no NaN values")
    func twoPointsNoNaN() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: twoPoints))
        #expect(!result.isEmpty)
        #expect(!anyNaN(result))
    }

    @Test("two equal points produce no NaN values")
    func twoEqualPointsNoNaN() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: twoEqualPoints))
        // Two equal points collapse to a single stroke point that walks the
        // single-point branch — should yield a small dot outline without NaN.
        #expect(!anyNaN(result))
    }

    @Test("many points produce no NaN values")
    func manyPointsNoNaN() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: manyPoints))
        #expect(!result.isEmpty)
        #expect(!anyNaN(result))
    }

    @Test("input with duplicates produces no NaN values")
    func duplicatesNoNaN() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: withDuplicates))
        #expect(!result.isEmpty)
        #expect(!anyNaN(result))
    }

    // MARK: - Single stroke-point → dot

    @Test("single stroke-point input takes the drawDot branch")
    func singleStrokePointDot() {
        // Construct a single StrokePoint directly (bypassing getStrokePoints,
        // which would expand a single input into 2 stroke points). This
        // exercises the `if points.length === 1` dot branch.
        let sp = StrokePoint(
            point: [10, 10],
            pressure: 0.5,
            distance: 0,
            vector: [0, 0],
            runningLength: 0
        )
        let result = getStrokeOutlinePoints(points: [sp])
        // drawDot emits START_CAP_SEGMENTS vertices (13).
        #expect(result.count == PFConstants.START_CAP_SEGMENTS)
        #expect(!anyNaN(result))
        for v in result {
            #expect(v.count == 2)
        }
    }

    @Test("single stroke-point with taper and last:false returns empty")
    func singleStrokePointTaperedIncomplete() {
        // With a taper set AND last=false, the dot branch is skipped (the
        // condition `!(taperStart || taperEnd) || isComplete` is false), and
        // since there's only one point the loop emits nothing into leftPts/
        // rightPts beyond the regular-point handling — but the cap drawing
        // is in the `else` (points.count > 1) branch, so startCap/endCap stay
        // empty. The final concat is the loop-emitted points only.
        var opts = StrokeOptions()
        opts.start = TaperOptions(taper: .length(10), cap: true)
        opts.last = false
        let sp = StrokePoint(
            point: [10, 10],
            pressure: 0.5,
            distance: 0,
            vector: [0, 0],
            runningLength: 0
        )
        let result = getStrokeOutlinePoints(points: [sp], options: opts)
        // The single-point branch is skipped (tapered + not complete).
        // The loop emits one left + one right point for the isLastPoint
        // case (i == 0 == points.count - 1). Final concat: left + [] + right.
        // No caps. Exactly 2 vertices.
        #expect(result.count == 2)
        #expect(!anyNaN(result))
    }

    @Test("single stroke-point with taper but last:true still produces a dot")
    func singleStrokePointTaperedComplete() {
        var opts = StrokeOptions()
        opts.start = TaperOptions(taper: .length(10), cap: true)
        opts.last = true
        let sp = StrokePoint(
            point: [10, 10],
            pressure: 0.5,
            distance: 0,
            vector: [0, 0],
            runningLength: 0
        )
        let result = getStrokeOutlinePoints(points: [sp], options: opts)
        // isComplete short-circuits to drawDot regardless of taper.
        #expect(result.count == PFConstants.START_CAP_SEGMENTS)
        #expect(!anyNaN(result))
    }

    // MARK: - Two-point polygon shape

    @Test("two-point stroke produces a closed polygon with caps")
    func twoPointsPolygon() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: twoPoints))
        // Should have at least 3 vertices to form a polygon.
        #expect(result.count >= 3)
        #expect(!anyNaN(result))
    }

    // MARK: - Cap variations

    @Test("flat start cap emits 4 extra vertices vs no start cap")
    func flatStartCap() {
        var optsRound = StrokeOptions()
        optsRound.start = TaperOptions(taper: .none, cap: true)
        let roundResult = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsRound),
            options: optsRound
        )

        var optsFlat = StrokeOptions()
        optsFlat.start = TaperOptions(taper: .none, cap: false)
        let flatResult = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsFlat),
            options: optsFlat
        )

        // Round start cap = START_CAP_SEGMENTS (13) vertices.
        // Flat start cap = 4 vertices.
        // Difference should be START_CAP_SEGMENTS - 4 = 9.
        #expect(roundResult.count - flatResult.count == PFConstants.START_CAP_SEGMENTS - 4)
    }

    @Test("flat end cap emits 4 vertices vs round end cap segments")
    func flatEndCap() {
        var optsRound = StrokeOptions()
        optsRound.end = TaperOptions(taper: .none, cap: true)
        let roundResult = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsRound),
            options: optsRound
        )

        var optsFlat = StrokeOptions()
        optsFlat.end = TaperOptions(taper: .none, cap: false)
        let flatResult = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsFlat),
            options: optsFlat
        )

        // Round end cap loop is `for t = step; t < 1; t += step` with step
        // 1/END_CAP_SEGMENTS. Because float accumulation lands the 28th step
        // at 0.999...96 (just under 1), the loop emits END_CAP_SEGMENTS = 29
        // vertices in practice. Flat end cap emits 4. Identical in TS and
        // Swift since both use IEEE 754 doubles.
        let expectedRoundEndCount = PFConstants.END_CAP_SEGMENTS
        let expectedFlatEndCount = 4
        #expect(roundResult.count - flatResult.count == expectedRoundEndCount - expectedFlatEndCount)
    }

    // MARK: - Tapered start drops the start cap

    @Test("tapered start drops the start cap entirely")
    func taperedStartNoCap() {
        var optsCap = StrokeOptions()
        optsCap.start = TaperOptions(taper: .none, cap: true)
        let withCap = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsCap),
            options: optsCap
        )

        var optsTaper = StrokeOptions()
        optsTaper.start = TaperOptions(taper: .length(20), cap: true)
        let withTaper = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsTaper),
            options: optsTaper
        )

        // Tapered version omits the START_CAP_SEGMENTS cap vertices.
        #expect(withCap.count - withTaper.count == PFConstants.START_CAP_SEGMENTS)
    }

    // MARK: - Tapered end emits single lastPoint, not full cap

    @Test("tapered end emits a single point instead of the rounded end cap")
    func taperedEndOnePoint() {
        var optsCap = StrokeOptions()
        optsCap.end = TaperOptions(taper: .none, cap: true)
        let withCap = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsCap),
            options: optsCap
        )

        var optsTaper = StrokeOptions()
        optsTaper.end = TaperOptions(taper: .length(20), cap: true)
        let withTaper = getStrokeOutlinePoints(
            points: getStrokePoints(points: manyPoints, options: optsTaper),
            options: optsTaper
        )

        // Tapered end emits a single lastPoint; rounded end emits
        // END_CAP_SEGMENTS points (see flatEndCap test for the float-loop
        // accumulation explanation). Difference: END_CAP_SEGMENTS - 1.
        #expect(withCap.count - withTaper.count == PFConstants.END_CAP_SEGMENTS - 1)
    }

    // MARK: - Two equal points yield a dot via the single-point branch

    @Test("two equal points yield a dot polygon (single-point branch)")
    func twoEqualPointsDot() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: twoEqualPoints))
        // Two equal points collapse to one stroke point, which walks the
        // single-point branch and emits a dot (START_CAP_SEGMENTS vertices)
        // because there are no tapers.
        #expect(result.count == PFConstants.START_CAP_SEGMENTS)
        #expect(!anyNaN(result))
    }

    // MARK: - All vertices are 2-element [x, y] arrays

    @Test("every emitted vertex is a 2-element [Double] array")
    func allVerticesAreXY() {
        let result = getStrokeOutlinePoints(points: getStrokePoints(points: manyPoints))
        for v in result {
            #expect(v.count == 2)
        }
    }
}
