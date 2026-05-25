// ABOUTME: Tests for ToolbarController — verifies the floating panel shows on
// ABOUTME: activation, hides on deactivation, and (later) widgets write through
// ABOUTME: to AppController state.

// swiftlint:disable file_length
import AppKit
import Testing

@Suite("ToolbarController")
@MainActor
struct ToolbarControllerTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (ToolbarController, AppController, Editor) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller, editor)
    }

    @Test("panel is hidden on init")
    func hiddenOnInit() {
        let (toolbar, _, _) = make()
        #expect(toolbar.panel.isVisible == false)
    }

    @Test("updateVisibility shows the panel when mode is not .inactive")
    func showsWhenActive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        #expect(toolbar.panel.isVisible == true)
    }

    @Test("updateVisibility hides the panel when mode is .inactive")
    func hidesWhenInactive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        toolbar.updateVisibility(for: .inactive)
        #expect(toolbar.panel.isVisible == false)
    }

    @Test("clicking a quick-pick color sets controller.currentColor RGB but preserves alpha")
    func quickPickPreservesAlpha() throws {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.5)
        try toolbar.testOnly_clickQuickPick(at: 1)
        #expect(controller.currentColor.r == 134.0 / 255.0)
        #expect(controller.currentColor.g == 142.0 / 255.0)
        #expect(controller.currentColor.b == 150.0 / 255.0)
        #expect(controller.currentColor.a == 0.5, "alpha should be preserved")
    }

    @Test("opacity slider writes controller.currentColor.a but preserves rgb")
    func opacityPreservesRGB() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 1.0)
        toolbar.testOnly_setOpacity(0.3)
        #expect(controller.currentColor.a == 0.3)
        #expect(controller.currentColor.r == 0.2)
        #expect(controller.currentColor.g == 0.4)
        #expect(controller.currentColor.b == 0.6)
    }

    @Test("width slider writes controller.currentWidth")
    func widthSlider() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_setWidth(12)
        #expect(controller.currentWidth == 12)
    }

    @Test("hide button toggles controller.drawingsVisible")
    func hideButton() {
        let (toolbar, controller, _) = make()
        #expect(controller.drawingsVisible == true)
        toolbar.testOnly_toggleHide()
        #expect(controller.drawingsVisible == false)
        toolbar.testOnly_toggleHide()
        #expect(controller.drawingsVisible == true)
    }

    @Test("persisted color/width override defaults at init")
    func persistedOverrides() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set(0.1, forKey: "fiti.color.r")
        suite.set(0.2, forKey: "fiti.color.g")
        suite.set(0.3, forKey: "fiti.color.b")
        suite.set(0.4, forKey: "fiti.color.a")
        suite.set(11.0, forKey: "fiti.width")
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        _ = ToolbarController(controller: controller, defaults: suite)
        #expect(controller.currentColor == RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
        #expect(controller.currentWidth == 11)
    }

    @Test("widget changes write through to UserDefaults")
    func widgetChangesPersist() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller, defaults: suite)
        toolbar.testOnly_setWidth(9)
        toolbar.testOnly_setOpacity(0.6)
        #expect(suite.double(forKey: "fiti.width") == 9)
        #expect(suite.double(forKey: "fiti.color.a") == 0.6)
    }

    @Test("non-widget color/width changes persist (keyboard/menubar/HTTP path)")
    func nonWidgetChangesPersist() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let (_, controller, _) = make()
        let toolbar = ToolbarController(controller: controller, defaults: suite)
        // Simulate keyboard/HTTP change: set controller state directly,
        // NOT through a toolbar widget.
        controller.currentColor = RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        controller.currentWidth = 9
        #expect(suite.double(forKey: "fiti.color.r") == 0.1)
        #expect(suite.double(forKey: "fiti.color.a") == 0.4)
        #expect(suite.double(forKey: "fiti.width") == 9)
        _ = toolbar
    }

    @Test("size picker outline flag follows the tool's outline setting")
    func sizePickerOutlineFollowsTool() {
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let settings = DefaultOutlineSettings(textOutline: true, arrowOutline: false, penOutline: false)
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                        outlineSettings: settings)
        controller.activate()
        controller.currentTool = .text
        #expect(toolbar.testOnly_sizePickerOutlineOn == true)
        controller.currentTool = .arrow
        #expect(toolbar.testOnly_sizePickerOutlineOn == false)
        controller.currentTool = .pen
        #expect(toolbar.testOnly_sizePickerOutlineOn == false)
    }

    @Test("external write to currentColor updates the color well")
    func externalColorWriteUpdatesWidget() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
        let c = toolbar.testOnly_colorWellColor
        #expect(abs(c.redComponent - 0.0) < 0.01)
        #expect(abs(c.greenComponent - 1.0) < 0.01)
        #expect(abs(c.blueComponent - 0.0) < 0.01)
    }

    @Test("external write to currentWidth updates the width slider")
    func externalWidthWriteUpdatesWidget() {
        let (toolbar, controller, _) = make()
        controller.currentWidth = 17
        #expect(toolbar.testOnly_widthSliderValue == 17)
    }

    @Test("size picker preview tool follows controller.currentTool")
    func sizePickerTracksTool() {
        let (toolbar, controller, _) = make()
        controller.activate()
        controller.currentTool = .text
        #expect(toolbar.testOnly_sizePickerTool == .text)
    }

    @Test("tapping size + steps controller.currentWidth to the next preset")
    func sizeStepUpdatesController() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_tapSizeUp()   // default width 6 -> next preset 9
        #expect(controller.currentWidth == 9)
    }

    @Test("tapping opacity + steps controller.currentColor.a, preserving rgb")
    func opacityStepUpdatesController() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.5)
        toolbar.testOnly_tapOpacityUp()   // 0.5 -> 0.6
        #expect(abs(controller.currentColor.a - 0.6) < 0.0001)
        #expect(controller.currentColor.r == 0.2)
        #expect(controller.currentColor.g == 0.4)
        #expect(controller.currentColor.b == 0.6)
    }

    @Test("external write to drawingsVisible updates the hide button glyph")
    func externalHideWriteUpdatesGlyph() {
        let (toolbar, controller, _) = make()
        controller.drawingsVisible = false
        #expect(toolbar.testOnly_hideButtonGlyphName == "eye.slash")
        controller.drawingsVisible = true
        #expect(toolbar.testOnly_hideButtonGlyphName == "eye")
    }
}

