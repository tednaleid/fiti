// ABOUTME: Tests for getStrokePoints — mirrors perfect-freehand@1.2.3's
// ABOUTME: getStrokePoints.spec.ts shape, plus regression cases pinned to
// ABOUTME: the upstream snapshot file.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("GetStrokePoints")
struct GetStrokePointsTests {
    // MARK: - Helpers

    private struct P: StrokeInputPoint {
        let x: Double
        let y: Double
        let pressure: Double?
        init(_ x: Double, _ y: Double, _ pressure: Double? = nil) {
            self.x = x; self.y = y; self.pressure = pressure
        }
    }

    private func expectClose(_ a: Double, _ b: Double, abs tolerance: Double = 1e-12) {
        #expect(Swift.abs(a - b) <= tolerance, "\(a) vs \(b)")
    }

    private func expectClose(_ a: [Double], _ b: [Double], abs tolerance: Double = 1e-12) {
        #expect(a.count == b.count)
        for (i, (x, y)) in zip(a, b).enumerated() {
            #expect(Swift.abs(x - y) <= tolerance, "index \(i): \(x) vs \(y)")
        }
    }

    private func containsNaN(_ sp: StrokePoint) -> Bool {
        sp.point.contains(where: { $0.isNaN })
            || sp.vector.contains(where: { $0.isNaN })
            || sp.distance.isNaN
            || sp.pressure.isNaN
            || sp.runningLength.isNaN
    }

    // MARK: - Empty input

    @Test("empty input -> empty output")
    func emptyInput() {
        let result = getStrokePoints(points: [P]())
        #expect(result.isEmpty)
    }

    // MARK: - Single point

    @Test("single point produces two points (input + UNIT_OFFSET-shifted clone)")
    func singlePointExpands() {
        // Mirrors upstream `onePoint` fixture: [[464.91, 286.51]] with no
        // pressure. The single-point expansion appends an [x+1, y+1] clone;
        // the streamline then carries the second emitted point only 0.575
        // of the way from input toward the clone, so the second point sits
        // at [input + 0.575, input + 0.575] — pinned to upstream snapshot.
        //
        // Snapshot reference: getStrokePoints.spec.ts.snap "one-point".
        // (Note: the snapshot shows pressure=0.25 because the TS test uses
        //  the array-input path; our object-input protocol uses the TS
        //  object-path semantics, so first pressure is DEFAULT_PRESSURE.)
        let result = getStrokePoints(points: [P(464.91, 286.51)])
        #expect(result.count == 2)
        expectClose(result[0].point, [464.91, 286.51])
        #expect(result[0].distance == 0)
        #expect(result[0].runningLength == 0)
        #expect(result[0].pressure == 0.5)  // object-path DEFAULT_PRESSURE
        #expect(result[1].pressure == 0.5)
        // Streamlined second point — not the unit-offset position.
        expectClose(result[1].point, [465.485, 287.085])
        // Vector points back toward prev: uni([-0.575, -0.575]) = [-√½, -√½].
        let r = sqrt(2.0) / 2.0
        expectClose(result[1].vector, [-r, -r])
        // First point's vector mirrors the second's (post-pass fix-up).
        expectClose(result[0].vector, [-r, -r])
        // dist = sqrt(0.575² + 0.575²) = 0.8131727983645136 (snapshot pin).
        expectClose(result[1].distance, 0.8131727983645136)
        expectClose(result[1].runningLength, 0.8131727983645136)
    }

    // MARK: - Two equal points

    @Test("two equal points collapse to a single stroke point")
    func twoEqualPoints() {
        // Mirrors upstream `twoEqualPoints`: [[1,1],[1,1]] → after the
        // 2-point expansion every interpolated point is identical to [1,1],
        // so isEqual short-circuits the loop and only the seed stroke
        // point survives. Its vector is [0,0] because there's no second
        // point to inherit from.
        //
        // Pressure is 0.5 (object-path DEFAULT_PRESSURE) — see the spec on
        // `getStrokePoints` for why this differs from the upstream
        // array-path snapshot (which shows 0.25).
        let result = getStrokePoints(points: [P(1, 1), P(1, 1)])
        #expect(result.count == 1)
        #expect(result[0].point == [1, 1])
        #expect(result[0].vector == [0, 0])
        #expect(result[0].distance == 0)
        #expect(result[0].runningLength == 0)
        #expect(result[0].pressure == 0.5)
    }

    // MARK: - Two distinct points expand to 5

