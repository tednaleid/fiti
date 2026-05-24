# fiti Arrow Tool Design

Date: 2026-05-24
Status: Design approved in principle, written up for review.

## Problem

fiti has pen, selection, and text tools but no way to place a clean directional
arrow. Annotation work (pointing at a thing, showing flow) needs a straight
arrow with a head at the end. The roadmap reserves `a` for this and specifies an
`ArrowItem` as a new `CanvasItem` case rather than a `Stroke` variant.

## Goals

- A dedicated arrow tool: press at the tail, drag, release at the head. The
  arrow is straight from the first move and rubber-bands its head to the cursor.
- The head sits at the end (the lift point), never the start.
- Single head, solid and filled, with the rounded swept look chosen in the
  visual mockups, on a subtly tapered shaft.
- Head size scales with the stroke-width slider.
- The arrow is a first-class `CanvasItem`, so selection, move/rotate/resize, the
  color/size/opacity restyle shortcuts, undo, and erase all work without
  per-tool code.
- WYSIWYG: the in-progress arrow flattens live with its same-color neighbors and
  is pixel-identical to the committed result, using the same opacity-flattening
  engine the pen already uses.

## Non-goals

- Pen-to-arrow shape detection (drawing a line with a hand-drawn head and having
  it convert). Deferred to a later spec, as the roadmap notes. This design is the
  `ArrowItem` primitive that detection would later target.
- Double-headed arrows. Single head only for v1. A future toggle or modifier can
  add a tail head later; the data model leaves room (see Data model).
- Angle snapping. The arrow follows the cursor exactly; no Shift-constrained
  0/45/90 angles in v1.
- Curved arrows. Straight only.
- Hold-to-straighten. The dedicated tool is straight immediately, so the pen's
  hold gesture is not involved. (Detection, if built later, would start freehand
  and straighten; that is the deferred path.)

## Interaction

Routed through the existing `currentTool` switch in `AppController`'s three
pointer handlers, parallel to pen/selection/text:

- `pointerDown(tail)`: record the tail; create an in-progress draft `ArrowItem`
  with `tail == head` (a degenerate zero-length arrow, not yet drawn).
- `pointerMoved(p)`: set the draft's `head = p`. The draft is surfaced to the
  renderer every frame and drawn live (see Live WYSIWYG). Below a small minimum
  length the head is not yet rendered, matching how a zero-length drag produces
  nothing.
- `pointerUp`: if the arrow meets the minimum length, commit it with
  `editor.addItem(.arrow(final))` (one undoable op) and clear the draft;
  otherwise discard the draft (no-op, nothing committed).

Color, width, and opacity come from the current drawing defaults, the same
source the pen reads.

## Visual specification

The look chosen in the mockups: medium-sweep filled head with rounded corners on
a subtly tapered shaft. All dimensions derive from the stroke width `w` so the
arrow scales with the width slider. These constants live in one place and are
tuned to match the approved mockup; the numbers below are the starting point.

- Shaft taper: half-width `0.275 * w` at the tail, growing linearly to `0.5 * w`
  at the head base (the shaft reaches full stroke width where it meets the head).
- Head length along the shaft: `~4.5 * w`.
- Barb half-span (perpendicular reach of each barb from the shaft axis):
  `~2.6 * w`.
- Sweep: the back inner vertex sits forward of the barb tips by about `25%` of
  the head length, giving the shallow concave notch (the "medium sweep").
- Corner rounding: a render-time cosmetic via CoreGraphics round line joins, not
  part of the stored geometry.

A minimum drawable length (a small multiple of `w`, enough that the head is not
larger than the shaft) gates both the live render and the commit.

## Data model

A new value type, frozen at commit like `Stroke`:

```swift
public struct ArrowItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var color: RGBA
    public var width: Double
    public var transform: Transform
    public var tail: Point        // local coords, frozen at commit
    public var head: Point        // local coords, frozen at commit
    public let createdAt: Double  // seconds since epoch
}
```

