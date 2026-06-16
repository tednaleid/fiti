// ABOUTME: Tests OverlayLayout.targetFrame — decides the full-screen overlay's
// ABOUTME: frame from the toolbar/fallback screen frames after a display change.

import Testing

@Suite("OverlayLayout")
struct OverlayLayoutTests {
    private let laptop = Rect(x: 0, y: 0, width: 1440, height: 900)
    private let big = Rect(x: 0, y: 0, width: 3840, height: 2160)

    @Test("same toolbar screen but a larger frame returns the new frame (monitor connected)")
    func staleFrameOnReconfiguredScreenResizes() {
        // Overlay still sized to the laptop, toolbar's screen is now the 4K.
        #expect(OverlayLayout.targetFrame(toolbarScreen: big, fallbackScreen: nil, current: laptop) == big)
    }

    @Test("frame already matches the toolbar screen returns nil (no resize)")
    func alreadyCoveringTargetReturnsNil() {
        #expect(OverlayLayout.targetFrame(toolbarScreen: big, fallbackScreen: laptop, current: big) == nil)
    }

    @Test("toolbar screen gone falls back to the fallback screen")
    func toolbarScreenGoneUsesFallback() {
        // The monitor hosting the toolbar was unplugged; cover the remaining (main) screen.
        #expect(OverlayLayout.targetFrame(toolbarScreen: nil, fallbackScreen: laptop, current: big) == laptop)
    }

    @Test("no screen to target returns nil")
    func noScreenReturnsNil() {
        #expect(OverlayLayout.targetFrame(toolbarScreen: nil, fallbackScreen: nil, current: laptop) == nil)
    }

    @Test("fallback already matches current returns nil")
    func fallbackAlreadyCorrectReturnsNil() {
        #expect(OverlayLayout.targetFrame(toolbarScreen: nil, fallbackScreen: laptop, current: laptop) == nil)
    }
}
