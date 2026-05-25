// ABOUTME: Port for the user-configurable auto-fade duration. AppKit backs it with
// ABOUTME: UserDefaults; tests and the default wiring use the in-memory DefaultFadeSettings.

import Foundation

/// The auto-fade timing the user can configure. `secondsBeforeFade` is the whole
/// window from the last input until marks are cleared; the final
/// `AppController.fadeRampSeconds` of that window is the visible opacity ramp.
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
