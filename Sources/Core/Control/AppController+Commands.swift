// ABOUTME: AppController extension for KeyCommand routing — color, size, opacity,
// ABOUTME: visibility, auto-fade, and clear dispatching.

import Foundation

extension AppController {
    public func run(_ command: KeyCommand) {
        // In selection mode with a live selection, color/size/opacity shortcuts
        // retarget the selected items rather than the drawing defaults.
        if applyStyleToSelection(command) { return }
        switch command {
        case .pickColor(let i):
            pickBrushColor(i)
        case .bumpSize(.up):
            currentWidth = min(40, currentWidth * 1.1)
        case .bumpSize(.down):
            currentWidth = max(1, currentWidth / 1.1)
        case .bumpOpacity(.up):
            currentColor = currentColor.with(a: min(1, currentColor.a + 0.1))
        case .bumpOpacity(.down):
            currentColor = currentColor.with(a: max(0, currentColor.a - 0.1))
        case .toggleHide:
            drawingsVisible.toggle()
        case .toggleAutoFade:
            autoFadeEnabled.toggle()
        case .clear:
            runClear()
        case .selectTool(let tool):
            currentTool = tool
        }
    }

    private func pickBrushColor(_ i: Int) {
        guard i >= 0, i < QuickPickPalette.colors.count else { return }
        let c = QuickPickPalette.colors[i]
        currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: currentColor.a)
    }

    /// Applies a color/size/opacity command to the current selection. Returns
    /// true when it handled the command; false when it should fall through to
    /// default handling (no live selection, or a non-style command).
    private func applyStyleToSelection(_ command: KeyCommand) -> Bool {
        guard currentTool == .selection, !selectedItemIds.isEmpty else { return false }
        switch command {
        case .pickColor(let i):
            guard i >= 0, i < QuickPickPalette.colors.count else { return true }
            let c = QuickPickPalette.colors[i]
            mutateSelection { $0.withColorPreservingAlpha(r: c.r, g: c.g, b: c.b) }
        case .bumpOpacity(let dir):
            let delta = dir == .up ? 0.1 : -0.1
            mutateSelection { $0.withAlpha(min(1, max(0, $0.color.a + delta))) }
        case .bumpSize(let dir):
            mutateSelection { resized($0, direction: dir) }
            recomputeSelectionBox()  // text bounds may have changed
        default:
            return false
        }
        return true
    }

    private func mutateSelection(_ transform: (CanvasItem) -> CanvasItem) {
        let updated = selectedItemIds.compactMap { editor.doc.items[$0].map(transform) }
        guard !updated.isEmpty else { return }
        _ = editor.replaceItems(updated)
    }

    /// Scales an item's "size": stroke width (clamped 1...40) or, for text, the
    /// font size with its frozen bounds re-measured via the TextMeasuring port.
    private func resized(_ item: CanvasItem, direction: KeyCommand.Direction) -> CanvasItem {
        switch item {
        case .stroke(var s):
            s.width = direction == .up ? min(40, s.width * 1.1) : max(1, s.width / 1.1)
            return .stroke(s)
        case .text(var t):
            t.fontSize = direction == .up ? t.fontSize * 1.1 : max(4, t.fontSize / 1.1)
            t.bounds = textMeasurer.measure(string: t.string, fontName: t.fontName,
                                            fontSize: t.fontSize)
            return .text(t)
        }
    }

    private func runClear() {
        if currentTool == .selection {
            if !selectedItemIds.isEmpty {
                _ = editor.eraseItems(ids: selectedItemIds)
                selectedItemIds = []
            }
            // no selection in selection mode → no-op (a "miss")
        } else {
            clear()
        }
    }
}
