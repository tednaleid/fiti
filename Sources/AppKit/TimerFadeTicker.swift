// ABOUTME: Real FadeTicker adapter. Fires at 30 Hz via Timer.scheduledTimer,
// ABOUTME: passing clock.now() into onTick. Smoke-tested through real app use.

import AppKit
import Foundation

@MainActor
public final class TimerFadeTicker: FadeTicker {
    public var onTick: ((Double) -> Void)?
    private let clock: Clock
    private var timer: Timer?

    public init(clock: Clock) {
        self.clock = clock
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            // Hop to MainActor — Timer's callback is not actor-isolated.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onTick?(self.clock.now())
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    isolated deinit {
        timer?.invalidate()
    }
}
