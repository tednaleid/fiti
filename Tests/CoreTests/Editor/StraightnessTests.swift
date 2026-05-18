// ABOUTME: Tests for isSubstantiallyStraight — the rubric that decides whether
// ABOUTME: a freehand path qualifies for the hold-to-straighten snap.

import Testing

@Suite("isSubstantiallyStraight")
struct StraightnessTests {
    @Test("two-point segment is straight")
    func twoPoints() {
        let pts = [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 0)]
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("perfectly collinear points are straight")
    func collinear() {
        let pts = (0...10).map { StrokePoint(x: Double($0), y: Double($0) * 2) }
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("slight wobble within threshold is straight")
    func slightWobble() {
        // a near-straight line from (0,0) to (100,0) with tiny Y jitter (±0.1 per step)
        let pts = (0...100).map { StrokePoint(x: Double($0), y: ($0 % 2 == 0) ? 0.1 : -0.1) }
        #expect(isSubstantiallyStraight(points: pts))
    }

    @Test("box is not straight")
    func box() {
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 10, y: 0),
            StrokePoint(x: 10, y: 10),
            StrokePoint(x: 0, y: 10),
            StrokePoint(x: 0, y: 0.1)  // near-closed box
        ]
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("zigzag is not straight")
    func zigzag() {
        let pts = (0...20).map { i -> StrokePoint in
            StrokePoint(x: Double(i), y: (i % 2 == 0) ? 0 : 10)
        }
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("fewer than 2 points is not straight")
    func notEnoughPoints() {
        #expect(isSubstantiallyStraight(points: []) == false)
        #expect(isSubstantiallyStraight(points: [StrokePoint(x: 0, y: 0)]) == false)
    }

    @Test("first and last identical (closed loop) is not straight")
    func degenerateEuclidean() {
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 5, y: 5),
            StrokePoint(x: 0, y: 0)
        ]
        #expect(isSubstantiallyStraight(points: pts) == false)
    }

    @Test("threshold is configurable")
    func customThreshold() {
        // a slightly-curved path with ratio ~1.077 (midpoint displaced to y=2)
        let pts = [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: 5, y: 2),
            StrokePoint(x: 10, y: 0)
        ]
        #expect(isSubstantiallyStraight(points: pts, threshold: 1.20))
        #expect(isSubstantiallyStraight(points: pts, threshold: 1.05) == false)
    }
}
