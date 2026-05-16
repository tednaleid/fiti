// ABOUTME: In-memory WindowControl for AppController tests.

import Foundation

public final class RecordingWindow: WindowControl {
    public private(set) var clickThroughHistory: [Bool] = []
    public private(set) var focusCount: Int = 0
    public init() {}
    public func setClickThrough(_ enabled: Bool) { clickThroughHistory.append(enabled) }
    public func focus() { focusCount += 1 }
}