@Suite("ToolbarController auto-fade toggle")
@MainActor
struct ToolbarControllerAutoFadeTests {
    // swiftlint:disable:next large_tuple
    private func make(defaults: UserDefaults) -> (ToolbarController, AppController, VirtualClock) {
        let clock = VirtualClock()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller, defaults: defaults)
        return (toolbar, controller, clock)
    }

    private func uniqueDefaults() -> UserDefaults {
        let suite = "fiti.tests.autoFade.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("button glyph is clock.badge.xmark when auto-fade is off")
    func glyphOff() {
        let (toolbar, _, _) = make(defaults: uniqueDefaults())
        #expect(toolbar.testOnly_autoFadeGlyphName == "clock.badge.xmark")
    }

    @Test("button glyph swaps to plain clock when auto-fade is on")
    func glyphOn() {
        let (toolbar, controller, _) = make(defaults: uniqueDefaults())
        controller.autoFadeEnabled = true
        #expect(toolbar.testOnly_autoFadeGlyphName == "clock")
    }

    @Test("clicking the button toggles controller.autoFadeEnabled")
    func clickToggles() {
        let (toolbar, controller, _) = make(defaults: uniqueDefaults())
        #expect(controller.autoFadeEnabled == false)
        toolbar.testOnly_clickAutoFade()
        #expect(controller.autoFadeEnabled == true)
        toolbar.testOnly_clickAutoFade()
        #expect(controller.autoFadeEnabled == false)
    }

    @Test("toggle writes to UserDefaults under fiti.autoFade")
    func togglePersists() {
        let defaults = uniqueDefaults()
        let (toolbar, _, _) = make(defaults: defaults)
        toolbar.testOnly_clickAutoFade()
        #expect(defaults.bool(forKey: "fiti.autoFade") == true)
        toolbar.testOnly_clickAutoFade()
        #expect(defaults.bool(forKey: "fiti.autoFade") == false)
    }

    @Test("init reads persisted state from UserDefaults")
    func initReadsPersisted() {
        let defaults = uniqueDefaults()
        defaults.set(true, forKey: "fiti.autoFade")
        let (_, controller, _) = make(defaults: defaults)
        #expect(controller.autoFadeEnabled == true)
    }
}

