// ABOUTME: DEBUG-only in-process timing aggregator. Hot paths call measure()/record();
// ABOUTME: the dev HTTP /perf route reads snapshot(). Compiled out of release builds.

#if DEBUG
import Foundation

/// Accumulates labeled timing samples (count/total/max/last) plus scalar gauges.
/// Process-global via `shared`; MainActor-confined since the render path and the
/// dev HTTP routes that read it both run on the main actor (no locking needed).
/// This is a deliberate dev-only convenience; it is excluded from release builds.
@MainActor
public final class PerfLog {
    public static let shared = PerfLog()

    public struct Stat: Sendable, Equatable {
        public var count: Int = 0
        public var totalSeconds: Double = 0
        public var maxSeconds: Double = 0
        public var lastSeconds: Double = 0
    }

    private var stats: [String: Stat] = [:]
    private var gauges: [String: Double] = [:]

    public init() {}

    /// Add one timing sample to `label`.
    public func record(_ label: String, seconds: Double) {
        var stat = stats[label] ?? Stat()
        stat.count += 1
        stat.totalSeconds += seconds
        stat.maxSeconds = max(stat.maxSeconds, seconds)
        stat.lastSeconds = seconds
        stats[label] = stat
    }

    /// Time `body`, record the elapsed wall time under `label`, return its result.
    @discardableResult
    public func measure<T>(_ label: String, _ body: () -> T) -> T {
        let start = ContinuousClock.now
        let result = body()
        let elapsed = ContinuousClock.now - start
        record(label, seconds: seconds(elapsed))
        return result
    }

    /// Add one timing sample expressed as a `Duration` (convenient with `defer`).
    public func record(_ label: String, duration: Duration) {
        record(label, seconds: seconds(duration))
    }

    /// Store the latest value of a scalar gauge (e.g. a buffer size or item count).
    public func set(gauge label: String, _ value: Double) {
        gauges[label] = value
    }

    public func snapshot() -> (stats: [String: Stat], gauges: [String: Double]) {
        (stats, gauges)
    }

    public func reset() {
        stats.removeAll()
        gauges.removeAll()
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
#endif
