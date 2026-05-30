# fiti Size / Opacity Visual Popover

Date: 2026-05-29
Status: Design approved 2026-05-29.

## Problem

The toolbar's size and opacity controls are stepper rows (`− size +`,
`− opacity +`) wrapped around a live preview rectangle. To change a value the
user has to either tap a stepper button repeatedly to walk through presets or
reach for the keyboard. There is no way to see what the other nine presets look
like before committing, and the stepper rows take vertical space that could
carry more direct affordances.

An older `ValuePickerControl` once provided a vertical popover of preset cells
but was hand-rolled (its own glyph drawing, not the real render pipeline), and
it was replaced by the current stepper-around-preview layout.

Now that the toolbar already renders a single live preview through the real
`SnapshotRenderer` pipeline — pen wave / arrow / text "A" in the current color
and width, with the per-tool outline applied — we can reuse that exact render
for every preset cell. The result is a horizontal popover of ten cells that
each look like the actual mark the user would make.

## Goals

- Replace the size and opacity stepper rows with a single SF-Symbol button
  each, matching the size of the tool and color buttons.
- Clicking either button opens a horizontal popover of ten cells, one per
  preset, anchored flush with the in-toolbar live preview's top and bottom
  edges.
- Each cell renders through the same `SnapshotRenderer` call shape the
  in-toolbar preview already uses (same canvas size, same per-tool item, same
  outline rules) with one preset value substituted on the popover's axis.
- The size popover varies width and holds the current color (including current
  opacity) constant. The opacity popover varies alpha and holds the current
  width and RGB constant. Each cell is a literal preview of what choosing it
  would produce.
- The popover extends to the right when the toolbar is on the left half of its
  screen and mirrors to the left when on the right half.
- The cell matching the current value (exact match) gets the accent ring used
  by the active tool and active swatch.
- Click commits the value and closes the popover. Outside-click, ESC, re-click
  of the trigger, and click of the other trigger all dismiss.
- The live preview rectangle in the toolbar stays put.

## Non-goals

- Hover-to-preview. Cells render the literal target; the toolbar's live preview
  does not track the hovered cell. Commit is click-only.
- Animation. Popover appears and disappears instantly.
- New keyboard shortcuts. `s`/`S` and `o`/`O` keep silently stepping presets
  via the existing path; they do not open the popover.
- New persisted state. `currentWidth` and `currentColor` already persist; the
  popover is chrome over the existing setters.
- New HTTP routes. `/currentWidth` and `/currentColor` already cover this.
- Changing the preset arrays themselves. `ValuePresets.sizes` and
  `.opacities` are unchanged.
- A draggable popover, a search field, custom presets, or any way to author
  values that are not on the preset list. The color panel still covers
  off-preset alpha; HTTP still covers any value.

## Decisions (from brainstorming)

- **Buttons show icons, not values or mini-previews.** The live preview already
  renders the current mark; encoding it again on a 28×28 button is redundant.
  SF Symbols: `lineweight` for size, `drop` for opacity. Matches the tool
  buttons' icon-only style.
- **Popover is a custom borderless `NSPanel`, not `NSPopover`.** The screenshot
  has no arrow; edge mirroring needs full control over positioning. The
  existing toolbar already uses a non-activating `NSPanel`, so this is the same
  pattern.
- **Cells are 60×140**, the same dimensions as the in-toolbar live preview
  rectangle. They use the same `SnapshotRenderer` call shape, with the preset
  substituted on the axis. Cell spacing matches the swatch column spacing.
- **Popover anchors vertically to the live preview, not to the trigger
  button.** Both the size and opacity popovers occupy the same vertical band,
  flush with the preview's top and bottom. That way the popover looks like an
  extension of the preview rather than dropping above or below it.
- **Selected cell highlight is the existing accent ring.** Reuses
  `setActiveBackground` style to stay consistent with active tool / swatch.
- **Hover effect is a subtle background tint** so the selected highlight stays
  visually dominant. Hover never displaces the "currently picked" indicator.
- **Click commits and closes.** Standard menu behavior; matches the swatch
  buttons today.
- **Four dismissal paths.** Outside-click (global mouse monitor), ESC (local
  key monitor), re-click the same trigger (toggle), click the other trigger
  (close + reopen on the other axis).
