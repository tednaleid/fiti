// ABOUTME: 28x28 SF-Symbol button used as the size/opacity popover trigger in the toolbar.
// ABOUTME: Sibling to color and tool buttons; the same FirstMouseButton + regularSquare bezel.

import AppKit

enum PresetButton {
    /// Builds a 28x28 first-mouse SF-Symbol button. Caller wires `target` and `action`.
    static func make(symbol: String, accessibility: String, tooltip: String) -> NSButton {
        let button = FirstMouseButton(title: "", target: nil, action: nil)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.toolTip = tooltip
        return button
    }
}
