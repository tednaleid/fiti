// ABOUTME: Synchronous FadeTicker for tests. tick(at:) simulates a real tick;
// ABOUTME: isRunning lets tests assert on start/stop bookkeeping.

import Foundation

@MainActor
public final class RecordingFadeTicker: FadeTicker {
    public var onTick: ((Double) -> Void)?
    public private(set) var isRunning = false
    public init() {}
    public func start() { isRunning = true }
    public func stop() { isRunning = false }
    /// Test helper: simulate a tick at the given time. No-op if not started.
    public func tick(at time: Double) {
        guard isRunning else { return }
        onTick?(time)
    }
}
