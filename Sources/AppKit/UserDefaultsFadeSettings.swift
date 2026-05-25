// ABOUTME: UserDefaults-backed FadeSettings adapter. Persists the auto-fade window
// ABOUTME: under "fiti.secondsBeforeFade", defaulting to the Core product default.

import Foundation

@MainActor
public final class UserDefaultsFadeSettings: FadeSettings {
    static let key = "fiti.secondsBeforeFade"
    /// Clamp range for whole-second windows: at least the fade ramp, at most a minute.
    static let minSeconds: Double = 2
    static let maxSeconds: Double = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var secondsBeforeFade: Double {
        get {
            // Unset reads as nil -> the Core default; a stored value is clamped to range.
            guard let stored = defaults.object(forKey: Self.key) as? Double else {
                return DefaultFadeSettings.defaultSecondsBeforeFade
            }
            return clamp(stored)
        }
        set { defaults.set(clamp(newValue), forKey: Self.key) }
    }

    private func clamp(_ value: Double) -> Double {
        min(Self.maxSeconds, max(Self.minSeconds, value.rounded()))
    }
}
