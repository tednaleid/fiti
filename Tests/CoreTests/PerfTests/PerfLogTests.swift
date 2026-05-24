// ABOUTME: Unit tests for the DEBUG-only PerfLog timing aggregator.
// ABOUTME: Verifies per-label stats accumulation, gauges, and reset.

import Testing

@MainActor
@Suite("PerfLog")
struct PerfLogTests {
    @Test("records aggregate stats per label")
    func aggregates() {
        let log = PerfLog()
        log.record("a", seconds: 0.5)
        log.record("a", seconds: 0.25)
        let a = log.snapshot().stats["a"]
        #expect(a?.count == 2)
        #expect(a?.totalSeconds == 0.75)
        #expect(a?.maxSeconds == 0.5)
        #expect(a?.lastSeconds == 0.25)
    }

    @Test("set gauge keeps the latest value")
    func gauge() {
        let log = PerfLog()
        log.set(gauge: "g", 1)
        log.set(gauge: "g", 2)
        #expect(log.snapshot().gauges["g"] == 2)
    }

    @Test("reset clears stats and gauges")
    func resets() {
        let log = PerfLog()
        log.record("a", seconds: 0.01)
        log.set(gauge: "g", 5)
        log.reset()
        #expect(log.snapshot().stats.isEmpty)
        #expect(log.snapshot().gauges.isEmpty)
    }

    @Test("measure records one sample for the labeled body")
    func measureRecords() {
        let log = PerfLog()
        let value = log.measure("m") { 41 + 1 }
        #expect(value == 42)
        #expect(log.snapshot().stats["m"]?.count == 1)
    }
}
