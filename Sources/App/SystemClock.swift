// ABOUTME: Production Clock — wall-clock seconds since epoch.
// ABOUTME: Tests use VirtualClock; this is the real impl wired in main.swift.

import Foundation

public final class SystemClock: Clock {
    public init() {}
    public func now() -> Double { Date().timeIntervalSince1970 }
}
