// ABOUTME: UserDefaults-backed OutlineSettings adapter. Persists the per-tool
// ABOUTME: outline toggles; text and arrows default on, pen defaults off.

import Foundation

@MainActor
public final class UserDefaultsOutlineSettings: OutlineSettings {
    static let textKey = "fiti.outline.text"
    static let arrowKey = "fiti.outline.arrow"
    static let penKey = "fiti.outline.pen"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // An unset key reads as its product default, not UserDefaults' blanket `false`.
    private func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    public var textOutline: Bool {
        get { bool(Self.textKey, default: true) }
        set { defaults.set(newValue, forKey: Self.textKey) }
    }
    public var arrowOutline: Bool {
        get { bool(Self.arrowKey, default: true) }
        set { defaults.set(newValue, forKey: Self.arrowKey) }
    }
    public var penOutline: Bool {
        get { bool(Self.penKey, default: false) }
        set { defaults.set(newValue, forKey: Self.penKey) }
    }
}