@Suite("ToolbarController tooltips and labels")
@MainActor
struct ToolbarControllerTooltipTests {
    private func make() -> (ToolbarController, AppController) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller)
    }

    @Test("color swatches have name + shortcut tooltips")
    func swatchTooltips() {
        let (toolbar, _) = make()
        for i in 0..<8 {
            let expected = "\(QuickPickPalette.colors[i].name) — \(i + 1)"
            #expect(toolbar.testOnly_swatchTooltip(at: i) == expected)
        }
    }

    @Test("color well has 'Custom color' tooltip")
    func colorWellTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_colorWellTooltip == "Custom color")
    }

    @Test("width control has 'Size — s / S' tooltip")
    func widthSliderTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_widthSliderTooltip == "Size — s / S")
    }

    @Test("opacity control has 'Opacity — o / O' tooltip")
    func opacitySliderTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacitySliderTooltip == "Opacity — o / O")
    }

    @Test("hide button tooltip flips with drawingsVisible")
    func hideButtonTooltip() {
        let (toolbar, controller) = make()
        #expect(toolbar.testOnly_hideButtonTooltip == "Hide drawings — h")
        controller.drawingsVisible = false
        #expect(toolbar.testOnly_hideButtonTooltip == "Show drawings — h")
    }

    @Test("auto-fade button tooltip flips with autoFadeEnabled")
    func autoFadeButtonTooltip() {
        let (toolbar, controller) = make()
        #expect(toolbar.testOnly_autoFadeTooltip == "Auto-fade off — f")
        controller.autoFadeEnabled = true
        #expect(toolbar.testOnly_autoFadeTooltip == "Auto-fade on — f")
    }

    @Test("width label text is 'size'")
    func widthLabelText() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_widthLabelText == "size")
    }

    @Test("opacity label text is 'opacity'")
    func opacityLabelText() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacityLabelText == "opacity")
    }
}

@Suite("ToolbarController active-state highlights")
@MainActor
struct ToolbarControllerActiveStateTests {
    private func make() -> (ToolbarController, AppController) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller)
    }

    @Test("the swatch matching currentColor is the active swatch on init")
    func initActiveSwatchMatchesDefault() {
        // Default currentColor is Red (palette index 2).
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_activeSwatchIndex == 2)
    }

    @Test("changing currentColor to a palette color updates the active swatch")
    func activeSwatchTracksColorChange() {
        let (toolbar, controller) = make()
        let green = QuickPickPalette.colors[5]
        controller.currentColor = RGBA(r: green.r, g: green.g, b: green.b, a: 0.7)
        #expect(toolbar.testOnly_activeSwatchIndex == 5)
    }

    @Test("setting a non-palette currentColor clears the active swatch")
    func nonPaletteColorClearsHighlight() {
        let (toolbar, controller) = make()
        controller.currentColor = RGBA(r: 0.123, g: 0.456, b: 0.789, a: 1.0)
        #expect(toolbar.testOnly_activeSwatchIndex == nil)
    }

    @Test("matching ignores alpha — only RGB is compared")
    func swatchMatchIgnoresAlpha() {
        let (toolbar, controller) = make()
        let blue = QuickPickPalette.colors[6]
        controller.currentColor = RGBA(r: blue.r, g: blue.g, b: blue.b, a: 0.1)
        #expect(toolbar.testOnly_activeSwatchIndex == 6)
    }

    @Test("hide button has no active background while drawings are visible")
    func hideButtonInactiveByDefault() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_hideButtonActiveBackground == false)
    }

    @Test("hide button gains an active background once drawings are hidden")
    func hideButtonActiveWhenHidden() {
        let (toolbar, controller) = make()
        controller.drawingsVisible = false
        #expect(toolbar.testOnly_hideButtonActiveBackground == true)
        controller.drawingsVisible = true
        #expect(toolbar.testOnly_hideButtonActiveBackground == false)
    }

    @Test("auto-fade button has no active background while disabled")
    func autoFadeInactiveByDefault() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_autoFadeActiveBackground == false)
    }

    @Test("auto-fade button gains an active background once enabled")
    func autoFadeActiveWhenEnabled() {
        let (toolbar, controller) = make()
        controller.autoFadeEnabled = true
        #expect(toolbar.testOnly_autoFadeActiveBackground == true)
        controller.autoFadeEnabled = false
        #expect(toolbar.testOnly_autoFadeActiveBackground == false)
    }
}
