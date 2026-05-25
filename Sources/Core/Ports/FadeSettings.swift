// ABOUTME: Port for the user-configurable auto-fade duration. AppKit backs it with
// ABOUTME: UserDefaults; tests and the default wiring use the in-memory DefaultFadeSettings.

import Foundation

/// The auto-fade timing the user can configure. `secondsBeforeFade` is the solid
/// hold after the last input before fading begins; the visible opacity ramp
/// (`AppController.fadeRampSeconds`) then runs on top, so marks clear at hold + ramp.
@MainActor
public protocol FadeSettings: AnyObject {
    var secondsBeforeFade: Double { get set }
}

/// In-memory `FadeSettings` holding the product default. Production injects a
/// persistent adapter; tests inject this with an explicit value.
@MainActor
public final class DefaultFadeSettings: FadeSettings {
    public nonisolated static let defaultSecondsBeforeFade: Double = 5.0
    public var secondsBeforeFade: Double
    public init(secondsBeforeFade: Double = DefaultFadeSettings.defaultSecondsBeforeFade) {
        self.secondsBeforeFade = secondsBeforeFade
    }
}
