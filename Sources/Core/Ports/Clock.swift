// ABOUTME: Time source port. Production wires a SystemClock (in Sources/App);
// ABOUTME: tests wire VirtualClock for determinism.

import Foundation

public protocol Clock: AnyObject, Sendable {
    func now() -> Double
}
