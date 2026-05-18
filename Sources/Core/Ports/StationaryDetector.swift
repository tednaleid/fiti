// ABOUTME: Port for "fire a callback after N ms of no arm() call." Real adapter
// ABOUTME: uses Task.sleep; test double exposes fire() so tests run instantly.

import Foundation

@MainActor
public protocol StationaryDetector: AnyObject {
    /// Callback invoked when the armed timer expires. Set once at composition time.
    var onStationary: (() -> Void)? { get set }
    /// (Re)start the timer. Any pending callback is cancelled.
    func arm()
    /// Cancel any pending callback.
    func disarm()
}
