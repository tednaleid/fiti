// ABOUTME: Swift-side property tests for the algorithm — invariants that must
// ABOUTME: hold regardless of fixture. Expanded across the port commits.

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
}
