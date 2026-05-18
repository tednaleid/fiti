// ABOUTME: Synchronous StationaryDetector for tests. fire() simulates the timer
// ABOUTME: expiring; isArmed lets tests assert on arm/disarm bookkeeping.

import Foundation

@MainActor
public final class RecordingStationaryDetector: StationaryDetector {
    public var onStationary: (() -> Void)?
    public private(set) var isArmed = false
    public init() {}
    public func arm() { isArmed = true }
    public func disarm() { isArmed = false }
    /// Test helper: simulate the timer expiring. No-op if not armed.
    public func fire() {
        guard isArmed else { return }
        isArmed = false
        onStationary?()
    }
}
