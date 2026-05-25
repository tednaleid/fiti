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

        if editor.doc.items.isEmpty {
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
        // secondsBeforeFade is the solid hold; the fade ramp runs on top of it, so
        // marks clear at hold + ramp. A hold of 0 fades immediately over the ramp.
        let solid = max(0, fadeSettings.secondsBeforeFade)
        let ramp = Self.fadeRampSeconds
        let clearAt = solid + ramp

        if age >= clearAt {
            editor.clear()
            if !selectedItemIds.isEmpty { selectedItemIds = [] }
            lastInputAt = nil
            fadeOpacity = 1.0
        } else if age >= solid {
            fadeOpacity = 1.0 - (age - solid) / ramp
        } else {
            fadeOpacity = 1.0
        }
    }
}
