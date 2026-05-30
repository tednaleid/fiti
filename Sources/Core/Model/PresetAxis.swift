// ABOUTME: Pure picker-axis enum used by the size/opacity popover. Holds the preset
// ABOUTME: list, the display formatter (integer / percent), and exact-match indexing.

import Foundation

public enum PresetAxis: Equatable, Sendable {
    case size
    case opacity

    public var values: [Double] {
        switch self {
        case .size: return ValuePresets.sizes
        case .opacity: return ValuePresets.opacities
        }
    }

    public func displayString(for value: Double) -> String {
        switch self {
        case .size:
            return "\(Int(value.rounded()))"
        case .opacity:
            return "\(Int((value * 100).rounded()))%"
        }
    }

    public func selectedIndex(for value: Double) -> Int? {
        values.firstIndex { abs($0 - value) < 1e-6 }
    }
}