    @Test("two distinct points expand to 5 internal points before streamlining")
    func twoDistinctPoints() {
        // Mirrors `twoPoints`: [[10,200],[10,0]] in TS array form (no
        // pressure). With Swift's object-path semantics, nil pressure
        // becomes DEFAULT_PRESSURE for every input — including the first.
        //
        // The 5-point expansion gives pts = [[10,200],[10,150],[10,100],
        // [10,50],[10,0]]. Streamline t = 0.575. Size = 16 so the start-
        // of-line noise-skip kicks in until runningLength >= 16.
        //
        // i=1: point = lrp([10,200],[10,150], 0.575) = [10, 171.25]
        //      distance = 28.75; runningLength = 28.75; 28.75 >= 16 -> emit
        // i=2: point = lrp([10,171.25],[10,100], 0.575) = [10, 130.28125]
        //      distance = 40.96875; runningLength = 69.71875
        // i=3: point = lrp([10,130.28125],[10,50], 0.575) = [10, 84.1195...]
        // i=4: point = lrp([10, 84.1195...],[10,0], 0.575) = [10, 35.7508...]
        let result = getStrokePoints(points: [P(10, 200), P(10, 0)])
        #expect(result.count == 5)

        // Seed + four interpolated emissions.
        expectClose(result[0].point, [10, 200])
        #expect(result[0].distance == 0)
        #expect(result[0].runningLength == 0)

        expectClose(result[1].point, [10, 171.25])
        expectClose(result[1].distance, 28.75)
        expectClose(result[1].runningLength, 28.75)

        expectClose(result[2].point, [10, 130.28125])
        expectClose(result[2].distance, 40.96875)
        expectClose(result[2].runningLength, 69.71875)

        expectClose(result[3].point, [10, 84.11953125])
        expectClose(result[3].distance, 46.161718750000006)
        expectClose(result[3].runningLength, 115.88046875)

        expectClose(result[4].point, [10, 35.75080078125])
        expectClose(result[4].distance, 48.368730468749995)
        expectClose(result[4].runningLength, 164.24919921875)

        // Each emitted point's vector points from current back toward prev,
        // i.e. uni(prev - point). For a vertically-descending path the
        // vector is [0, 1] at every point.
        for sp in result { expectClose(sp.vector, [0, 1]) }
    }

    // MARK: - Object input matches TS snapshot

    @Test("object input matches upstream getStrokePoints snapshot (regression)")
    func objectPairsSnapshot() {
        // `objectPairs` fixture in TS:
        //   [{0,0},{10,0},{20,0},{25,5},{30,5}] (no pressure)
        // Pinned to upstream snapshot — see
        // getStrokePoints.spec.ts.snap "object-pairs" block.
        let result = getStrokePoints(points: [
            P(0, 0), P(10, 0), P(20, 0), P(25, 5), P(30, 5)
        ])
        #expect(result.count == 4)

        // [0] seed point — vector is the second point's vector after fix-up.
        expectClose(result[0].point, [0, 0])
        #expect(result[0].pressure == 0.5)
        expectClose(result[0].vector, [-1, 0])
        #expect(result[0].distance == 0)
        #expect(result[0].runningLength == 0)

        // [1] first survivor of the noise-skip
        expectClose(result[1].point, [11.5, 0])
        expectClose(result[1].distance, 11.5)
        expectClose(result[1].runningLength, 17.25)
        expectClose(result[1].vector, [-1, 0])

        // [2]
        expectClose(result[2].point, [19.2625, 2.875])
        expectClose(result[2].distance, 8.277803528110582)
        expectClose(result[2].runningLength, 25.52780352811058)
        expectClose(result[2].vector, [-0.9377487607237036, -0.347314355823594])

        // [3]
        expectClose(result[3].point, [25.4365625, 4.096875])
        expectClose(result[3].distance, 6.293808566323833)
        expectClose(result[3].runningLength, 31.821612094434414)
        expectClose(result[3].vector, [-0.9809739897453262, -0.19413920635239276])
    }

    // MARK: - Streamline parameter

    @Test("streamline=0 lets points jump fully to the input position")
    func streamlineZeroPullsAllTheWay() {
        // streamline=0 -> t = 0.15 + 1 * 0.85 = 1.0
        // So lrp(prev, current, 1.0) == current — emitted points coincide
        // with the input (after noise-skip).
        var opts = StrokeOptions()
        opts.streamline = 0
        opts.size = 1   // disable the noise-skip for this case
        let input = [P(0, 0), P(10, 0), P(20, 0)]
        let result = getStrokePoints(points: input, options: opts)
        // 3-point input doesn't trip the 2-point expansion.
        #expect(result.count == 3)
        expectClose(result[1].point, [10, 0])
        expectClose(result[2].point, [20, 0])
    }

