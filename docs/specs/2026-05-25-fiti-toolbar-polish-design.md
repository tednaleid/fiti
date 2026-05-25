# fiti Toolbar Polish + Cursor State Machine

Status: design approved 2026-05-25. Work on branch `toolbar-polish`.

## Summary

A batch of toolbar and cursor polish driven by direct use:

1. **Label cleanup** — the size/opacity controls say "stroke size" / "stroke
   opacity" but apply to every tool; drop the misleading "stroke".
2. **One-wide vertical layout** — restack the whole toolbar into a single
   column (tools, the 8 color swatches, custom well, size, opacity, hide, fade)
   so it matches the vertical hide/fade controls and reads top-to-bottom.
3. **Discrete-preset value controls** — replace the size and opacity
   `NSSlider`s with a collapsed control that shows a visual example plus the
   number; clicking it opens a horizontal popover of ~10 presets. Keyboard
   `s`/`o` step to the next/previous pickable preset (deterministic, not a
   coincidental 10%). Values stay continuous `Double`s internally.
4. **Cursor/input state machine over the toolbar** — extend the existing pure
   Core cursor policy so that when the pointer is over the toolbar region the
   cursor is a plain arrow and the canvas suppresses drawing/text. Today the
   canvas can leak its tool cursor (and, in edge cases, marks) under the
   floating toolbar.
5. **Select-mode crosshair** — in selection mode, hovering outside the
   selection box means "draw a marquee," so the cursor should be a crosshair,
   not the arrow it is today.
6. **Persistence bug fix** — color/width only persist when set through the
   toolbar's own widgets; changing them via the keyboard, the menubar, or HTTP
   never persists. Re-key persistence to the canonical state-change callbacks
   so "last-used" actually works from every input path.

The unifying principle: all policy (presets, stepping, the over-toolbar cursor
decision, the crosshair, and "persist on canonical change") lives in pure Core
and is unit-tested. AppKit stays a thin adapter that feeds geometry in and
renders the result.

## Goals

- Remove "stroke" from the size/opacity labels and tooltips.
- A single-column toolbar, one control wide, colors stacked vertically.
- Size and opacity become discrete-preset pickers (visual example + number,
  horizontal popover), backed by a pure Core preset/stepping policy. Keyboard
  `s`/`S` and `o`/`O` step to the next/previous preset.
- A pure Core cursor/input policy that knows the toolbar region: arrow cursor
  over the toolbar, and no stroke/text/arrow starts there.
- Selection-mode crosshair when outside the box.
- Color/width persist on every change regardless of input source.

## Non-goals

- Changing the keyboard shortcut *keys* (`s`/`S`, `o`/`O`, `1`–`8`, etc.).
- Changing how selection-mutation shortcuts resize existing selected items
  (those keep today's multiplicative size / additive opacity behavior — the
  preset stepping applies only to the tool defaults the toolbar shows).
- Any new persisted setting, or a new persistence framework. We re-key the
  existing UserDefaults persistence, we do not add a store.
- Reworking the color palette, the color well, or the hide/fade controls beyond
  placing them in the new single column.
- Touching the document model or serialization.

## Decisions (from brainstorming)

- **Value model:** presets in the UI, continuous `Double` internally.
  `currentWidth` / `currentColor.a` keep their full range; HTTP can still set
  any value. The popover and keyboard offer the presets.
- **Keyboard stepping:** `s`/`o` jump to the next *pickable* preset, `S`/`O` to
  the previous one — "first preset strictly greater" / "last preset strictly
  less" than the current value, clamped at the ends. Off-preset values (e.g. an
  HTTP-set 7) step to the next pickable preset, not the nearest. This is
  enforced by the preset list, not a coincidental 10%.
- **Collapsed display:** visual example *and* number. Size shows a filled dot
  scaled to the width plus the integer; opacity shows a swatch at that alpha
  plus the percent.
- **Layout:** fully one-wide, including the 8 colors stacked vertically.
- **Color default:** keep persisting last-used color (the user is fine with
  that) — but fix the bug so it persists from every input path. No forced red
  default; correct persistence yields red because red is what was last used.
  Clear the stale orange value once so the next launch is already red.
- **Over-toolbar behavior:** the cursor/behavior decision is a pure Core state
  machine keyed on whether the hover point is inside a toolbar region rect that
  the AppKit adapter feeds in (canvas coordinates).

## Architecture

### Pure Core: the policy lives here

- `Sources/Core/Model/ValuePresets.swift` (new):
  ```swift
  public enum ValuePresets {
      /// Stroke-width presets spanning 1...maxStrokeWidth (tuned in-app).
      public static let sizes: [Double] = [2, 4, 6, 9, 14, 20, 30, 45, 70, 100]
      /// Opacity presets, 10%...100%.
      public static let opacities: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5,
                                               0.6, 0.7, 0.8, 0.9, 1.0]
  }

  /// First preset strictly greater than `value`; the max if none is greater.
  public func nextPreset(after value: Double, in presets: [Double]) -> Double

  /// Last preset strictly less than `value`; the min if none is less.
  public func previousPreset(before value: Double, in presets: [Double]) -> Double
  ```
  Presets are ascending. Stepping is defined on `>`/`<` so any value (on or off
  a preset) advances deterministically; the ends clamp.
