// ABOUTME: AppController extension for auto-fade tick handling — opacity ramp
// ABOUTME: and clear-after-window logic driven by the FadeTicker port.

import Foundation

extension AppController {
    func autoFadeStateChanged() {
        if autoFadeEnabled {
            lastInputAt = clock.now()
            ticker.start()
        } else {
            ticker.stop()
            fadeOpacity = 1.0
        }
    }

    func handleTick(_ now: Double) {
        guard autoFadeEnabled else { return }
        guard mode != .activeDrawing else { return }

        if editor.doc.strokes.isEmpty {
            lastInputAt = nil
            fadeOpacity = 1.0
            return
        }

        if lastInputAt == nil {
            lastInputAt = now
            fadeOpacity = 1.0
            return
        }

        let age = now - lastInputAt!
        let rampStart = Self.fadeWindowSeconds - Self.fadeRampSeconds  // 8.0

        if age >= Self.fadeWindowSeconds {
            editor.clear()
            lastInputAt = nil
            fadeOpacity = 1.0
        } else if age >= rampStart {
            fadeOpacity = 1.0 - (age - rampStart) / Self.fadeRampSeconds
        } else {
            fadeOpacity = 1.0
        }
    }
}
