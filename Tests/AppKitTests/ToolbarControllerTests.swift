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

    @Test("clicking the size button opens the popover with axis .size")
    func sizeButtonOpensPopover() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .size)
    }

    @Test("clicking the opacity button opens the popover with axis .opacity")
    func opacityButtonOpensPopover() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .opacity)
    }

    @Test("re-clicking the same trigger toggles the popover closed")
    func reclickSameTriggerCloses() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen == false)
    }

    @Test("clicking the other trigger swaps the popover axis")
    func clickOtherTriggerSwaps() {
        let (toolbar, _, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverAxis == .size)
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_popoverOpen)
        #expect(toolbar.testOnly_popoverAxis == .opacity)
    }

    @Test("picking a size cell writes through to controller.currentWidth")
    func sizePickWritesWidth() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_clickSizeButton()
        toolbar.testOnly_pickPopoverCell(at: 6)  // ValuePresets.sizes[6] == 30
        #expect(controller.currentWidth == 30)
        #expect(toolbar.testOnly_popoverOpen == false)
    }

    @Test("picking an opacity cell writes controller.currentColor.a, preserving rgb")
    func opacityPickWritesAlpha() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.5)
        toolbar.testOnly_clickOpacityButton()
        toolbar.testOnly_pickPopoverCell(at: 9)  // 1.0
        #expect(abs(controller.currentColor.a - 1.0) < 1e-6)
        #expect(controller.currentColor.r == 0.2)
        #expect(controller.currentColor.g == 0.4)
        #expect(controller.currentColor.b == 0.6)
    }

    @Test("changing currentTool while the popover is open closes it")
    func toolChangeClosesPopover() {
        let (toolbar, controller, _) = make()
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_popoverOpen)
        controller.currentTool = .arrow
        #expect(toolbar.testOnly_popoverOpen == false)
    }

    @Test("triggerPopover opens the matching axis and toggles closed on re-trigger")
    func triggerPopoverTogglesByAxis() {
        let (toolbar, _, _) = make()
        toolbar.triggerPopover(axis: .size)
        #expect(toolbar.popoverIsOpen)
        #expect(toolbar.popoverAxis == .size)
        toolbar.triggerPopover(axis: .opacity)   // swap
        #expect(toolbar.popoverAxis == .opacity)
        toolbar.triggerPopover(axis: .opacity)   // re-trigger closes
        #expect(toolbar.popoverIsOpen == false)
        #expect(toolbar.popoverAxis == nil)
    }

    @Test("popoverSnapshotPNG is nil when closed and PNG data when open")
    func popoverSnapshot() {
        let (toolbar, _, _) = make()
        #expect(toolbar.popoverSnapshotPNG() == nil)
        toolbar.triggerPopover(axis: .size)
        let data = toolbar.popoverSnapshotPNG()
        #expect(data != nil)
        #expect(Array(data!.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("changing color while the popover is open keeps it open and re-renders the cells")
    func colorChangeRefreshesOpenPopover() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.85, g: 0.2, b: 0.2, a: 1)  // red
        toolbar.triggerPopover(axis: .size)
        let before = toolbar.popoverSnapshotPNG()
        controller.currentColor = RGBA(r: 0.2, g: 0.2, b: 0.85, a: 1)  // blue
        #expect(toolbar.popoverIsOpen)            // stays open
        #expect(toolbar.popoverAxis == .size)
        #expect(toolbar.popoverSnapshotPNG() != before)  // cells re-rendered in the new color
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
        // Persistence is driven by AppController setters (not by widgets), so go
        // directly through the controller — equivalent to the keyboard/HTTP path.
        controller.currentWidth = 9
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: 0.6)
        // Default tool is pen, so changes persist under pen's per-tool keys.
        #expect(suite.double(forKey: "fiti.style.pen.width") == 9)
        #expect(suite.double(forKey: "fiti.style.pen.color.a") == 0.6)
        _ = toolbar
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
        #expect(suite.double(forKey: "fiti.style.pen.color.r") == 0.1)
        #expect(suite.double(forKey: "fiti.style.pen.color.a") == 0.4)
        #expect(suite.double(forKey: "fiti.style.pen.width") == 9)
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

    @Test("external write to currentColor updates the live mark preview")
    func externalColorWriteUpdatesWidget() {
        let (toolbar, controller, _) = make()
        controller.currentColor = RGBA(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
        let c = toolbar.testOnly_markColor
        #expect(abs(c.r - 0.0) < 0.01)
        #expect(abs(c.g - 1.0) < 0.01)
        #expect(abs(c.b - 0.0) < 0.01)
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

    @Test("custom color button has 'Custom color' tooltip")
    func customColorTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_customColorTooltip == "Custom color")
    }

    @Test("size button tooltip is 'Size — s / S'")
    func sizeButtonTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_sizeButtonTooltip == "Size — s / S")
    }

    @Test("opacity button tooltip is 'Opacity — o / O'")
    func opacityButtonTooltip() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_opacityButtonTooltip == "Opacity — o / O")
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

    @Test("custom-color wheel is active only when the color isn't a palette color")
    func customColorWheelActiveForNonPalette() {
        let (toolbar, controller) = make()
        // Default red is a palette color, so the wheel starts inactive.
        #expect(toolbar.testOnly_customColorActiveBackground == false)
        controller.currentColor = RGBA(r: 0.123, g: 0.456, b: 0.789, a: 1.0)
        #expect(toolbar.testOnly_customColorActiveBackground == true)
        let green = QuickPickPalette.colors[5]
        controller.currentColor = RGBA(r: green.r, g: green.g, b: green.b, a: 1.0)
        #expect(toolbar.testOnly_customColorActiveBackground == false)
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

    @Test("size button gains an active background while its popover is open")
    func sizeButtonActiveWhileOpen() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_sizeButtonActive == false)
        toolbar.testOnly_clickSizeButton()
        #expect(toolbar.testOnly_sizeButtonActive == true)
        #expect(toolbar.testOnly_opacityButtonActive == false)
        toolbar.testOnly_clickSizeButton()  // close
        #expect(toolbar.testOnly_sizeButtonActive == false)
    }

    @Test("opacity button gains an active background while its popover is open")
    func opacityButtonActiveWhileOpen() {
        let (toolbar, _) = make()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_opacityButtonActive == true)
        #expect(toolbar.testOnly_sizeButtonActive == false)
    }

    @Test("swap clears the previous trigger's active background and lights the new one")
    func swapMovesActiveHighlight() {
        let (toolbar, _) = make()
        toolbar.testOnly_clickSizeButton()
        toolbar.testOnly_clickOpacityButton()
        #expect(toolbar.testOnly_sizeButtonActive == false)
        #expect(toolbar.testOnly_opacityButtonActive == true)
    }
}