    @Test("streamline=1 produces the most aggressive low-pass smoothing")
    func streamlineOneSmoothsMost() {
        // streamline=1 -> t = MIN_STREAMLINE_T = 0.15.
        // Each emitted point only moves 15% of the way from the previous
        // emitted point toward the next input — strong damping.
        var opts = StrokeOptions()
        opts.streamline = 1
        opts.size = 1
        let result = getStrokePoints(points: [P(0, 0), P(100, 0)], options: opts)
        // 2-point expansion makes pts = [[0,0],[25,0],[50,0],[75,0],[100,0]]
        // i=1: point = lrp([0,0],[25,0], 0.15) = [3.75, 0]
        #expect(result.count == 5)
        expectClose(result[1].point, [3.75, 0])
    }

    // MARK: - last:true

    @Test("last:true lands the final emitted point exactly on the final input")
    func lastTrueLandsExactly() {
        // With last=true and i==max, the algorithm uses the raw input point
        // rather than the streamlined lrp position.
        var opts = StrokeOptions()
        opts.last = true
        opts.size = 1
        let input = [P(0, 0), P(10, 0), P(100, 0)]
        let result = getStrokePoints(points: input, options: opts)
        // Final emitted point matches the final input verbatim.
        expectClose(result.last!.point, [100, 0])
    }

    @Test("last:false (default) interpolates to the final input via streamline t")
    func lastFalseInterpolates() {
        var opts = StrokeOptions()
        opts.last = false
        opts.streamline = 0.5
        opts.size = 1
        let input = [P(0, 0), P(10, 0), P(100, 0)]
        let result = getStrokePoints(points: input, options: opts)
        // Final emitted point should NOT match the raw last input; it lands
        // between the previous emitted point and (100, 0) at t=0.575.
        #expect(result.last!.point[0] != 100)
    }

    // MARK: - Pressure handling

    @Test("explicit pressure values flow through to the output")
    func explicitPressure() {
        let input = [P(0, 0, 0.7), P(50, 0, 0.3), P(100, 0, 0.9)]
        var opts = StrokeOptions()
        opts.size = 1
        let result = getStrokePoints(points: input, options: opts)
        #expect(result.count == 3)
        // First point keeps its explicit pressure (isValidPressure -> true).
        #expect(result[0].pressure == 0.7)
        #expect(result[1].pressure == 0.3)
        #expect(result[2].pressure == 0.9)
    }

    @Test("negative pressure is treated as invalid and falls back to defaults")
    func negativePressureInvalid() {
        let input = [P(0, 0, -0.1), P(100, 0, -0.5)]
        var opts = StrokeOptions()
        opts.size = 1
        let result = getStrokePoints(points: input, options: opts)
        // First point: -0.1 is invalid -> DEFAULT_FIRST_PRESSURE.
        #expect(result[0].pressure == 0.25)
        // Subsequent: -0.5 is invalid -> DEFAULT_PRESSURE.
        // Note: 2-point expansion strips pressure from interpolated points
        // anyway, so the test really only constrains the first point.
        for sp in result.dropFirst() {
            #expect(sp.pressure == 0.5)
        }
    }

    // MARK: - Duplicate-skip

    @Test("identical consecutive points after streamline are skipped")
    func duplicatesSkipped() {
        // Many identical points should produce only one stroke point.
        let input = [P(5, 5), P(5, 5), P(5, 5), P(5, 5)]
        var opts = StrokeOptions()
        opts.size = 1
        let result = getStrokePoints(points: input, options: opts)
        #expect(result.count == 1)
        #expect(result[0].point == [5, 5])
        #expect(result[0].vector == [0, 0])
    }

    // MARK: - Running length monotonicity

    @Test("runningLength is non-decreasing across all emitted points")
    func runningLengthMonotonic() {
        var opts = StrokeOptions()
        opts.size = 1
        let input = (0..<10).map { P(Double($0) * 5, sin(Double($0)) * 5) }
        let result = getStrokePoints(points: input, options: opts)
        for i in 1..<result.count {
            #expect(result[i].runningLength >= result[i - 1].runningLength)
        }
    }

    // MARK: - No NaN production

    @Test("no NaN values produced for a range of inputs")
    func noNaNs() {
        let fixtures: [[P]] = [
            [],                                                       // empty
            [P(464.91, 286.51)],                                      // single
            [P(10, 200), P(10, 0)],                                   // two distinct
            [P(1, 1), P(1, 1)],                                       // two equal
            [P(0, 0), P(10, 0), P(20, 0), P(25, 5), P(30, 5)],        // objectPairs
            [P(0, 0), P(0, 0), P(0, 0), P(0, 0), P(0, 0),             // withDuplicates-ish
             P(10, 10), P(10, 10), P(100, 100), P(0, 0)],
        ]
        for input in fixtures {
            let result = getStrokePoints(points: input)
            for sp in result {
                #expect(!containsNaN(sp), "NaN in result for input of count \(input.count)")
            }
        }
    }
}
