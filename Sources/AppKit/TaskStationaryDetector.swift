// ABOUTME: StationaryDetector adapter using a cancellable Task with sleep.
// ABOUTME: arm() restarts the sleep; disarm() cancels. onStationary fires on
// ABOUTME: timeout if and only if the most recent arm() wasn't superseded.

import Foundation

@MainActor
public final class TaskStationaryDetector: StationaryDetector {
    public var onStationary: (() -> Void)?
    private let timeout: Duration
    private var task: Task<Void, Never>?

    public init(timeout: Duration = .milliseconds(800)) {
        self.timeout = timeout
    }

    public func arm() {
        task?.cancel()
        task = Task { @MainActor [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            self.onStationary?()
        }
    }

    public func disarm() {
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }
}
