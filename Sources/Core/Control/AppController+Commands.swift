// ABOUTME: AppController extension for KeyCommand routing — color, size, opacity,
// ABOUTME: visibility, auto-fade, and clear dispatching.

import Foundation

extension AppController {
    public func run(_ command: KeyCommand) {
        switch command {
        case .pickColor(let i):
            guard i >= 0, i < QuickPickPalette.colors.count else { return }
            let c = QuickPickPalette.colors[i]
            currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: currentColor.a)
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
        }
    }

    private func runClear() {
        if currentTool == .selection {
            if !selectedStrokeIds.isEmpty {
                _ = editor.eraseItems(ids: selectedStrokeIds)
                selectedStrokeIds = []
            }
            // no selection in selection mode → no-op (a "miss")
        } else {
            clear()
        }
    }
}