- `Sources/Core/Control/AppController+Commands.swift` (modified): rewire
  `bumpSize` and `bumpOpacity` for the **tool-default** path to use
  `nextPreset`/`previousPreset` over `ValuePresets.sizes` / `.opacities`
  instead of `currentWidth *= 1.1` / `currentColor.a += 0.1`. The
  selection-mutation path (`mutateSelection`) is unchanged.
- `Sources/Core/Control/AppController.swift` (modified): add
  `public var toolbarRegion: Rect?` (canvas coordinates; `nil` = unknown/none).
  Setting it calls `refreshCursor()`.
- `Sources/Core/Control/AppController+SelectionGesture.swift` (modified):
  `currentCursor` checks the toolbar region first. After the
  `mode == .inactive -> nil` guard:
  ```swift
  if let region = toolbarRegion, let p = lastHoverPoint, region.contains(p) {
      return .system(.arrow)
  }
  ```
  (`Rect.contains(StrokePoint)` already exists; `lastHoverPoint` is a `Point`,
  so add a `Point`-accepting `contains` or convert — see File structure.)
- `Sources/Core/Control/AppController.swift` `pointerDown(_:modifiers:)`
  (modified): after the inactive guard, suppress drawing when over the toolbar:
  ```swift
  if let region = toolbarRegion, region.contains(point) { return }
  ```
  This guarantees no stroke/text/arrow starts under the toolbar even if an
  event leaks to the canvas window. `pointerUp`/`pointerMoved` need no guard —
  with no gesture started they are already no-ops; hover cursor is handled by
  `currentCursor`.
- `Sources/Core/Selection/SelectionRegion.swift` (modified): `cursorFor`'s
  `.outside` case returns `.crosshair` instead of `.arrow` (selection-mode
  outside-the-box means "draw a marquee"). `SystemCursor.crosshair` exists.

### AppKit: thin adapters

- `Sources/AppKit/ValuePickerControl.swift` (new): a small `NSControl`/`NSView`
  that renders the collapsed example+number and, on click, presents an
  `NSPopover` whose content is a horizontal `NSStackView` of the presets. Two
  configurations:
  - **Size:** collapsed = a filled dot whose diameter maps the current width
    (clamped to the control height) + the integer width. Popover cells = dots
    of increasing diameter.
  - **Opacity:** collapsed = a swatch filled with the current color at its alpha
    over a checkerboard (so alpha reads) + the percent. Popover cells = swatches
    of increasing alpha.
  Selecting a cell invokes a callback with the chosen `Double` and dismisses.
  Reads `ValuePresets` from Core. Keeps `ToolbarController` from ballooning.
- `Sources/AppKit/ToolbarController.swift` (modified):
  - Labels: `"stroke size"` -> `"size"`, `"stroke opacity"` -> `"opacity"`, and
    the slider tooltips drop "Stroke ".
  - Layout: rebuild the stack as a single vertical column — pen/text/arrow each
    on their own row, the 8 swatches one per row, the custom well, the size
    picker, the opacity picker, hide, fade.
  - Replace `widthSlider`/`opacitySlider` with two `ValuePickerControl`s wired
    to `controller.currentWidth` and `controller.currentColor.a`. Rework the
    `testOnly_setWidth`/`testOnly_setOpacity`/`testOnly_widthSliderValue`/
    tooltip hooks to drive/read the new controls.
  - **Persistence fix:** persist inside the existing
    `onCurrentColorChanged` / `onCurrentWidthChanged` closures (which fire on
    every canonical change, from any source), and delete the per-action
    `persistColor()` / `defaults.set(...)` calls in `colorClicked`,
    `customColorChanged`, `opacityChanged`, `widthChanged`. Loading still runs
    before the callbacks are wired, so there is no load-time echo. Verify
    `main.swift` does not clobber these callbacks; compose if it does.
  - Bump the panel's `setFrameAutosaveName` (e.g. `fiti.toolbar.v2`) so the
    stale 60x320 saved frame does not fight the new tall/narrow layout; set a
    sensible initial frame in `ToolbarPanel`.
- `Sources/AppKit/CursorRenderer.swift`: confirm `.system(.crosshair)` maps to
  `NSCursor.crosshair` (add the case if missing).
- `Sources/App/main.swift` (modified): feed the toolbar frame to the controller
  as a canvas-space `Rect`. Convert `toolbar.panel.frame` into the canvas
  view's coordinate space and assign `controller.toolbarRegion`; recompute on
  the existing toolbar screen-move notification and on canvas resize, and clear
  it when the toolbar hides (mode `.inactive`).

