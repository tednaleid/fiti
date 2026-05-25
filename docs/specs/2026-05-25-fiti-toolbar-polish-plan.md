# fiti Toolbar Polish + Cursor State Machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the fiti toolbar — drop misleading "stroke" labels, restack it one control wide, replace the size/opacity sliders with discrete-preset pickers (tool-aware visual + number), make the cursor a plain arrow over the toolbar, give selection-mode a crosshair, and fix color/width persistence so it tracks every input path.

**Architecture:** All policy is pure Core (`ValuePresets` + stepping, the over-toolbar cursor/input decision in `currentCursor`/`pointerDown`, the crosshair in `cursorFor`) or keyed to Core's canonical state-change callbacks (persistence). AppKit stays a thin adapter: it feeds the toolbar frame in as a `Rect`, renders the collapsed pickers + preset popovers, and persists on `onCurrentColorChanged`/`onCurrentWidthChanged`.

**Tech Stack:** Swift, Swift Testing (`import Testing`, `@Test`, `#expect`), AppKit, XcodeGen. `Sources/Core` stays pure (no AppKit/CoreGraphics/CoreText). All commands go through `just`.

---

## Conventions (apply to every task)

- **TDD red/green.** Write the failing test first, watch it fail, implement the minimum, watch it pass. The full suite stays under 5 seconds.
- **Test targets.** `just test` runs `fiti-unit` (Core). `just test-integration` runs `fiti-integration` (AppKit). After creating any **new** source or test file, run `just generate` before `just test*` so XcodeGen picks it up. In Swift, a "failing" test for a not-yet-existing symbol fails as a **compile error** — that is the red.
- **Commit gate.** `git commit` triggers a pre-commit hook that runs `just check` (test + test-integration + lint + build). Never `--no-verify`. If a flaky, unrelated test (e.g. `CursorRendererTests.allResolve`) fails the hook, re-run the commit; do not bypass.
- **Every new file** starts with two `// ABOUTME:` comment lines.
- **Commits** use a HEREDOC and end with the `Co-Authored-By` trailer shown in each task.
- **No raw tools.** Never call `xcodebuild`/`swiftlint`/`xcodegen`/`curl`/`rm -rf` directly — only `just` recipes.

---

# Phase 1 — Core policy (pure, unit-tested)

## Task 1: Size/opacity presets + stepping

**Files:**
- Create: `Sources/Core/Model/ValuePresets.swift`
- Test: `Tests/CoreTests/ModelTests/ValuePresetsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/ModelTests/ValuePresetsTests.swift`:

```swift
// ABOUTME: Tests the size/opacity preset lists and next/previous/closest helpers
// ABOUTME: that back the toolbar pickers and the keyboard size/opacity shortcuts.

import Testing

@Suite("ValuePresets")
struct ValuePresetsTests {
    @Test("preset lists are the agreed values")
    func lists() {
        #expect(ValuePresets.sizes == [2, 4, 6, 9, 14, 20, 30, 45, 70, 100])
        #expect(ValuePresets.opacities == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
    }

    @Test("nextPreset returns the first preset strictly greater than the value")
    func nextStepsUp() {
        #expect(nextPreset(after: 6, in: ValuePresets.sizes) == 9)   // on-preset
        #expect(nextPreset(after: 7, in: ValuePresets.sizes) == 9)   // off-preset
        #expect(nextPreset(after: 100, in: ValuePresets.sizes) == 100) // clamps at max
    }

    @Test("previousPreset returns the last preset strictly less than the value")
    func previousStepsDown() {
        #expect(previousPreset(before: 9, in: ValuePresets.sizes) == 6)  // on-preset
        #expect(previousPreset(before: 7, in: ValuePresets.sizes) == 6)  // off-preset
        #expect(previousPreset(before: 2, in: ValuePresets.sizes) == 2)  // clamps at min
    }

    @Test("opacity stepping lands on exact 10% increments")
    func opacityExactSteps() {
        #expect(nextPreset(after: 0.5, in: ValuePresets.opacities) == 0.6)
        #expect(previousPreset(before: 0.5, in: ValuePresets.opacities) == 0.4)
        #expect(nextPreset(after: 1.0, in: ValuePresets.opacities) == 1.0)
        #expect(previousPreset(before: 0.1, in: ValuePresets.opacities) == 0.1)
    }

    @Test("closestPresetIndex picks the nearest cell, ties to the lower index")
    func closest() {
        #expect(closestPresetIndex(to: 6, in: ValuePresets.sizes) == 2)
        #expect(closestPresetIndex(to: 7, in: ValuePresets.sizes) == 2)   // 7 closer to 6 than 9
        #expect(closestPresetIndex(to: 8, in: ValuePresets.sizes) == 3)   // 8 closer to 9
        #expect(closestPresetIndex(to: 0, in: []) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just generate && just test`
Expected: FAIL — compile error, `ValuePresets` / `nextPreset` / `previousPreset` / `closestPresetIndex` are undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/Core/Model/ValuePresets.swift`:

```swift
// ABOUTME: Pure size/opacity preset values plus next/previous/closest stepping.
// ABOUTME: Backs the toolbar pickers and the keyboard size/opacity shortcuts.

import Foundation

public enum ValuePresets {
    /// Stroke/arrow width presets in points. The text tool derives font size as
    /// width * 4, so these map to font sizes 8...400 (the smallest is an 8pt font).
    public static let sizes: [Double] = [2, 4, 6, 9, 14, 20, 30, 45, 70, 100]
    /// Opacity presets, 10%...100%.
    public static let opacities: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5,
                                            0.6, 0.7, 0.8, 0.9, 1.0]
}

/// First preset strictly greater than `value`; the largest preset when none is
/// greater (empty list -> `value`). Presets must be ascending.
public func nextPreset(after value: Double, in presets: [Double]) -> Double {
    presets.first(where: { $0 > value }) ?? presets.last ?? value
}