`CanvasItem` gains a `.arrow(ArrowItem)` case and the matching arms for `id`,
`createdAt`, `color`, `transform` get/set, and `withColor`. `tail`/`head` are
the geometry; later edits ride on `transform` (uniform scale and rotation), so a
resized or rotated arrow keeps its proportions and the head scales with it.

Single-headed is expressed by drawing a head only at `head`. A future
double-headed option would add one flag and a second head at `tail` without
changing the stored endpoints.

## Pure geometry (Core)

A pure function (no AppKit/CoreGraphics) builds the arrow outline so Core stays
the source of truth for shape, bounds, and hit-testing:

```swift
// Sources/Core/Rendering/ArrowGeometry.swift
// Returns the arrow as one merged outline polygon (tapered shaft + swept head)
// in the item's local space, given endpoints and width.
public func arrowOutline(tail: Point, head: Point, width: Double) -> [Point]
```

One merged polygon (not separate shaft and head shapes) means the shaft/head
seam is interior to a single filled region, so it never double-darkens, and the
hit-test is a single point-in-polygon check.

Two consumers share this function:

- `SelectionMath`: a `.arrow` branch computes the world AABB from the transformed
  outline and hit-tests with point-in-polygon. Exact and cheap from the
  endpoints; no `TextMeasuring`-style port needed (unlike text).
- The AppKit renderer: turns the outline into a `CGPath`.

The stored/queried outline is the sharp polygon. The rendered corners are
rounded by CoreGraphics, which slightly over-covers relative to the sharp
polygon, so AABB and hit-test err toward including the rounded ink, never
excluding it.

## Rendering and flattening

A new `Sources/AppKit/ArrowDrawing.swift` builds the `CGPath` from
`arrowOutline` and fills it with round line joins for the rounded corners. It
exposes the same opaque-versus-alpha shape the stroke and text drawers use, so
it slots into both the live per-item draw path and the opaque-union flatten
path.

The arrow participates in the existing `(hue, alpha)` opacity flattening with no
new grouping logic, because grouping is keyed on color and operates on
`CanvasItem`s generically (`LayerPlan`, pure Core):