- **Keyboard untouched.** `s`/`S`/`o`/`O` keep stepping presets through
  `AppController` writes, the popover does not open from the keyboard.
- **Pure preset axis logic lives in Core.** A new `PresetAxis` enum holds the
  values list, the display string formatting, and the current-value-to-index
  match. AppKit consumes it — no `switch axis` blocks in the popover.

## Architecture

### Core

`Sources/Core/Model/PresetAxis.swift` — new pure enum:

```swift
public enum PresetAxis {
    case size
    case opacity

    public var values: [Double] { /* ValuePresets.sizes or .opacities */ }
    public func displayString(for value: Double) -> String  // "14" or "70%"
    public func selectedIndex(for value: Double) -> Int?    // exact match or nil
}
```

`ValuePresets` stays where it is; `PresetAxis` reads from it. No other Core
changes.

### AppKit

`Sources/AppKit/MarkPreview.swift` — new view, lifted from the rendering logic
currently inside `MarkControl`:

- 60×140 `NSImageView` wrapper.
- Properties `color: RGBA`, `width: Double`, `currentTool: Tool`,
  `outlineOn: Bool`. Setters trigger re-render.
- Internal `renderPreview()` invokes
  `SnapshotRenderer.image(from: RenderFrame(items: [previewItem()],
  inProgress: nil, canvasSize: Size(width: 60, height: 140)), scale: 2,
  outline: flags)`.
- Per-tool `previewItem()` builds a centered pen wave / arrow / text "A" — the
  same construction `MarkControl` does today.
- No interaction logic; no buttons; no popover knowledge.

`Sources/AppKit/PresetButton.swift` — small factory or thin subclass:

- A `FirstMouseButton` configured at 28×28 with an SF Symbol image,
  `bezelStyle = .regularSquare`, `imagePosition = .imageOnly`, and a tooltip.
- Two instances live in `MarkControl`: the size button with `lineweight`, the
  opacity button with `drop`.
- Active background highlight follows whether its axis's popover is currently
  open (driven by `ToolbarController`).

`Sources/AppKit/PresetPopover.swift` — the new behavior, isolated:

- Owns a borderless, non-activating `NSPanel` (level above the toolbar panel
  so it sits over the canvas) plus a `NSStackView` of cell `NSButton`s.
- Public surface:

  ```swift
  func open(axis: PresetAxis,
            currentValue: Double,
            color: RGBA,
            width: Double,
            tool: Tool,
            outlineOn: Bool,
            anchor: NSRect,         // screen-space rect of the live preview
            edge: NSRectEdge,       // .maxX (popover right of anchor) or .minX
            onPick: @escaping (Double) -> Void)
  func close()
  var isOpen: Bool { get }
  var currentAxis: PresetAxis? { get }
  ```