### Stale value cleanup

A one-time reset of the persisted color to red `#e03131` so the first launch
after this change is red without waiting for the user to repaint. Done via the
existing defaults keys (`fiti.color.{r,g,b,a}`); the persistence fix keeps it
correct thereafter.

## File structure

New:
- `Sources/Core/Model/ValuePresets.swift` (`ValuePresets`, `nextPreset`,
  `previousPreset`)
- `Sources/AppKit/ValuePickerControl.swift` (collapsed control + preset popover)

Modified:
- `Sources/Core/Control/AppController.swift` (`toolbarRegion`, pointerDown guard)
- `Sources/Core/Control/AppController+Commands.swift` (preset stepping)
- `Sources/Core/Control/AppController+SelectionGesture.swift`
  (`currentCursor` over-toolbar arrow)
- `Sources/Core/Selection/SelectionRegion.swift` (`.outside` -> `.crosshair`)
- `Sources/Core/Model/Rect.swift` (a `Point`-accepting `contains`, if needed)
- `Sources/AppKit/ToolbarController.swift` (labels, layout, pickers,
  persistence re-key, autosave bump)
- `Sources/AppKit/ToolbarPanel.swift` (initial frame for the tall layout)
- `Sources/AppKit/CursorRenderer.swift` (crosshair mapping, if missing)
- `Sources/App/main.swift` (toolbar frame -> `toolbarRegion`, updates)
- Test files for all of the above (see Testing)

## Testing

Swift Testing, suite under 5 seconds, red/green.

Core (`fiti-unit`):
- `nextPreset`/`previousPreset`: from an on-preset value, advances one index;
  from an off-preset value (e.g. 7 with sizes), goes to the next/previous
  pickable preset, not the nearest; clamps at min and max.
- `bumpSize`/`bumpOpacity` (tool-default path): stepping moves `currentWidth` /
  `currentColor.a` through `ValuePresets`, and `o`/`O` lands on exact 10%
  steps because the preset list is exact.
- `currentCursor` returns `.system(.arrow)` when `lastHoverPoint` is inside
  `toolbarRegion`, and the tool cursor (`.brush`/`.iBeam`/`.arrowhead`) when it
  is outside — for each tool.
- `pointerDown` inside `toolbarRegion` starts no stroke/text/arrow (doc
  unchanged, mode stays idle); just outside, it starts normally.
- `cursorFor(.outside, ...)` returns `.crosshair`; corners/body/rotate cursors
  unchanged.
- `Rect.contains(Point)` if added.

AppKit (`test-integration`):
- `ValuePickerControl` shows the expected number/percent for a value and snaps
  display to the right preset cell; selecting a cell invokes the callback with
  that preset.
- `ToolbarController` size/opacity hooks set `controller.currentWidth` /
  `currentColor.a`; labels read "size"/"opacity"; tooltips have no "Stroke ".
- **Persistence regression:** changing `controller.currentColor` /
  `currentWidth` *not* through a toolbar widget (i.e. directly, as the keyboard/
  menubar/HTTP paths do) writes the new value to defaults. This is the test
  that fails today and passes after the re-key.
- `CursorRenderer` maps `.system(.crosshair)` without crashing.

## Engineering principles

- Red/green TDD per task; `just check` (the pre-commit gate) green at every
  commit; never `--no-verify`.
- Hexagonal: presets, stepping, the over-toolbar cursor/suppression decision,
  the crosshair, and "persist on canonical change" are pure Core or keyed to
  Core's canonical state-change callbacks, all unit-testable. AppKit feeds the
  toolbar rect in and renders the collapsed control + popover.
- Smallest reasonable change: re-key existing persistence rather than adding a
  store; reuse the existing defaults keys, callbacks, and screen-move observer.
- Visual tuning in the running app: the exact size-preset values, the toolbar
  dimensions, and the collapsed-control sizing are tuned with the
  `inspect-screenshot` loop after the first end-to-end render.

## Risks and notes

- Persisting on every `onCurrentColorChanged` means continuous writes while a
  value is dragged via the popover/keyboard repeat. UserDefaults coalesces
  these; it is cheap and not a concern.
- The toolbar is a separate floating window above the canvas, so real button
  clicks already hit the toolbar, not the canvas. The Core `pointerDown` guard
  is belt-and-suspenders for leaked events; the everyday win is the arrow
  cursor (and no lingering tool cursor) over the toolbar via `currentCursor`.
- Mapping the toolbar frame to canvas coordinates must track toolbar drags
  between screens (the existing screen-move observer) and canvas resizes; a
  stale rect would arrow-ize the wrong region. Clear it when inactive.
- Changing the panel autosave name discards the user's saved toolbar position
  once. Acceptable for a layout this different; it re-saves immediately.
- Selection-mutation size/opacity shortcuts intentionally keep their current
  behavior; only the tool-default `s`/`o` path becomes preset-stepped. Called
  out so the asymmetry is deliberate, not a bug.
