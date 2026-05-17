// ABOUTME: Smoke test that the package compiles and the public API is reachable.
// ABOUTME: Asserts the stub getStroke returns [] until the real algorithm lands.

import Testing
@testable import PerfectFreehand

@Suite("Bootstrap")
struct BootstrapTests {
    struct P: StrokeInputPoint {
        let x: Double; let y: Double; let pressure: Double?
    }

    @Test("getStroke is callable and returns an empty array (stub)")
    func empty() {
        let result = getStroke(points: [P](), options: StrokeOptions())
        #expect(result.isEmpty)
    }
}