/// Last preset strictly less than `value`; the smallest preset when none is
/// less (empty list -> `value`). Presets must be ascending.
public func previousPreset(before value: Double, in presets: [Double]) -> Double {
    presets.last(where: { $0 < value }) ?? presets.first ?? value
}

/// Index of the preset nearest `value`, ties resolving to the lower index.
/// `nil` for an empty list.
public func closestPresetIndex(to value: Double, in presets: [Double]) -> Int? {
    guard !presets.isEmpty else { return nil }
    var best = 0
    var bestDist = abs(presets[0] - value)
    for i in 1..<presets.count {
        let d = abs(presets[i] - value)
        if d < bestDist { bestDist = d; best = i }
    }
    return best
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test`
Expected: PASS (whole `fiti-unit` suite green).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/ValuePresets.swift Tests/CoreTests/ModelTests/ValuePresetsTests.swift fiti.xcodeproj
git commit -F - <<'EOF'
Core: size/opacity presets + next/previous/closest stepping

Pure preset lists (sizes 2...100, opacity 10%...100%) and stepping
helpers that the toolbar pickers and keyboard shortcuts will share.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 2: Keyboard size/opacity shortcuts step through presets

**Files:**
- Modify: `Sources/Core/Control/AppController+Commands.swift:14-21`
- Modify (tests): `Tests/CoreTests/AppControllerTests/RunCommandTests.swift:45-110`

The tool-default `bumpSize`/`bumpOpacity` path becomes preset-stepping. The selection-mutation path (`applyStyleToSelection`/`resized`) is intentionally left on its multiplicative/additive behavior.

- [ ] **Step 1: Update the failing tests**

In `Tests/CoreTests/AppControllerTests/RunCommandTests.swift`, replace the bodies of these tests so they assert preset stepping:

```swift
    @Test("bumpSize(.up) steps to the next size preset")
    func bumpSizeUp() {
        let (c, _, _) = make()
        c.currentWidth = 10            // off-preset; next strictly greater is 14
        c.run(.bumpSize(.up))
        #expect(c.currentWidth == 14)
    }

    @Test("bumpSize(.down) steps to the previous size preset")
    func bumpSizeDown() {
        let (c, _, _) = make()
        c.currentWidth = 11            // off-preset; previous strictly less is 9
        c.run(.bumpSize(.down))
        #expect(c.currentWidth == 9)
    }

    @Test("bumpSize(.up) clamps at the largest preset")
    func bumpSizeUpClamp() {
        let (c, _, _) = make()
        c.currentWidth = 100
        c.run(.bumpSize(.up))
        #expect(c.currentWidth == 100)
    }

    @Test("bumpSize(.down) clamps at the smallest preset")
    func bumpSizeDownClamp() {
        let (c, _, _) = make()
        c.currentWidth = 2
        c.run(.bumpSize(.down))
        #expect(c.currentWidth == 2)
    }

    @Test("bumpOpacity(.up) steps to the next opacity preset")
    func bumpOpacityUp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.up))
        #expect(abs(c.currentColor.a - 0.6) < 0.0001)
        #expect(c.currentColor.r == 0.2)
        #expect(c.currentColor.g == 0.3)
        #expect(c.currentColor.b == 0.4)
    }

    @Test("bumpOpacity(.down) steps to the previous opacity preset")
    func bumpOpacityDown() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.down))
        #expect(abs(c.currentColor.a - 0.4) < 0.0001)
    }

    @Test("bumpOpacity(.up) clamps at 1.0")
    func bumpOpacityUpClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 1.0)
        c.run(.bumpOpacity(.up))
        #expect(c.currentColor.a == 1.0)
    }

    @Test("bumpOpacity(.down) clamps at the smallest preset (0.1)")
    func bumpOpacityDownClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.1)
        c.run(.bumpOpacity(.down))
        #expect(c.currentColor.a == 0.1)
    }
```

Leave `bumpSizeMidStrokeDoesNotRetro` as-is — it sets `currentWidth = 10`, bumps up (now -> 14) and only asserts `currentWidth > strokeBefore.width`, which still holds.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL — `bumpSizeUp` expects 14 but the current code multiplies 10 * 1.1 = 11 (and the other rewritten expectations likewise mismatch).

- [ ] **Step 3: Write the implementation**

In `Sources/Core/Control/AppController+Commands.swift`, change the four bump cases (lines 14-21) to:

```swift
        case .bumpSize(.up):
            currentWidth = nextPreset(after: currentWidth, in: ValuePresets.sizes)
        case .bumpSize(.down):
            currentWidth = previousPreset(before: currentWidth, in: ValuePresets.sizes)
        case .bumpOpacity(.up):
            currentColor = currentColor.with(a: nextPreset(after: currentColor.a, in: ValuePresets.opacities))
        case .bumpOpacity(.down):
            currentColor = currentColor.with(a: previousPreset(before: currentColor.a, in: ValuePresets.opacities))
```

Do not touch `applyStyleToSelection` or `resized`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS. (Note: `WidthClampTests.bumpClampsAt100` sets width 95; `nextPreset(after: 95)` is 100, so it stays green unchanged.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController+Commands.swift Tests/CoreTests/AppControllerTests/RunCommandTests.swift
git commit -F - <<'EOF'
Core: keyboard size/opacity shortcuts step through presets

bumpSize/bumpOpacity (the tool-default path) now jump to the next/
previous pickable preset instead of multiplying by 1.1 / adding 0.1, so
the keyboard lands on the same values the picker offers. Selection-
mutation shortcuts keep their existing behavior.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 3: `Rect.contains(Point)`

**Files:**
- Modify: `Sources/Core/Model/Rect.swift:26-28`
- Test: `Tests/CoreTests/ModelTests/RectContainsPointTests.swift`

`currentCursor` compares the toolbar region against `lastHoverPoint`, which is a `Point` (not a `StrokePoint`). `Rect` only has `contains(StrokePoint)` today.

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/ModelTests/RectContainsPointTests.swift`:

```swift
// ABOUTME: Tests Rect.contains(Point) — the overload currentCursor uses to test
// ABOUTME: the toolbar region against the (Point-typed) hover location.

import Testing

@Suite("Rect.contains(Point)")
struct RectContainsPointTests {
    @Test("inside, on the edge, and outside")
    func contains() {
        let r = Rect(x: 0, y: 0, width: 10, height: 20)
        #expect(r.contains(Point(x: 5, y: 5)) == true)
        #expect(r.contains(Point(x: 0, y: 0)) == true)   // edge is inside
        #expect(r.contains(Point(x: 10, y: 20)) == true) // far edge inside
        #expect(r.contains(Point(x: 11, y: 5)) == false)
        #expect(r.contains(Point(x: 5, y: -1)) == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just generate && just test`
Expected: FAIL — compile error, no `contains(_:Point)` overload.

- [ ] **Step 3: Write the implementation**

In `Sources/Core/Model/Rect.swift`, add directly after the existing `contains(_ p: StrokePoint)` (line 28):

```swift
    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/Rect.swift Tests/CoreTests/ModelTests/RectContainsPointTests.swift fiti.xcodeproj
git commit -F - <<'EOF'
Core: Rect.contains(Point) overload

currentCursor needs to test the toolbar region against the Point-typed
hover location; Rect previously only accepted StrokePoint.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 4: Toolbar region — arrow cursor + input suppression

**Files:**
- Modify: `Sources/Core/Control/AppController.swift` (add `toolbarRegion`; guard `pointerDown`)
- Modify: `Sources/Core/Control/AppController+SelectionGesture.swift:8-23` (`currentCursor`)
- Test: `Tests/CoreTests/AppControllerTests/ToolbarRegionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CoreTests/AppControllerTests/ToolbarRegionTests.swift`:

```swift
// ABOUTME: Tests the over-toolbar cursor/input policy: an arrow cursor when the
// ABOUTME: hover point is inside toolbarRegion, and no drawing started there.

import Testing

