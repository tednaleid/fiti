// ABOUTME: UserDefaults-backed OutlineSettings adapter. Persists the global
// ABOUTME: outline/halo toggle under "fiti.outlineEnabled", defaulting to off.

import Foundation

@MainActor
public final class UserDefaultsOutlineSettings: OutlineSettings {
    static let key = "fiti.outlineEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var outlineEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }   // unset -> false
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
