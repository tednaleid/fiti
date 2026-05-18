// ABOUTME: Port for a periodic tick that drives auto-fade. Real adapter wraps
// ABOUTME: Timer.scheduledTimer; tests use RecordingFadeTicker with tick(at:).

import Foundation

@MainActor
public protocol FadeTicker: AnyObject {
    /// Fired on each tick with the current clock time (seconds).
    var onTick: ((Double) -> Void)? { get set }

    /// Begin firing onTick on the adapter's chosen cadence. Idempotent.
    func start()

    /// Stop firing. Idempotent.
    func stop()
}
