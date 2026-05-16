// ABOUTME: Deterministic Clock for tests. Time advances only on explicit calls.

import Foundation

public final class VirtualClock: Clock, @unchecked Sendable {
    private var current: Double

    public init(now: Double = 0) {
        self.current = now
    }

    public func now() -> Double {
        current
    }

    public func advance(by seconds: Double) {
        current += seconds
    }
}
