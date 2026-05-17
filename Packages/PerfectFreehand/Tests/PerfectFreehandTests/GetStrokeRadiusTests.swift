// ABOUTME: Tests for getStrokeRadius — mirrors perfect-freehand@1.2.3's
// ABOUTME: getStrokeRadius.spec.ts 1:1 in Swift Testing form.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("GetStrokeRadius")
struct GetStrokeRadiusTests {
    // MARK: - Float-tolerant comparison helper

    private func expectClose(_ a: Double, _ b: Double, abs tolerance: Double = 1e-12) {
        #expect(Swift.abs(a - b) <= tolerance, "\(a) vs \(b)")
    }

    // MARK: - thinning = 0 → always half the size (ports `when thinning is zero`)

    @Test("when thinning is zero, uses half the size regardless of pressure")
    func zeroThinningHalfSize() {
        #expect(getStrokeRadius(size: 100, thinning: 0, pressure: 0) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 0, pressure: 0.25) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 0, pressure: 0.5) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 0, pressure: 0.75) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 0, pressure: 1) == 50)
    }

    // MARK: - positive thinning (ports `when thinning is positive`)

    @Test("at 0.5 thinning, scales between 25% and 75%")
    func positiveHalfThinning() {
        #expect(getStrokeRadius(size: 100, thinning: 0.5, pressure: 0) == 25)
        #expect(getStrokeRadius(size: 100, thinning: 0.5, pressure: 0.25) == 37.5)
        #expect(getStrokeRadius(size: 100, thinning: 0.5, pressure: 0.5) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 0.5, pressure: 0.75) == 62.5)
        #expect(getStrokeRadius(size: 100, thinning: 0.5, pressure: 1) == 75)
    }

    @Test("at 1 thinning, scales between 0% and 100%")
    func positiveFullThinning() {
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0) == 0)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.25) == 25)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.5) == 50)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.75) == 75)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 1) == 100)
    }

    // MARK: - negative thinning (ports `when thinning is negative`)

    @Test("at -0.5 thinning, scales between 75% and 25%")
    func negativeHalfThinning() {
        #expect(getStrokeRadius(size: 100, thinning: -0.5, pressure: 0) == 75)
        #expect(getStrokeRadius(size: 100, thinning: -0.5, pressure: 0.25) == 62.5)
        #expect(getStrokeRadius(size: 100, thinning: -0.5, pressure: 0.5) == 50)
        #expect(getStrokeRadius(size: 100, thinning: -0.5, pressure: 0.75) == 37.5)
        #expect(getStrokeRadius(size: 100, thinning: -0.5, pressure: 1) == 25)
    }

    @Test("at -1 thinning, scales between 100% and 0%")
    func negativeFullThinning() {
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0) == 100)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.25) == 75)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.5) == 50)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.75) == 25)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 1) == 0)
    }

    // MARK: - exponential easing (ports `when easing is exponential`)

    @Test("with t*t easing at 1 thinning, scales between 0% and 100%")
    func exponentialEasingPositiveThinning() {
        let easing: @Sendable (Double) -> Double = { t in t * t }
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0, easing: easing) == 0)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.25, easing: easing) == 6.25)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.5, easing: easing) == 25)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 0.75, easing: easing) == 56.25)
        #expect(getStrokeRadius(size: 100, thinning: 1, pressure: 1, easing: easing) == 100)
    }

    @Test("with t*t easing at -1 thinning, scales between 100% and 0%")
    func exponentialEasingNegativeThinning() {
        let easing: @Sendable (Double) -> Double = { t in t * t }
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0, easing: easing) == 100)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.25, easing: easing) == 56.25)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.5, easing: easing) == 25)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 0.75, easing: easing) == 6.25)
        #expect(getStrokeRadius(size: 100, thinning: -1, pressure: 1, easing: easing) == 0)
    }

    // MARK: - Swift-specific additions

    @Test("nil easing behaves identically to linear t -> t")
    func nilEasingIsLinear() {
        let linear: @Sendable (Double) -> Double = { t in t }
        let pressures: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]
        let thinnings: [Double] = [-1, -0.5, 0, 0.5, 1]
        for thinning in thinnings {
            for pressure in pressures {
                let nilResult = getStrokeRadius(size: 100, thinning: thinning, pressure: pressure)
                let linearResult = getStrokeRadius(
                    size: 100, thinning: thinning, pressure: pressure, easing: linear
                )
                #expect(nilResult == linearResult)
            }
        }
    }

    @Test("size scales the result linearly")
    func sizeScalesLinearly() {
        // At thinning=0.5 pressure=0.5, the easing argument is 0.5, so the
        // result is size * 0.5. Confirm linear scaling across sizes.
        for size in stride(from: 1.0, through: 200.0, by: 13.0) {
            #expect(getStrokeRadius(size: size, thinning: 0.5, pressure: 0.5) == size * 0.5)
        }
    }
}