@Suite("AppController toolbar region")
@MainActor
struct ToolbarRegionTests {
    private func make() -> (AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker(), textMeasurer: FakeTextMeasurer())
        return (c, editor)
    }

    @Test("hovering inside the toolbar region shows the arrow cursor")
    func arrowOverToolbar() {
        let (c, _) = make()
        c.activate()                                   // pen tool, activeIdle
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerHover(StrokePoint(x: 10, y: 10), modifiers: .none)
        #expect(c.currentCursor == .system(.arrow))
    }

    @Test("hovering outside the toolbar region shows the tool cursor")
    func brushOutsideToolbar() {
        let (c, _) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerHover(StrokePoint(x: 400, y: 400), modifiers: .none)
        #expect(c.currentCursor == .brush(color: c.currentColor, diameter: c.currentWidth))
    }

    @Test("pointerDown inside the toolbar region starts no stroke")
    func noDrawUnderToolbar() {
        let (c, editor) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(editor.doc.items.isEmpty)
        #expect(c.mode == .activeIdle)
    }

    @Test("pointerDown just outside the toolbar region starts a stroke")
    func drawOutsideToolbar() {
        let (c, editor) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerDown(StrokePoint(x: 400, y: 400))
        #expect(c.mode == .activeDrawing)
        #expect(!editor.doc.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just generate && just test`
Expected: FAIL — compile error, `toolbarRegion` is undefined.

- [ ] **Step 3: Write the implementation**

In `Sources/Core/Control/AppController.swift`, add a stored property near the other public drawing state (e.g. just after `currentWidth`'s closing brace at line 103):

```swift
    /// The toolbar's frame in canvas coordinates, fed by the AppKit adapter.
    /// When the hover point is inside it, the cursor is a plain arrow and
    /// pointer-downs there start no mark. `nil` when unknown or inactive.
    public var toolbarRegion: Rect? {
        didSet { if oldValue != toolbarRegion { refreshCursor() } }
    }
```

In the same file, add the guard to `pointerDown(_:modifiers:)` (after the `guard mode != .inactive` line, line 238):

```swift
        if let region = toolbarRegion, region.contains(point) { return }
```

In `Sources/Core/Control/AppController+SelectionGesture.swift`, add the region check at the top of `currentCursor`, right after the `if mode == .inactive { return nil }` line (line 9):

```swift
        if let region = toolbarRegion, let p = lastHoverPoint, region.contains(p) {
            return .system(.arrow)
        }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift Sources/Core/Control/AppController+SelectionGesture.swift Tests/CoreTests/AppControllerTests/ToolbarRegionTests.swift
git commit -F - <<'EOF'
Core: toolbar-region cursor + input suppression

AppController gains a toolbarRegion rect (canvas coords). When the hover
point is inside it currentCursor returns the arrow, and pointerDown
there starts no mark, so the canvas never draws under the toolbar.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 5: Selection-mode crosshair

**Files:**
- Modify: `Sources/Core/Selection/SelectionRegion.swift:27-28`
- Modify (tests): `Tests/CoreTests/SelectionTests/CursorPolicyTests.swift:13`, `Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift:46-51`, `Tests/CoreTests/AppControllerTests/ToolStateTests.swift:47-53`

Outside the selection box means "draw a marquee," so the cursor should be a crosshair.

- [ ] **Step 1: Update the failing tests**

In `Tests/CoreTests/SelectionTests/CursorPolicyTests.swift`, change line 13:

```swift
        #expect(cursorFor(region: .outside, boxRotation: 0, dragging: false) == .crosshair)
```

In `Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift`, change the `@Test` name and assertion (lines 46-51):

```swift
    @Test("hovering outside the box emits the crosshair")
    func hoverOutsideEmitsCrosshair() {
        // (keep the existing setup body that hovers outside the box)
        #expect(c.currentCursor == .system(.crosshair))
    }
```

In `Tests/CoreTests/AppControllerTests/ToolStateTests.swift`, change the `@Test` name and assertion (lines 47-53):

```swift
    @Test("cursor is .system(.crosshair) while currentTool is .selection in an active mode")
    func selectionCrosshair() {
        // (keep the existing setup that puts the controller in active selection mode)
        #expect(c.currentCursor == .system(.crosshair))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL — `cursorFor(.outside)` still returns `.arrow`.

- [ ] **Step 3: Write the implementation**

In `Sources/Core/Selection/SelectionRegion.swift`, change the `.outside` case (line 27-28) of `cursorFor`:

```swift
    case .outside:
        return .crosshair
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Selection/SelectionRegion.swift Tests/CoreTests/SelectionTests/CursorPolicyTests.swift Tests/CoreTests/AppControllerTests/SelectionBoxHoverTests.swift Tests/CoreTests/AppControllerTests/ToolStateTests.swift
git commit -F - <<'EOF'
Core: selection-mode crosshair outside the box

Outside the selection box means "draw a marquee", so cursorFor(.outside)
now returns .crosshair instead of .arrow.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

# Phase 2 — AppKit small changes

## Task 6: Drop "stroke" from the size/opacity labels and tooltips

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift:23-24` (label init), `:127` and `:135` (slider tooltips)
- Modify (tests): `Tests/AppKitTests/ToolbarControllerTests.swift:261-299`

- [ ] **Step 1: Update the failing tests**

In `Tests/AppKitTests/ToolbarControllerTests.swift`, change the four expectations:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test-integration`
Expected: FAIL — labels still read "stroke size"/"stroke opacity", tooltips still "Stroke …".

- [ ] **Step 3: Write the implementation**

In `Sources/AppKit/ToolbarController.swift`:
- Line 23: `private let widthLabel = NSTextField(labelWithString: "size")`
- Line 24: `private let opacityLabel = NSTextField(labelWithString: "opacity")`
- Line 127: `widthSlider.toolTip = "Size — s / S"`
- Line 135: `opacitySlider.toolTip = "Opacity — o / O"`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test-integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -F - <<'EOF'
AppKit: drop "stroke" from size/opacity labels and tooltips

The size and opacity controls apply to every tool, not just strokes.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 7: Factor the brush-dab image out of CursorRenderer

**Files:**
- Modify: `Sources/AppKit/CursorRenderer.swift:78-108`
- Test: `Tests/AppKitTests/BrushDabImageTests.swift`

The pen size-preview must draw the exact dab the brush cursor draws. Factor the dab into a free function both call.

- [ ] **Step 1: Write the failing test**

Create `Tests/AppKitTests/BrushDabImageTests.swift`:

```swift
// ABOUTME: Tests fitiBrushDabImage — the shared dab drawing used by both the
// ABOUTME: brush cursor and the size picker's pen preview.

import AppKit
import Testing

@Suite("fitiBrushDabImage")
@MainActor
struct BrushDabImageTests {
    @Test("image size is the fill diameter (width/2) plus the outline on both sides")
    func sizeMatchesSpec() {
        // diameter 10 -> fill 5, +1pt outline each side -> 7x7.
        let img = fitiBrushDabImage(color: RGBA(r: 1, g: 0, b: 0, a: 1),
                                    diameter: 10, outlineWidth: 1)
        #expect(abs(img.size.width - 7) < 0.01)
        #expect(abs(img.size.height - 7) < 0.01)
    }

    @Test("tiny diameters still produce a positive-size image")
    func tinyClamps() {
        let img = fitiBrushDabImage(color: RGBA(r: 0, g: 0, b: 0, a: 1),
                                    diameter: 1, outlineWidth: 1)
        #expect(img.size.width > 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just generate && just test-integration`
Expected: FAIL — compile error, `fitiBrushDabImage` is undefined.

- [ ] **Step 3: Write the implementation**

In `Sources/AppKit/CursorRenderer.swift`, add a file-scope function (below the imports, above the class) that contains the dab-drawing logic currently inside `makeBrushCursor`:

```swift
/// Draws the filled brush dab (inner color disc + outside contrast ring) used by
/// both the brush cursor and the size picker's pen preview. `diameter` is the
/// brush spec; the visible fill is half that (matching what gets drawn).
@MainActor
func fitiBrushDabImage(color: RGBA, diameter: Double, outlineWidth: CGFloat) -> NSImage {
    let fillDiameter = max(1.0, CGFloat(diameter) / 2)
    let outerDiameter = fillDiameter + outlineWidth * 2
    let size = NSSize(width: outerDiameter, height: outerDiameter)
    let outline = CursorSpec.outlineColor(for: color)
    let outerRect = NSRect(x: 0, y: 0, width: outerDiameter, height: outerDiameter)
    let innerRect = NSRect(x: outlineWidth, y: outlineWidth, width: fillDiameter, height: fillDiameter)
    return NSImage(size: size, flipped: false) { _ in
        let ring = NSBezierPath()
        ring.append(NSBezierPath(ovalIn: outerRect))
        ring.append(NSBezierPath(ovalIn: innerRect))
        ring.windingRule = .evenOdd
        NSColor(srgbRed: outline.r, green: outline.g, blue: outline.b, alpha: outline.a).setFill()
        ring.fill()
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
        NSBezierPath(ovalIn: innerRect).fill()
        return true
    }
}
```

Then rewrite `makeBrushCursor` (lines 78-108) to use it:

```swift
    private func makeBrushCursor(color: RGBA, diameter: Double) -> NSCursor {
        let image = fitiBrushDabImage(color: color, diameter: diameter, outlineWidth: outlineWidth)
        let center = image.size.width / 2
        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test-integration`
Expected: PASS, and existing `CursorRendererTests` stay green (the cursor image is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/CursorRenderer.swift Tests/AppKitTests/BrushDabImageTests.swift fiti.xcodeproj
git commit -F - <<'EOF'
AppKit: factor brush-dab image out of CursorRenderer

fitiBrushDabImage(color:diameter:outlineWidth:) is now the single source
of truth for the dab; the brush cursor and the upcoming size picker both
render from it.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

# Phase 3 — AppKit toolbar: persistence + value pickers

## Task 8: Persist color/width on canonical state change

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift:42-47` (callbacks), `:283`, `:294-295`, `:300` (remove scattered persist calls)
- Test: `Tests/AppKitTests/ToolbarControllerTests.swift` (add a regression test)

Persistence currently only fires inside toolbar widget handlers, so keyboard/menubar/HTTP color and width changes never persist. Re-key persistence to the canonical `onCurrentColorChanged`/`onCurrentWidthChanged` callbacks (which fire on every change) and delete the per-action calls.

- [ ] **Step 1: Write the failing test**

Add to the `ToolbarControllerTests` suite in `Tests/AppKitTests/ToolbarControllerTests.swift`:

```swift
    @Test("non-widget color/width changes persist (keyboard/menubar/HTTP path)")
    func nonWidgetChangesPersist() {
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
        _ = ToolbarController(controller: controller, defaults: suite)
        // Simulate a keyboard/HTTP change: set the controller state directly,
        // NOT through a toolbar widget.
        controller.currentColor = RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        controller.currentWidth = 9
        #expect(suite.double(forKey: "fiti.color.r") == 0.1)
        #expect(suite.double(forKey: "fiti.color.a") == 0.4)
        #expect(suite.double(forKey: "fiti.width") == 9)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just test-integration`
Expected: FAIL — nothing persists `fiti.color.r` / `fiti.width` for a direct controller change.

- [ ] **Step 3: Write the implementation**

In `Sources/AppKit/ToolbarController.swift`, fold persistence into the existing callbacks (lines 42-47):

```swift
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
            self?.persistColor()
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.widthSlider.doubleValue = width
            self?.defaults.set(width, forKey: "fiti.width")
        }
```

Then delete the now-redundant persist calls so they are not duplicated:
- In `colorClicked` (line ~283): remove the trailing `persistColor()`.
- In `customColorChanged` (line ~289): remove the trailing `persistColor()`.
- In `widthChanged` (lines 294-295): remove `defaults.set(controller.currentWidth, forKey: "fiti.width")` (the callback now persists).
- In `opacityChanged` (line ~300): remove the trailing `persistColor()`.

(`persistColor()` stays defined — it is now called only from the color callback.) Loading still runs in `loadPersistedState()` before the callbacks are assigned, so there is no load-time echo.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test-integration`
Expected: PASS — the new regression test passes, and the existing `widgetChangesPersist` / `persistedOverrides` tests stay green (widget changes still flow through `currentColor`/`currentWidth` to the callbacks).

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -F - <<'EOF'
AppKit: persist color/width on canonical state change

Persistence was wired only to toolbar widget handlers, so changing color
or width via the keyboard, menubar, or HTTP never saved. Persist inside
onCurrentColorChanged/onCurrentWidthChanged instead, which fire on every
change, and drop the scattered per-action persist calls.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 9: `ValuePickerControl` — collapsed example + number, preset popover

**Files:**
- Create: `Sources/AppKit/ValuePickerControl.swift`
- Test: `Tests/AppKitTests/ValuePickerControlTests.swift`

A self-contained control: collapsed it shows a tool-aware example (size) or color swatch (opacity) plus the number; clicking opens an `NSPopover` with a horizontal strip of preset cells. This task builds and unit-tests the control in isolation; Task 10 wires it into the toolbar.

- [ ] **Step 1: Write the failing test**

Create `Tests/AppKitTests/ValuePickerControlTests.swift`:

```swift
// ABOUTME: Tests ValuePickerControl — display string, tool-aware size preview,
// ABOUTME: and that selecting a preset cell fires onPick with that value.

import AppKit
import Testing

@Suite("ValuePickerControl")
@MainActor
struct ValuePickerControlTests {
    @Test("size control shows the integer width")
    func sizeDisplay() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        #expect(pc.testOnly_displayString == "6")
    }

    @Test("opacity control shows the percent")
    func opacityDisplay() {
        let pc = ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.5)
        #expect(pc.testOnly_displayString == "50%")
    }

    @Test("selecting a preset cell fires onPick with that preset value")
    func pickFires() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        var picked: Double?
        pc.onPick = { picked = $0 }
        pc.testOnly_selectPreset(at: 4)   // ValuePresets.sizes[4] == 14
        #expect(picked == 14)
    }

    @Test("the size preview renders for each tool without crashing")
    func toolAwarePreview() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 20)
        pc.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        for tool in [Tool.pen, .arrow, .text, .selection] {
            pc.currentTool = tool
            #expect(pc.testOnly_previewImage().size.width > 0)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just generate && just test-integration`
Expected: FAIL — compile error, `ValuePickerControl` is undefined.

- [ ] **Step 3: Write the implementation**

Create `Sources/AppKit/ValuePickerControl.swift`:

```swift
// ABOUTME: Toolbar control showing a tool-aware example + number (size) or a color
// ABOUTME: swatch + percent (opacity), opening a horizontal preset popover on click.

import AppKit

@MainActor
final class ValuePickerControl: NSView {
    enum Kind { case size, opacity }

    private let kind: Kind
    private let presets: [Double]
    private(set) var value: Double
    var onPick: ((Double) -> Void)?

    /// Drives the size preview glyph and color. Updating either repaints.
    var currentTool: Tool = .pen { didSet { needsDisplay = true } }
    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { needsDisplay = true } }

    var toolTipText: String? {
        didSet { toolTip = toolTipText }
    }

    private let cellSize: CGFloat = 22

    init(kind: Kind, presets: [Double], value: Double) {
        self.kind = kind
        self.presets = presets
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setValue(_ v: Double) {
        value = v
        needsDisplay = true
    }

    // MARK: Display

    var displayString: String {
        switch kind {
        case .size: return "\(Int(value.rounded()))"
        case .opacity: return "\(Int((value * 100).rounded()))%"
        }
    }

    /// The collapsed-state example glyph at the current value, scaled to fit `box`.
    func previewImage(maxSide: CGFloat) -> NSImage {
        switch kind {
        case .opacity:
            return swatchImage(alpha: value, side: maxSide)
        case .size:
            switch currentTool {
            case .pen, .selection:
                return scaledToFit(fitiBrushDabImage(color: color, diameter: value, outlineWidth: 1),
                                   maxSide: maxSide)
            case .arrow:
                return scaledToFit(arrowGlyphImage(color: color, width: value), maxSide: maxSide)
            case .text:
                return letterTImage(color: color, fontSize: value * 4, maxSide: maxSide)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let img = previewImage(maxSide: bounds.height - 2)
        let imgRect = NSRect(x: 2, y: (bounds.height - img.size.height) / 2,
                             width: img.size.width, height: img.size.height)
        img.draw(in: imgRect)
        let text = displayString as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor
        ]
        let tsize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.width - tsize.width - 2,
                              y: (bounds.height - tsize.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        presentPopover()
    }

    // MARK: Popover

    private func presentPopover() {
        let strip = NSStackView()
        strip.orientation = .horizontal
        strip.spacing = 4
        strip.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        for (i, preset) in presets.enumerated() {
            let btn = NSButton(title: "", target: self, action: #selector(presetClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare
            btn.imagePosition = .imageOnly
            btn.image = cellImage(for: preset)
            strip.addArrangedSubview(btn)
        }
        let vc = NSViewController()
        vc.view = strip
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.contentSize = strip.fittingSize
        activePopover = pop
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    private var activePopover: NSPopover?

    private func cellImage(for preset: Double) -> NSImage {
        switch kind {
        case .opacity: return swatchImage(alpha: preset, side: cellSize)
        case .size:
            switch currentTool {
            case .pen, .selection:
                return scaledToFit(fitiBrushDabImage(color: color, diameter: preset, outlineWidth: 1), maxSide: cellSize)
            case .arrow:
                return scaledToFit(arrowGlyphImage(color: color, width: preset), maxSide: cellSize)
            case .text:
                return letterTImage(color: color, fontSize: preset * 4, maxSide: cellSize)
            }
        }
    }

    @objc private func presetClicked(_ sender: NSButton) {
        let v = presets[sender.tag]
        setValue(v)
        onPick?(v)
        activePopover?.close()
        activePopover = nil
    }

    // MARK: Glyph drawing

    private func swatchImage(alpha: Double, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // checkerboard so alpha reads
            NSColor.white.setFill(); rect.fill()
            NSColor(white: 0.8, alpha: 1).setFill()
            let h = rect.height / 2, w = rect.width / 2
            NSRect(x: 0, y: 0, width: w, height: h).fill()
            NSRect(x: w, y: h, width: w, height: h).fill()
            NSColor(srgbRed: self.color.r, green: self.color.g, blue: self.color.b,
                    alpha: CGFloat(alpha)).setFill()
            rect.fill()
            return true
        }
    }

    private func arrowGlyphImage(color: RGBA, width: Double) -> NSImage {
        let side: CGFloat = 24
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: side / 2))
            p.line(to: NSPoint(x: side - 6, y: side / 2))
            p.lineWidth = max(1, CGFloat(width) / 2)
            p.lineCapStyle = .round
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setStroke()
            p.stroke()
            // small head
            let head = NSBezierPath()
            head.move(to: NSPoint(x: side - 3, y: side / 2))
            head.line(to: NSPoint(x: side - 10, y: side / 2 + 6))
            head.line(to: NSPoint(x: side - 10, y: side / 2 - 6))
            head.close()
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
            head.fill()
            return true
        }
    }

    private func letterTImage(color: RGBA, fontSize: Double, maxSide: CGFloat) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(fontSize)),
            .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
        ]
        let s = "T" as NSString
        let natural = s.size(withAttributes: attrs)
        let img = NSImage(size: natural, flipped: false) { _ in
            s.draw(at: .zero, withAttributes: attrs); return true
        }
        return scaledToFit(img, maxSide: maxSide)
    }

    private func scaledToFit(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect); return true
        }
    }

    // MARK: Test hooks

    var testOnly_displayString: String { displayString }
    func testOnly_selectPreset(at index: Int) {
        let v = presets[index]
        setValue(v)
        onPick?(v)
    }
    func testOnly_previewImage() -> NSImage { previewImage(maxSide: 22) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `just test-integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ValuePickerControl.swift Tests/AppKitTests/ValuePickerControlTests.swift fiti.xcodeproj
git commit -F - <<'EOF'
AppKit: ValuePickerControl with tool-aware preview + preset popover

Collapsed control shows a tool-aware example (pen dab, arrow, or "T" for
text) plus the number for size, or a color swatch plus percent for
opacity. Clicking opens a horizontal popover of the presets; selecting
one fires onPick.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 10: One-wide layout + swap sliders for pickers

**Files:**
- Modify: `Sources/AppKit/ToolbarController.swift` (replace sliders with pickers; rebuild `buildContent` as one column; rework test hooks)
- Modify: `Sources/AppKit/ToolbarPanel.swift:8` (initial frame; autosave name)
- Modify (tests): `Tests/AppKitTests/ToolbarControllerTests.swift` (slider hooks -> picker hooks)

- [ ] **Step 1: Update the failing tests**

In `Tests/AppKitTests/ToolbarControllerTests.swift`, the hooks `testOnly_setWidth`, `testOnly_setOpacity`, and `testOnly_widthSliderValue` now drive/read the pickers; their call sites stay the same. Keep the existing assertions:
- `opacityPreservesRGB`: `toolbar.testOnly_setOpacity(0.3)` then `controller.currentColor.a == 0.3` (rgb preserved).
- `widthSlider`: `toolbar.testOnly_setWidth(12)` then `controller.currentWidth == 12`.
- `widgetChangesPersist`: `testOnly_setWidth(9)` / `testOnly_setOpacity(0.6)` then `suite.double(forKey: "fiti.width") == 9` / `"fiti.color.a") == 0.6`.
- `externalWidthWriteUpdatesWidget`: `controller.currentWidth = 17` then `toolbar.testOnly_widthSliderValue == 17`.

Add a tool-tracking test:

```swift
    @Test("size picker preview tool follows controller.currentTool")
    func sizePickerTracksTool() {
        let (toolbar, controller) = makeTooltipHarness()
        controller.activate()
        controller.currentTool = .text
        #expect(toolbar.testOnly_sizePickerTool == .text)
    }
```

(Use whichever existing `make()` helper returns `(ToolbarController, AppController)`; rename to `makeTooltipHarness` only if you need a fresh one — otherwise reuse `make()`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test-integration`
Expected: FAIL — compile error (`testOnly_sizePickerTool` undefined) and/or the hooks still reference removed sliders.

- [ ] **Step 3: Write the implementation**

In `Sources/AppKit/ToolbarController.swift`:

1. Replace the slider properties (lines 17-18) with pickers:

```swift
    private let sizePicker = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
    private let opacityPicker = ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.8)
```

Remove the `widthSlider`/`opacitySlider` initializations in `init` (lines 32-33).

2. In `init`, after `loadPersistedState()`, seed the pickers and wire their `onPick`:

```swift
        sizePicker.setValue(controller.currentWidth)
        sizePicker.color = controller.currentColor
        sizePicker.currentTool = controller.currentTool
        sizePicker.toolTipText = "Size — s / S"
        sizePicker.onPick = { [weak self] v in self?.controller.currentWidth = v }

        opacityPicker.setValue(controller.currentColor.a)
        opacityPicker.color = controller.currentColor
        opacityPicker.toolTipText = "Opacity — o / O"
        opacityPicker.onPick = { [weak self] v in
            guard let self else { return }
            let c = self.controller.currentColor
            self.controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: v)
        }
```

3. Update the callbacks (from Task 8) to refresh the pickers:

```swift
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
            self?.sizePicker.color = color
            self?.opacityPicker.color = color
            self?.opacityPicker.setValue(color.a)
            self?.persistColor()
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.sizePicker.setValue(width)
            self?.defaults.set(width, forKey: "fiti.width")
        }
        controller.onCurrentToolChanged = { [weak self] tool in
            self?.updateToolHighlights()
            self?.sizePicker.currentTool = tool
        }
```

(Replace the existing `onCurrentToolChanged` body, which only calls `updateToolHighlights`.)

4. Rebuild `buildContent` as a single vertical column. Keep the existing stack setup but change the tool row and color rows to one-wide, and use the pickers:

```swift
        // Tools, one per row
        configureToolButton(penButton, symbol: "pencil.tip", accessibility: "Pen",
                            tooltip: "Pen — p", action: #selector(penClicked(_:)))
        configureToolButton(textButton, symbol: "textformat", accessibility: "Text",
                            tooltip: "Text — t", action: #selector(textClicked(_:)))
        configureToolButton(arrowButton, symbol: "line.diagonal.arrow", accessibility: "Arrow",
                            tooltip: "Arrow — a", action: #selector(arrowClicked(_:)))
        stack.addArrangedSubview(penButton)
        stack.addArrangedSubview(textButton)
        stack.addArrangedSubview(arrowButton)

        // Colors, one per row
        for (i, color) in QuickPickPalette.colors.enumerated() {
            let btn = NSButton(title: "", target: self, action: #selector(colorClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare
            btn.image = makeSwatchImage(r: color.r, g: color.g, b: color.b)
            btn.imagePosition = .imageOnly
            btn.toolTip = "\(color.name) — \(i + 1)"
            quickPickButtons.append(btn)
            stack.addArrangedSubview(btn)
        }

        // Custom well
        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        colorWell.color = NSColor(red: CGFloat(controller.currentColor.r),
                                  green: CGFloat(controller.currentColor.g),
                                  blue: CGFloat(controller.currentColor.b),
                                  alpha: CGFloat(controller.currentColor.a))
        colorWell.toolTip = "Custom color"
        stack.addArrangedSubview(colorWell)

        // Size + opacity pickers (with labels)
        styleSliderLabel(widthLabel)
        stack.addArrangedSubview(widthLabel)
        stack.addArrangedSubview(sizePicker)
        styleSliderLabel(opacityLabel)
        stack.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacityPicker)

        // Hide + fade (unchanged)
        // ... existing hideButton / autoFadeButton setup ...
```

Remove the old `widthSlider`/`opacitySlider` `target`/`action`/`addArrangedSubview` blocks. Keep `widthChanged`/`opacityChanged` only if a test still references them; otherwise the picker `onPick` closures replace them — delete `widthChanged`/`opacityChanged` and their `@objc`.

5. Rework the test hooks at the bottom of the file:

```swift
    internal func testOnly_setWidth(_ value: Double) {
        sizePicker.setValue(value)
        controller.currentWidth = value
    }
    internal func testOnly_setOpacity(_ value: Double) {
        opacityPicker.setValue(value)
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: value)
    }
    internal var testOnly_widthSliderValue: Double { sizePicker.value }
    internal var testOnly_widthSliderTooltip: String? { sizePicker.toolTipText }
    internal var testOnly_opacitySliderTooltip: String? { opacityPicker.toolTipText }
    internal var testOnly_sizePickerTool: Tool { sizePicker.currentTool }
```

In `Sources/AppKit/ToolbarPanel.swift`, change the initial frame to the taller, narrower column and bump the autosave name so the stale saved frame is discarded once (line 8 and line 17):

```swift
        let initialRect = NSRect(x: 24, y: 24, width: 56, height: 560)
        // ...
        self.setFrameAutosaveName("fiti.toolbar.v2")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test-integration`
Expected: PASS. If SwiftLint flags `buildContent`/`type_body_length`, keep the existing `// swiftlint:disable:next function_body_length` on `buildContent` and the `type_body_length` disable already on the class.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppKit/ToolbarController.swift Sources/AppKit/ToolbarPanel.swift Tests/AppKitTests/ToolbarControllerTests.swift
git commit -F - <<'EOF'
AppKit: one-wide toolbar layout + preset value pickers

Restack the toolbar into a single column (tools, 8 colors, custom well,
size, opacity, hide, fade) and replace the size/opacity sliders with
ValuePickerControls. The size picker follows the current tool; bump the
panel autosave name for the new tall/narrow frame.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

# Phase 4 — Wiring + cleanup

## Task 11: Feed the toolbar frame to the controller as a canvas-space rect

**Files:**
- Modify: `Sources/App/main.swift` (compute `toolbarRegion`; update on toolbar move and canvas resize)

This is glue between AppKit windows and the Core policy; the policy itself is already unit-tested (Task 4). Verify behavior manually with the running app.

- [ ] **Step 1: Write the implementation**

In `Sources/App/main.swift`, add a helper that converts the toolbar panel frame (screen coords) into the flipped canvas-view coordinate space and assigns it:

```swift
    @MainActor
    private func syncToolbarRegion() {
        guard controller.mode != .inactive else {
            controller.toolbarRegion = nil
            return
        }
        let screenFrame = toolbar.panel.frame                       // screen coords
        let windowFrame = window.convertFromScreen(screenFrame)     // window coords
        let viewRect = inputView.convert(windowFrame, from: nil)    // flipped view coords
        controller.toolbarRegion = Rect(x: Double(viewRect.minX), y: Double(viewRect.minY),
                                        width: Double(viewRect.width), height: Double(viewRect.height))
    }
```

Call it:
- At the end of `applicationDidFinishLaunching` (after `wireInputAndSubscriptions()`), once: `syncToolbarRegion()`.
- Inside `composeControllerCallbacks`, extend the composed `onModeChanged` so the region clears/recomputes on activation changes:

```swift
        controller.onModeChanged = { [weak self] mode in
            menubarModeHandler?(mode)
            self?.toolbar.updateVisibility(for: mode)
            self?.keyMonitor.syncRegistration(for: mode)
            self?.syncToolbarRegion()
        }
```

- In `followToolbarToScreen`, after `window.setFrame(...)`, add `syncToolbarRegion()`. Also call `syncToolbarRegion()` at the end of `observeToolbarScreenChanges`' notification block (the toolbar can move within a screen without changing screens — observe `NSWindow.didMoveNotification` on `toolbar.panel` the same way and call `syncToolbarRegion()`):

```swift
        toolbarMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: toolbar.panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncToolbarRegion() }
        }
```

Add `private var toolbarMoveObserver: NSObjectProtocol?` next to `toolbarScreenObserver`.

- [ ] **Step 2: Build and verify manually**

Run: `just build`
Expected: builds clean.

Then exercise it:

```bash
just run-bg
just inspect-activate
just inspect-state          # confirm mode active
just inspect-screenshot     # baseline
```

Manual checks (the cursor is not captured in screenshots, so observe on screen):
- Move the mouse over the toolbar with the **pen** tool selected: cursor is the arrow, not the brush circle.
- Select the **text** tool, move over the toolbar: cursor is the arrow, no I-beam, no text preview placed on the toolbar.
- Click within the toolbar area: tools/colors respond; no stroke/text appears under the toolbar.
- Drag the toolbar to a new position, repeat: the arrow region tracks it.

```bash
just stop
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/main.swift
git commit -F - <<'EOF'
App: feed toolbar frame to controller as canvas-space toolbarRegion

Convert the floating toolbar panel frame into flipped canvas-view
coordinates and assign controller.toolbarRegion, recomputing on
activation, screen change, and toolbar move; clear it when inactive.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
```

---

## Task 12: Clear the stale persisted orange (one-time)

**Files:** none (operational data fix)

The persisted color in `com.fiti.app` is orange from before the persistence fix. With Task 8 in place, the next color the user picks will stick — but clear the stale value once so the very next launch is already the red default.

- [ ] **Step 1: Confirm the stale value**

Run: `defaults read com.fiti.app | grep -i color`
Expected: shows `fiti.color.r ≈ 0.969` (orange).

- [ ] **Step 2: Delete the persisted color keys so the code default (red) applies**

Run:

```bash
defaults delete com.fiti.app fiti.color.r
defaults delete com.fiti.app fiti.color.g
defaults delete com.fiti.app fiti.color.b
defaults delete com.fiti.app fiti.color.a
```

(Leave `fiti.width`, `fiti.autoFade`, and outline keys intact.)

- [ ] **Step 3: Verify the default returns**

Run:

```bash
just run-bg
just inspect-state
```

Expected: the active color is red `#e03131` (the code default), since no persisted color overrides it. Then:

```bash
just stop
```

No commit (no code changed).

---

## Final review

After all tasks, dispatch a final code review over the branch diff (`git diff main...toolbar-polish`) against this plan and the design spec, then run `just check` once more to confirm the full gate is green. Hand off via superpowers:finishing-a-development-branch.

## Self-review notes (author)

- **Spec coverage:** label cleanup (T6), one-wide layout (T10), discrete pickers + visual/number + tool-aware preview (T9, T10) + keyboard preset stepping (T1, T2), over-toolbar cursor/suppression (T1 region helper via T3, T4) + wiring (T11), select-mode crosshair (T5), persistence fix (T8), stale-orange clear (T12). All spec sections map to a task.
- **Type consistency:** `ValuePresets`, `nextPreset`/`previousPreset`/`closestPresetIndex`, `Rect.contains(Point)`, `AppController.toolbarRegion: Rect?`, `ValuePickerControl(kind:presets:value:)` with `onPick`/`currentTool`/`color`/`setValue`/`displayString` and `testOnly_*` hooks, and `fitiBrushDabImage(color:diameter:outlineWidth:)` are used consistently across tasks.
- **Sequencing:** every task keeps `just check` green at its commit. Phase 1 is pure Core; Phase 2 adds isolated AppKit pieces; Phase 3 lands persistence before the control swap so each is independently testable; Phase 4 is glue + a data fix.