- `GroupCompositor` gains a `.arrow` branch in its opaque-draw step (fill the
  outline at alpha 1 inside the group's transparency layer) and includes the
  arrow's AABB in the per-group clip. Overlapping same-color arrows and strokes
  then read as one flat region, identical to strokes today.
- The committed bake and `SnapshotRenderer` pick arrows up automatically, since
  both already iterate `CanvasItem`s through `GroupCompositor`.

## Live WYSIWYG

The in-progress arrow flattens live through the same machinery the pen stroke
uses, so what is drawn is pixel-identical to what commits. The per-frame cost is
the same fixed shape as the pen (one cached-union blit plus one opaque fill of
the in-progress item, bounded to the active group's clip, independent of mark
count); the arrow's merged polygon is a cheaper fill than a perfect-freehand
outline.

The one structural change is generalizing the in-progress render slot, which is
typed for a pen stroke today:

- `RenderFrame.inProgress: Stroke?` becomes able to carry an in-progress arrow as
  well. Either a parallel `inProgressArrow: ArrowItem?` field or a single
  `inProgressItem: CanvasItem?`; the implementation plan picks the smaller diff
  against the existing live-group code. The active group's `(hue, alpha)` key is
  read from the in-progress item's color generically, which already works for an
  arrow.
- The live-group per-frame "draw the in-progress item opaque" dispatches on item
  type (stroke vs arrow). The arrow branch reuses `ArrowDrawing`'s opaque path,
  the same one the committed bake uses. The below/above bake split and the
  cached opaque-union are unchanged; an arrow is just another member of its
  `(hue, alpha)` group.

At pen-up the draft commits, the lifted set empties, and the static bake rebuilds
with the new arrow, exactly as for a pen stroke.

## Integration points

- `Sources/Core/Model/Tool.swift`: add `.arrow`.
- `Sources/Core/Control/KeyCommand.swift`: bind `KeyBinding(character: "a")` to
  `.selectTool(.arrow)`.
- `Sources/Core/Control/AppController.swift`: route `.arrow` in the three pointer
  switches to the new arrow handler.
- `Sources/Core/Control/AppController+ArrowTool.swift` (create): `arrowPointerDown`
  / `arrowPointerMoved` / `arrowPointerUp`, holding the in-progress draft.
- `Sources/AppKit/ToolbarController.swift`: an arrow toolbar button beside pen
  and text, indicating the active tool the same way the others do.
- `Sources/AppKit/CursorRenderer.swift`: an arrow-tool cursor.
- `Sources/AppKit/KeyMonitor.swift`: no change; `selectTool(.arrow)` dispatches
  through the existing registry path.

## Files

Create:

- `Sources/Core/Model/ArrowItem.swift`
- `Sources/Core/Rendering/ArrowGeometry.swift`
- `Sources/Core/Control/AppController+ArrowTool.swift`
- `Sources/AppKit/ArrowDrawing.swift`

Modify:

- `Sources/Core/Model/CanvasItem.swift` (add `.arrow` case and arms)
- `Sources/Core/Model/Tool.swift` (add `.arrow`)
- `Sources/Core/Control/KeyCommand.swift` (bind `a`)
- `Sources/Core/Control/AppController.swift` (route `.arrow`)
- `Sources/Core/Ports/RenderFrame.swift` (carry the in-progress arrow)
- `Sources/Core/Editor/RenderFrame+from.swift` (surface the draft)
- `Sources/Core/Selection/SelectionMath.swift` (`.arrow` AABB + hit-test)
- `Sources/AppKit/GroupCompositor.swift` (`.arrow` opaque-draw + clip)
- `Sources/AppKit/CanvasView.swift` (live `.arrow` draw + in-progress slot)
- `Sources/AppKit/SnapshotRenderer.swift` (only if it does not already flow
  arrows through `GroupCompositor` for free)
- `Sources/AppKit/ToolbarController.swift`, `Sources/AppKit/CursorRenderer.swift`

## Testing

Core (pure, fast):

- `ArrowGeometry`: outline for an axis-aligned arrow (horizontal, vertical) and a
  diagonal; head dimensions scale linearly with width; the tail is narrower than
  the head base (taper); the outline is a single closed polygon.
- `SelectionMath`: arrow AABB matches the transformed outline; hit-test is true
  inside the shaft and head and false just outside; rotated/scaled arrow bounds
  follow the transform.
- `KeyCommandRegistry`: `a` resolves to `.selectTool(.arrow)`.
- `AppController` arrow gesture: down/move/up commits exactly one `.arrow` item,
  undoable in one step; the draft head tracks moves; a sub-minimum-length drag
  commits nothing.

AppKit (pixel-sample on the offscreen bake, following `CanvasViewBakeTests`):

- A single arrow fills its outline in the current color; the shaft/head seam
  shows no internal darkening (single merged path).
- Two overlapping same-color arrows read flat at the overlap (not darker), same
  as overlapping strokes.
- A same-color arrow crossing a same-color stroke flattens together.
- A different-color mark over the arrow preserves z-order.
- WYSIWYG: an in-progress arrow rendered via the live path over a committed
  same-color mark matches the same two items both committed via the bake at the
  intersection pixel.

Performance (the perf probe, against `docs/perf-baseline.md`):

- The live per-frame composite while dragging an arrow stays sub-millisecond and
  flat in committed-mark count, matching the pen-stroke live path.

The full suite must stay under 5 seconds; `just check` is the gate.

## Known limitations

- AABB-based per-group clipping and overlap are conservative, identical to the
  stroke behavior: a bounding box that touches but whose filled shape does not
  may add an ordering constraint. Errs toward slightly more darkening, never
  wrong z-order. Same as the opacity-flattening design.
- The cross-hue-conflict darkening from the opacity-flattening design applies to
  arrows too (a same-color mark that crosses a different color and also overlaps
  an earlier same-color mark on the far side, in draw order). Inherited, not new.
