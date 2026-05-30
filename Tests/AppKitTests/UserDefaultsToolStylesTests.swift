// ABOUTME: Per-tool style persistence — round-trip, product-default fallback, the
// ABOUTME: one-time legacy-global migration, and end-to-end restore across a relaunch.

import AppKit
import Testing

@Suite("UserDefaultsToolStyles")
@MainActor
struct UserDefaultsToolStylesTests {
    private func suite() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    @Test("save then load round-trips each tool independently")
    func roundTrip() {
        let d = suite()
        let store = UserDefaultsToolStyles(defaults: d)
        let pen = ToolStyle(color: RGBA(r: 1, g: 0, b: 0, a: 0.9), width: 10)
        let text = ToolStyle(color: RGBA(r: 0, g: 0, b: 1, a: 0.4), width: 30)
        store.save(pen, for: .pen)
        store.save(text, for: .text)

        let loaded = store.load()
        #expect(loaded[.pen] == pen)
        #expect(loaded[.text] == text)
        #expect(loaded[.arrow] == .default)   // never saved, never any legacy -> default
    }

    @Test("an unpersisted tool with legacy global keys is seeded from them")
    func legacyMigration() {
        let d = suite()
        d.set(0.1, forKey: "fiti.color.r")
        d.set(0.2, forKey: "fiti.color.g")
        d.set(0.3, forKey: "fiti.color.b")
        d.set(0.4, forKey: "fiti.color.a")
        d.set(11.0, forKey: "fiti.width")

        let loaded = UserDefaultsToolStyles(defaults: d).load()
        let migrated = ToolStyle(color: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4), width: 11)
        for tool in Tool.drawingTools {
            #expect(loaded[tool] == migrated)
        }
    }

    @Test("a saved per-tool style wins over the legacy global keys")
    func perToolBeatsLegacy() {
        let d = suite()
        d.set(0.1, forKey: "fiti.color.r"); d.set(0.2, forKey: "fiti.color.g")
        d.set(0.3, forKey: "fiti.color.b"); d.set(0.4, forKey: "fiti.color.a")
        d.set(11.0, forKey: "fiti.width")
        let store = UserDefaultsToolStyles(defaults: d)
        let pen = ToolStyle(color: RGBA(r: 1, g: 1, b: 1, a: 1), width: 70)
        store.save(pen, for: .pen)

        let loaded = store.load()
        #expect(loaded[.pen] == pen)                                   // explicit wins
        #expect(loaded[.text]?.width == 11)                            // text still migrates
    }

    @Test("per-tool styles survive a relaunch through ToolbarController")
    func relaunchRestoresPerTool() {
        let d = suite()
        let first = make(defaults: d)
        first.controller.currentTool = .pen
        first.controller.currentColor = RGBA(r: 1, g: 0, b: 0, a: 0.9)
        first.controller.currentWidth = 10
        first.controller.currentTool = .text
        first.controller.currentColor = RGBA(r: 0, g: 0, b: 1, a: 0.4)
        first.controller.currentWidth = 30

        // Relaunch: a fresh controller + toolbar reading the same defaults.
        let second = make(defaults: d)
        second.controller.currentTool = .pen
        #expect(second.controller.currentColor == RGBA(r: 1, g: 0, b: 0, a: 0.9))
        #expect(second.controller.currentWidth == 10)
        second.controller.currentTool = .text
        #expect(second.controller.currentColor == RGBA(r: 0, g: 0, b: 1, a: 0.4))
        #expect(second.controller.currentWidth == 30)
    }

    private func make(defaults: UserDefaults) -> (toolbar: ToolbarController, controller: AppController) {
        let controller = AppController(
            editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s")),
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller, defaults: defaults)
        return (toolbar, controller)
    }
}
