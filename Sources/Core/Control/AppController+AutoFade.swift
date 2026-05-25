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
        let window = fadeSettings.secondsBeforeFade
        guard window > 0 else { fadeOpacity = 1.0; return }
        // The ramp is the tail of the window; it can never exceed the window itself
        // (a window shorter than the ramp just fades across its whole length).
        let ramp = min(Self.fadeRampSeconds, window)
        let rampStart = window - ramp

        if age >= window {
            editor.clear()
            if !selectedItemIds.isEmpty { selectedItemIds = [] }
            lastInputAt = nil
            fadeOpacity = 1.0
        } else if age >= rampStart {
            fadeOpacity = 1.0 - (age - rampStart) / ramp
        } else {
            fadeOpacity = 1.0
        }
    }
}
