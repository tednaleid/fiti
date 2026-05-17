// ABOUTME: Tests for simulatePressure — first-principles coverage of the
// ABOUTME: velocity-to-pressure synthesis from perfect-freehand@1.2.3.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("SimulatePressure")
struct SimulatePressureTests {
    // MARK: - Float-tolerant comparison helper

    private func expectClose(_ a: Double, _ b: Double, abs tolerance: Double = 1e-12) {
        #expect(Swift.abs(a - b) <= tolerance, "\(a) vs \(b)")
    }

    // MARK: - Regression cases (computed BY HAND from the TS source)

    /// Hand-computed:
    ///   sp = min(1, 4/16)          = 0.25
    ///   rp = min(1, 1 - 0.25)      = 0.75
    ///   result = min(1, 0.25 + (0.75 - 0.25) * (0.25 * 0.275))
    ///          = 0.25 + 0.5 * 0.06875
    ///          = 0.284375
    @Test("regression: prev=0.25, distance=4, size=16 -> 0.284375")
    func regressionMidStroke() {
        let result = simulatePressure(prevPressure: 0.25, distance: 4, size: 16)
        expectClose(result, 0.284375)
    }

    /// Hand-computed (fast stroke saturates sp=1, drives rp=0):
    ///   sp = min(1, 20/16)         = 1
    ///   rp = min(1, 1 - 1)         = 0
    ///   result = min(1, 0.5 + (0 - 0.5) * (1 * 0.275))
    ///          = 0.5 - 0.1375
    ///          = 0.3625
    @Test("regression: fast stroke (distance > size) drops pressure")
    func regressionFastStroke() {
        let result = simulatePressure(prevPressure: 0.5, distance: 20, size: 16)
        expectClose(result, 0.3625)
    }

    /// Hand-computed:
    ///   sp = 2/16                  = 0.125
    ///   rp = 1 - 0.125             = 0.875
    ///   result = 0.5 + (0.875 - 0.5) * (0.125 * 0.275)
    ///          = 0.5 + 0.375 * 0.034375
    ///          = 0.512890625
    @Test("regression: slow stroke (distance << size) raises pressure")
    func regressionSlowStroke() {
        let result = simulatePressure(prevPressure: 0.5, distance: 2, size: 16)
        expectClose(result, 0.512890625)
    }

    // MARK: - Behavioural properties

    @Test("first-point case (prev=0, distance=0) stays at zero")
    func startingZeroNoMovement() {
        // sp=0, rp=1, but rate factor is sp*RATE = 0, so result = prev + 0 = 0.
        let result = simulatePressure(prevPressure: 0, distance: 0, size: 16)
        expectClose(result, 0)
    }

    @Test("zero distance never changes pressure regardless of prev")
    func zeroDistanceIsFixedPoint() {
        for prev in stride(from: 0.0, through: 1.0, by: 0.1) {
            let result = simulatePressure(prevPressure: prev, distance: 0, size: 16)
            expectClose(result, prev)
        }
    }

    @Test("result is always in [0, 1] for sane inputs")
    func resultClampedToUnitInterval() {
        // Sweep a variety of inputs; output must always lie within [0, 1].
        let prevs: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 0.99, 1.0]
        let distances: [Double] = [0, 0.5, 1, 4, 16, 32, 1000]
        let sizes: [Double] = [1, 8, 16, 64]
        for prev in prevs {
            for distance in distances {
                for size in sizes {
                    let result = simulatePressure(prevPressure: prev, distance: distance, size: size)
                    #expect(result >= 0, "result \(result) < 0 for prev=\(prev) d=\(distance) size=\(size)")
                    #expect(result <= 1, "result \(result) > 1 for prev=\(prev) d=\(distance) size=\(size)")
                }
            }
        }
    }

    @Test("faster strokes produce lower pressure than slower strokes")
    func fasterMeansLower() {
        // From the same prevPressure, a larger distance step should yield
        // pressure that's no greater than (and usually less than) a smaller
        // distance step. This holds because sp grows with distance, and the
        // (rp - prev) term flips sign as sp passes (1 - prev).
        let prev = 0.5
        let size = 16.0
        let slow = simulatePressure(prevPressure: prev, distance: 2, size: size)
        let fast = simulatePressure(prevPressure: prev, distance: 20, size: size)
        #expect(slow > fast)
    }

    @Test("with small steady distance, pressure converges toward a stable value")
    func iteratesTowardEquilibrium() {
        // Iterating with a small steady distance should drive pressure
        // monotonically upward from a low start, and asymptote below 1.
        // (The equilibrium is the fixed point of x = x + (1-sp - x) * sp*R,
        // i.e. x = 1 - sp = 0.9375 when sp = 0.0625.)
        var pressure = 0.1
        let distance = 1.0
        let size = 16.0
        var prev = pressure
        for _ in 0..<10_000 {
            pressure = simulatePressure(prevPressure: pressure, distance: distance, size: size)
            #expect(pressure >= prev, "pressure should be non-decreasing while below equilibrium")
            prev = pressure
        }
        // After many iterations we should be very close to the equilibrium 0.9375.
        expectClose(pressure, 1.0 - (distance / size), abs: 1e-9)
    }

    @Test("equilibrium ceiling never exceeds 1.0 even with extreme prev")
    func extremePrevStaysBounded() {
        // Even if prev is way out of range, min(...) clamps to 1.
        let result = simulatePressure(prevPressure: 5.0, distance: 4, size: 16)
        #expect(result <= 1.0)
    }
}
