// ABOUTME: Named 8-color quick-pick palette used by the toolbar's color row,
// ABOUTME: the menubar's Drawing submenu, and tooltip text. RGB only — alpha
// ABOUTME: comes from the user's current opacity at the moment a color is picked.

import Foundation

public struct QuickPickColor: Equatable, Sendable {
    public let name: String
    public let r: Double
    public let g: Double
    public let b: Double

    public init(name: String, r: Double, g: Double, b: Double) {
        self.name = name
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum QuickPickPalette {
    public static let colors: [QuickPickColor] = [
        QuickPickColor(name: "Black", r: 0, g: 0, b: 0),
        QuickPickColor(name: "Gray", r: 134.0 / 255.0, g: 142.0 / 255.0, b: 150.0 / 255.0),
        QuickPickColor(name: "Red", r: 224.0 / 255.0, g: 49.0 / 255.0, b: 49.0 / 255.0),
        QuickPickColor(name: "Orange", r: 247.0 / 255.0, g: 103.0 / 255.0, b: 7.0 / 255.0),
        QuickPickColor(name: "Amber", r: 245.0 / 255.0, g: 159.0 / 255.0, b: 0),
        QuickPickColor(name: "Green", r: 47.0 / 255.0, g: 158.0 / 255.0, b: 68.0 / 255.0),
        QuickPickColor(name: "Blue", r: 25.0 / 255.0, g: 113.0 / 255.0, b: 194.0 / 255.0),
        QuickPickColor(name: "Violet", r: 156.0 / 255.0, g: 54.0 / 255.0, b: 181.0 / 255.0)
    ]
}