- On `open(...)` the panel:
  1. Builds N cells (`NSImageView` inside an `NSButton`). Each cell's image is
     `SnapshotRenderer.image(...)` with the same canvas size as `MarkPreview`,
     with the axis value swapped on the relevant property (size axis: cell uses
     preset width + caller's `color` and `outlineOn`; opacity axis: cell uses
     caller's `width` with `color` alpha replaced by the preset).
  2. Highlights the cell at `axis.selectedIndex(for: currentValue)` with the
     accent background. No highlight if `nil`.
  3. Positions itself so the panel's vertical extents match `anchor.top` and
     `anchor.bottom`, with a small horizontal offset on the chosen edge.
  4. Installs three monitors and observers:
     - Local `keyDown` monitor: ESC → `close()`, swallow.
     - Global `leftMouseDown` monitor: any outside-app click → `close()`.
     - `NSApplication.didResignActiveNotification` observer → `close()`.
- `close()` removes the monitors and observer, orders the panel out, and clears
  `currentAxis`. Idempotent.
- Click on a cell calls `onPick(presetValue)` then `close()`.

`Sources/AppKit/MarkControl.swift` — shrinks:

- Vertical stack: size `PresetButton`, `MarkPreview`, opacity `PresetButton`.
- Exposes `onOpenPopover: ((PresetAxis, NSRect) -> Void)?` where the rect is
  the `MarkPreview`'s frame in screen coordinates.
- Drops `sizeMinus`, `sizePlus`, `opacityMinus`, `opacityPlus`, all stepper
  actions, and the four `testOnly_tap*` shims. Keyboard shortcuts already write
  directly to `AppController`; they do not go through `MarkControl`.

`Sources/AppKit/ToolbarController.swift` — holds one `PresetPopover` instance.
Implements `markControl.onOpenPopover`:

1. Read `popover.currentAxis` and `popover.isOpen`.
2. If open with the same axis → `popover.close()`, return.
3. If open with the other axis → `popover.close()`; fall through to open.
4. Compute the edge: convert the toolbar window's frame to screen coords; if
   the toolbar's center.x is in the left half of `window.screen`, use `.maxX`
   (popover extends right of the anchor). Else `.minX`.
5. Call `popover.open(...)` with the current `color`, `width`, `currentTool`,
   `outlineOn`, the anchor rect, and an `onPick` closure that writes through:

   ```swift
   onPick: { [weak self] v in
       guard let self else { return }
       switch axis {
       case .size:    self.controller.currentWidth = v
       case .opacity:
           let c = self.controller.currentColor
           self.controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: v)
       }
   }
   ```

   The existing `onCurrentWidthChanged` / `onCurrentColorChanged` propagate the
   change back into `MarkPreview` and `UserDefaults`. Persistence is unchanged.

6. After opening, set the active highlight on the matching trigger button.
   On `close()`, clear it.

Also: subscribe to `controller.onCurrentToolChanged` and close the popover when
the tool changes — cells captured the tool at open time and would otherwise be
showing the wrong mark.

### Files

Added:

- `Sources/Core/Model/PresetAxis.swift`
- `Sources/AppKit/MarkPreview.swift`
- `Sources/AppKit/PresetButton.swift`
- `Sources/AppKit/PresetPopover.swift`
- `Tests/CoreTests/PresetAxisTests.swift`
- `Tests/AppKitTests/MarkPreviewTests.swift`
- `Tests/AppKitTests/PresetPopoverTests.swift`

Modified:

- `Sources/AppKit/MarkControl.swift`
- `Sources/AppKit/ToolbarController.swift`
- `Tests/AppKitTests/MarkControlTests.swift`
- `Tests/AppKitTests/ToolbarControllerTests.swift`

Removed: nothing on disk; existing files shrink.

## Data flow

### Opening

1. User clicks a `PresetButton`. The `MarkControl` action calls
   `onOpenPopover(axis, previewRectInScreenCoords)`.
2. `ToolbarController` toggles, swaps, or opens per the rules above.
3. `PresetPopover.open(...)` builds the cells, positions the panel, installs
   monitors, orders front.

### Picking

1. Cell `NSButton` action fires `onPick(axis.values[index])`.
2. `ToolbarController`'s pick closure writes `currentWidth` or
   `currentColor.a` on `AppController`.
3. `controller.onCurrentWidthChanged` / `onCurrentColorChanged` propagate back
   into the `MarkPreview` (refreshes the live preview) and persistence.
4. `PresetPopover.close()` runs immediately after the pick callback.

### Dismissal

- **Cell click** → pick → close.
- **Outside click** → global `leftMouseDown` monitor → close.
- **ESC** → local `keyDown` monitor → close (swallowed).
- **Re-click trigger** → handled in `ToolbarController.onOpenPopover` via the
  same-axis-open branch → close.
- **Click other trigger** → handled in the other-axis-open branch → close + open
  the other axis.
- **App deactivation** → `didResignActiveNotification` → close.
- **Tool change** → `onCurrentToolChanged` → close.

All paths converge on `PresetPopover.close()`, which is idempotent.

## Edge cases

- **Off-preset current value.** HTTP, the macOS color panel, or any other
  source can set values not on the preset list. `axis.selectedIndex(for:)`
  returns `nil`; no cell is highlighted; picking commits a preset value.
- **Re-entrant open while opening.** `open(...)` checks `isOpen` first and
  no-ops if already open.
- **Toolbar drag while popover is open.** The next mouse-down inside the title
  bar is outside the popover; the global monitor closes it. We do not live-
  reposition.
- **Outline setting changes while popover is open.** Outline is captured at
  open time; the cells continue to show what they were built with. Since
  outline shortcuts are rare during a picking interaction and the popover
  closes on most input, this is acceptable; we do not subscribe to outline
  changes.
- **Selection tool active.** The in-toolbar preview already retains the prior
  drawing tool when `.selection` is active. The popover does the same — when
  opening, if `controller.currentTool == .selection`, fall back to
  `MarkPreview`'s retained `previewTool` so the cells show the user's last
  drawing tool, not blanks.

## Testing

Swift Testing throughout. Full suite stays under five seconds.

### Pure Core

`Tests/CoreTests/PresetAxisTests.swift`:

- `values` returns the ten elements from `ValuePresets` for each axis.
- `displayString(for:)` formats: size → integer string (`"14"`), opacity →
  percent string (`"70%"`, `"100%"`).
- `selectedIndex(for:)` returns the index for an exact preset match and `nil`
  for an off-preset value.

### AppKit, `@MainActor`

`Tests/AppKitTests/MarkPreviewTests.swift`:

- Setting `width`, `color`, `currentTool`, `outlineOn` produces a non-nil
  snapshot (covers all three drawing tools).
- Setting `currentTool = .selection` keeps the previously-set tool's snapshot
  (matches existing `MarkControl` behavior).

`Tests/AppKitTests/PresetPopoverTests.swift`:

- `open(axis: .size, ...)` builds ten cells; cell at `selectedIndex` has the
  active background and others do not.
- Clicking cell N fires the `onPick` closure with `axis.values[N]` and closes.
- `close()` is idempotent.
- An ESC `NSEvent` delivered to the local monitor closes the popover.
- A simulated `didResignActiveNotification` closes the popover.
- Event monitors are removed after close — verified through a
  `testOnly_monitorCount` counter to catch leaks across open/close cycles.

`Tests/AppKitTests/MarkControlTests.swift` (rewrite):

- Drops every assertion about stepper buttons (`testOnly_tapSize*` /
  `*MinusEnabled` / `*PlusEnabled`).
- Adds: clicking the size `PresetButton` calls `onOpenPopover(.size,
  previewRectInScreenCoords)`. Same for opacity → `.opacity`.
- The preview rect passed matches `MarkPreview`'s on-screen frame.

`Tests/AppKitTests/ToolbarControllerTests.swift` (adjustments):

- Replace assertions about stepper tooltips and labels with assertions about
  the size and opacity `PresetButton` tooltips and accessibility labels.
- New: clicking the size button opens the popover with `axis == .size`. The
  pick callback writes through to `controller.currentWidth`.
- Toggle: re-clicking the size button while open closes the popover.
- Swap: clicking opacity while size is open closes size and opens opacity.
- Tool change: changing `controller.currentTool` while the popover is open
  closes it.

### Out of scope for tests

- Click-outside via the global mouse monitor — synthesising a global event in
  the test runtime is not reliable. The dismissal hook is exercised in the
  `close()` and ESC tests, which is enough to verify the close machinery.
- Edge-mirroring math by toolbar position — covered indirectly by a small unit
  test on the pure helper that picks the edge from a toolbar rect and a screen
  rect; the test does not require a real window.

## Migration

- The four `testOnly_tap*` shims and the four `*Enabled` checks on `MarkControl`
  go away. The corresponding `ToolbarController` shims
  (`testOnly_tapSizeUp` / `testOnly_tapOpacityUp`) are removed since no caller
  needs them — keyboard tests already write through `AppController`.
- No public-API change on `AppController`.
- No persistence migration.

## Risks

- **Borderless panel lifecycle.** The prior `ValuePickerControl` had popover
  lifecycle bugs (commit `7da5e6b AppKit: ValuePickerControl popover lifecycle
  hardening`). We mitigate by: idempotent `close()`, monitor-removal in a
  single `close()` path, an explicit `didResignActiveNotification` observer,
  and a `testOnly_monitorCount` invariant in tests.
- **Render cost.** Ten `SnapshotRenderer.image(...)` calls per open. The
  existing live preview does one such call on every state change without
  perceptible lag, so ten on a single open is fine. We do not cache cell
  images across opens; each open rebuilds with current color/outline/tool.
