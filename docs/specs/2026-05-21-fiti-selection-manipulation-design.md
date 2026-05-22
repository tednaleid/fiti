# fiti Selection Manipulation Design

Date: 2026-05-21
Status: Design — not yet implemented.

## Goal

Make the selection tool fully manipulable: grab a selection (single or multi) by its body and translate it, scale it uniformly from the corners, and rotate it around its center — with hover cursors that tell you what each region does. This finishes the resize/rotate work deferred from the original selection tool (`2026-05-20-fiti-selection-tool-design.md`, sub-task 5b) and fixes the multi-select drag bug, while reworking the interaction model around region-first hit-testing and a transient (Space-held) lifetime.

## Context: what exists today

The selection tool shipped with click-to-select, Cmd-click toggle, marquee, and drag-translate (commits `65f94501`…`f7d446d`). Resize and rotate were deferred. The current `selectionPointerDown` hit-tests individual strokes only and **always replaces** the selection on a plain click — so clicking a member of a multi-selection collapses it to that one stroke (the reported bug). Selection is currently *sticky* (persists after Space release). The selection box is an axis-aligned `Rect`. The cursor under the selection tool is the plain system arrow.

The live-overlay rendering refactor (`f7d446d`) already draws in-flight (dragged) strokes on the live layer with their override transforms; this design reuses that path for all three gestures.

## Decisions locked (from brainstorm)

1. **Transient lifetime.** A selection exists only while Space is held. Releasing Space clears it and returns to pen. All manipulation happens during the hold.
2. **Cmd = edit the selection set.** Without Cmd, gestures manipulate what's selected. With Cmd, clicks and marquees change *which* strokes are selected (toggle).
3. **Corners-only resize**, uniform scale, anchored at the diagonally-opposite corner. No edge handles (the `Transform` model is uniform-scale-only).
4. **Oriented selection box (persistent).** The box rotates with the content and stays snug; it persists at its rotated angle for the life of the selection (no snap-back).
5. **Native diagonal cursors** via private `NSCursor` selectors (with fallback), a programmatically-drawn rotate cursor, and the public open/closed hand for the body. Corner cursor is chosen by the corner's **screen-space angle** (bucketed into the four available cursors) so it stays correct on a rotated box.

## Interaction model

### Lifetime

| Trigger | Effect |
| --- | --- |
| `Space` keyDown (not autorepeat), fiti active | `currentTool = .selection`; selection starts empty |
| `Space` keyUp, no gesture in flight | `currentTool = .pen`; selection state cleared entirely |
| `Space` keyUp **during** a pointer gesture (button down) | defer the revert+clear; apply it on the following `pointerUp` so the drag isn't yanked out |
| `Esc` | deactivate fiti — its plain meaning, unchanged. No selection-specific handling: to clear a selection you just release Space. |
| `Delete` (Space held) with a selection | erase only the selected strokes (one undoable op) |
| `Delete` (Space held) with no selection | **no-op** — you "missed"; nothing destructive happens while in selection mode |

This removes the selection-aware `Esc` branch that shipped in the original selection tool (Task 8 made `main.swift`'s `onDeactivate` clear the selection before deactivating). That handler reverts to a plain `controller.deactivate()`.

"Cleared entirely" means `selectedStrokeIds = []`, `selectionBox = nil`, `inFlightTransforms = [:]`, `marqueeRect = nil`, gesture state reset.

### Region-first pointerDown classification

While `currentTool == .selection`, a **no-Cmd** `pointerDown` resolves against the current selection in this precedence order:

1. On the **rotate node** (within hit-radius of the node center) → begin **rotate**.
2. On a **corner handle** (within hit-radius of a corner) → begin **resize** (anchor = diagonally-opposite corner).
3. Inside the **selection box** (on a stroke or its empty interior) → begin **translate** of the whole selection.
4. Outside the box, **on a stroke** (`hitTest`) → replace selection with that stroke, begin translate.
5. Outside the box, **empty** → begin **marquee** (replaces selection on release).

Rule 3 fixes the multi-drag bug: any click inside the box grabs the entire group. Region classification (rules 1–3) reads the **oriented** box, so handle/node/body tests work at any rotation (see "Oriented box").

### Cmd: editing the selection set

Cmd is a modifier *layered on top of the held Space* — there is no selection tool, and therefore no selection editing, unless Space is down. So every interaction here is really **Space+Cmd**. With Cmd also held, handles go inactive and every gesture toggles membership instead of manipulating:

- **Space+Cmd+click a stroke** → toggle that stroke in/out of the selection. No drag.
- **Space+Cmd+drag (anywhere)** → a marquee that, on release, toggles each stroke whose AABB it intersects (members are removed, non-members added). Symmetric with the Cmd-click.

Because Space is the precondition for the tool, `pointerDown(_:modifiers:)` only consults `modifiers.command` while `currentTool == .selection`; in pen mode the Cmd flag is ignored by the selection logic entirely.

### Delete / Clear

`Delete` (the `KeyCommandRegistry` `.clear` binding → `run(.clear)`) becomes **tool-gated** so Space-held is a true mode where Delete can never nuke the whole drawing:

- `currentTool == .selection` (Space held): if a selection exists, erase only those strokes (one undoable op) and clear the selection; if nothing is selected, **no-op**.
- `currentTool == .pen` (Space not held): clear all strokes (the existing destructive behavior).

`Cmd+K` is unaffected — it routes through `clear()` directly and always wipes everything, regardless of tool. This refines the shipped `run(.clear)`, which cleared-all whenever the selection was empty; under the transient lifetime the empty-selection case only happens in pen mode anyway, but gating on `currentTool` makes the "missed click in selection mode is harmless" guarantee explicit.

## Oriented selection box

An oriented box cannot be re-derived from the strokes each frame — once strokes rotate, their AABB is axis-aligned and the group's orientation is lost (and a mixed-direction multi-select has no single orientation to recover). So the selection carries session state:

```swift
// Sources/Core/Selection/OrientedBox.swift  (pure value)
public struct OrientedBox: Equatable, Sendable {
    public var center: Point        // world coords
    public var size: Size           // width/height in the box's local (unrotated) frame
    public var rotation: Double     // degrees; 0 when a selection is first formed

    public func corners() -> [Point]              // 4 world-space corners, rotation applied
    public func rotateNode(offset: Double) -> Point  // node center, above the local top edge, rotated
    public func toLocal(_ p: Point) -> Point      // world → box-local (translate by -center, rotate by -rotation)
}
```

`Point` is a small 2D value (`x`, `y`); introduce it if Core lacks one (`Rect`/`Size` already exist). `OrientedBox` lives in `Sources/Core/Selection/`.

**Lifecycle.** When `selectedStrokeIds` changes, recompute `selectionBox` from the selected strokes' transformed-points AABB with `rotation = 0`. Each gesture is computed by a single pure function that takes the gesture-start snapshot plus the pointer and returns *both* the updated `OrientedBox` and the updated per-stroke transforms from one delta — the box is never updated independently of the strokes, so they cannot drift. The box persists at its accumulated rotation for the life of the selection.

`SelectionMath.selectionBounds` (existing, returns an axis-aligned `Rect`) is still used to build the initial box (center = rect center, size = rect size, rotation = 0).

## Region classification & cursors

One pure function classifies a point and is the single source of truth for both the cursor and the pointerDown gesture:

```swift
public enum Corner: Equatable, Sendable { case topLeft, topRight, bottomRight, bottomLeft }
public enum SelectionRegion: Equatable, Sendable {
    case rotateHandle
    case corner(Corner)
    case body
    case outside
}

extension SelectionMath {
    public static func region(at point: Point, box: OrientedBox?,
                              handleRadius: Double, rotateNodeOffset: Double) -> SelectionRegion
}
```

`region` transforms `point` into box-local space via `box.toLocal`, then tests (in local, axis-aligned coords): rotate node first, then corners, then interior, else outside. A `nil` box → `.outside`.

### Cursor model

The existing cursor abstraction grows from "brush-or-nil" into an enum so Core expresses cursor *intent* and the adapter picks the platform cursor:

```swift
public enum SystemCursor: Equatable, Sendable {
    case arrow, openHand, closedHand
    case resize(angle: Double)   // screen-space angle in {0, 45, 90, 135}; adapter maps to a platform cursor
    case rotate
}
public enum CursorSpec: Equatable, Sendable {
    case brush(color: RGBA, diameter: Double)   // pen — today's behavior
    case system(SystemCursor)
}
```

Core never names a platform cursor: `.resize(angle:)` carries the already-computed screen-space angle, and "which of the four NSCursors is closest" is the adapter's concern. `CursorSpec` is `Sources/Core/Model/CursorSpec.swift` (a struct today — refactor to this enum). `AppController.currentCursor` stays **optional** (`CursorSpec?`): `nil` keeps the current "no managed cursor" meaning for `.inactive`; `.some(.brush(...))` is the pen; `.some(.system(...))` is the selection-tool cursor for the hovered region.

**Cursor policy** — a pure free function co-located with `SelectionRegion`, unit-tested without drawing:

```swift
public func cursorFor(region: SelectionRegion, boxRotation: Double, dragging: Bool) -> SystemCursor
```

- `.rotateHandle` → `.rotate`
- `.body` → `.openHand`, or `.closedHand` when `dragging`
- `.outside` → `.arrow`
- `.corner(c)` → `.resize(angle:)`, where the angle is the corner's outward diagonal in box-local coords (`topLeft`/`bottomRight` ⇒ 135°, `topRight`/`bottomLeft` ⇒ 45°) plus `boxRotation`, bucketed (mod 180°) to the nearest of {0, 45, 90, 135}. An unrotated box yields the familiar diagonal; the cursor tracks the box as it rotates.

During an active gesture the cursor is fixed for the gesture's duration (translate → `.closedHand`, resize → the corner's `.resize(angle:)`, rotate → `.rotate`).

**Geometry constants** (match/extend today's chrome): corner handles draw 6×6pt; the rotate node is a 6pt-radius circle 20pt above the top edge. Hit-radii are slightly larger than the visuals for easier grabbing — corner `handleRadius ≈ 8pt`, rotate-node radius ≈ 10pt (`rotateNodeOffset = 20`).

**AppKit mapping (thin, `CursorRenderer`):** `SystemCursor → NSCursor`. `arrow`/`openHand`/`closedHand` from public API; `.rotate` from a curved-arrow `NSImage` drawn programmatically (no bundled asset); `.resize(angle:)` maps the angle to the nearest platform cursor — `0`/`90` to the public `resizeLeftRight`/`resizeUpDown`, `45`/`135` to the private window-resize selectors (`_windowResizeNorthEastSouthWestCursor` / `_windowResizeNorthWestSouthEastCursor`) guarded with a `?? .arrow` fallback. Drawing-free lookup — every decision happened in Core.

**Hover plumbing:** `AppController` gains `pointerHover(_ point:, modifiers:)` and stores `lastHoverPoint`. The input view forwards `mouseMoved` (no button) to it; while the selection tool is active it computes `region` → `cursorFor(...)` → `CursorSpec` and emits via the existing `onCursorChanged` path. `refreshCursor()` re-runs region classification from `lastHoverPoint`, so a programmatic selection or box change updates the cursor without mouse motion — `currentCursor` stays a pure function of stored inputs (mode, tool, selection box, last hover point). Note: hover/cursor is **not** drivable through the dev HTTP `/pointer` surface (mouseMoved bypasses the `InputSource` port); cursor behavior is verified by Core unit tests, not the dev API.

## Gesture math

All gesture math lives in a dedicated pure module `SelectionTransforms` (separate from the geometry in `SelectionMath`). Each function takes the gesture-start snapshot (`startBox`, `startTransforms`) plus the current pointer (and modifiers) and returns `(OrientedBox, [StrokeId: Transform])` from one delta — the single source of truth for the gesture, so box and strokes can't diverge. Results preview through `inFlightTransforms` + a live `OrientedBox`, and commit one `editor.transformStrokes` op on `pointerUp`.

**Translate** by `(dx, dy)`:
- box: `center += (dx, dy)`
- each stroke: `translate += (dx, dy)`; scale, rotate unchanged.

**Resize** — dragging a corner with the diagonally-opposite corner `C` (world-space, captured at gesture start) pinned:
- factor `s = dist(C, pointer) / dist(C, startCorner)`, clamped to a floor (e.g. `0.05`) so it can't collapse or flip.
- box: `size = startSize * s`, `center = C + s * (startCenter - C)`; rotation unchanged.
- each stroke: `scale = startScale * s`, `translate = C + s * (startTranslate - C)`; rotate unchanged.

**Rotate** — around the box center `M` (= start center):
- `θ = angle(M, pointer) - angle(M, startPointer)`; if Shift held, snap `θ` to the nearest 15°.
- box: `rotation = startRotation + θ`; center unchanged.
- each stroke: `rotate = startRotate + θ`, `translate = rotateAround(startTranslate, M, θ)`; scale unchanged.

Because every stroke rotates around the **shared** center `M` (not its own), a multi-stroke group rotates as one rigid unit — the relative arrangement is preserved (e.g. four strokes drawn as a box stay a box).

## Architecture & hexagonal boundary

Focused units rather than one grab-bag — `SelectionMath` stays geometry-only; gesture math and cursor policy get their own homes:

**Core (pure Swift, all red/green tested):**
- `Sources/Core/Selection/OrientedBox.swift` — the box value + geometry helpers (and `Point` if Core lacks one).
- `Sources/Core/Selection/SelectionMath.swift` — geometry only: `selectionBounds`, `hitTest`, `marqueeHit`, `region(...)`.
- `Sources/Core/Selection/SelectionRegion.swift` — `SelectionRegion` + `Corner` enums and the `cursorFor(region:boxRotation:dragging:) -> SystemCursor` policy free function.
- `Sources/Core/Selection/SelectionTransforms.swift` — the translate/resize/rotate gesture math, each returning `(OrientedBox, [StrokeId: Transform])`.
- `Sources/Core/Model/CursorSpec.swift` — refactor the struct to the `brush`/`system` enum; add `SystemCursor` (with `.resize(angle:)`). Update the pen path to emit `.brush(...)`.
- `Sources/Core/Control/AppController*.swift` — session state `selectionBox: OrientedBox?` and `lastHoverPoint: Point?` (+ publishers), `pointerHover(_:modifiers:)`, `refreshCursor()` re-running region classification from `lastHoverPoint`, region-first `pointerDown` routing, resize/rotate gesture states added to the existing `SelectionGesture` enum, transient-lifetime handling (Space-up clear with mid-gesture deferral), tool-gated `run(.clear)`.

**AppKit (thin, drawing-only, smoke-tested):**
- `CursorRenderer` — `SystemCursor → NSCursor`: public cursors + `.resize(angle:)` → nearest platform cursor (public orthogonals, private-selector diagonals with fallback) + programmatic rotate image.
- `CanvasView` — `setSelectionBox(_ box: OrientedBox?)` replaces `setSelectionBounds`; strokes the rotated rectangle, four rotated corner handles, and the rotate node. Marquee stays an axis-aligned `Rect`.
- input view — forward `mouseMoved` to `pointerHover`.

**App (`main.swift`):** the `onSelectionChanged` / in-flight subscriptions now publish/consume an `OrientedBox` instead of a `Rect`; wire `pointerHover`.

The test boundary: region classification, cursor policy, gesture math, box lifecycle, and pointer routing are all pure-Core and tested with value inputs. AppKit only does `NSCursor` lookup and pixel drawing.

## Testing strategy (red/green)

**Core — `OrientedBox` / `SelectionMath` (geometry):**
- `OrientedBox`: `corners()`, `rotateNode(offset:)`, `toLocal(_:)` round-trip at rotation 0 and non-zero.
- `region(at:box:...)`: rotate node → `.rotateHandle`; each corner → `.corner(that)`; interior → `.body`; far → `.outside`; with a rotated box, a point at the *rotated* top-left corner still classifies as `.corner(.topLeft)`.

**Core — `SelectionRegion` cursor policy:**
- `cursorFor(...)`: `.rotateHandle → .rotate`, `.body → .openHand` (and `.closedHand` when `dragging`), `.outside → .arrow`; corner angle bucketing — at boxRotation 0 `.topLeft → .resize(angle: 135)`; rotate the box ~45° and the same corner buckets to the adjacent angle.

**Core — `SelectionTransforms` (gesture math):**
- translate (delta applied to box + each stroke); resize (uniform factor from the opposite-corner anchor, floor clamp prevents collapse, box + strokes scale around `C`); rotate (angle from center, Shift snaps to 15°, box rotation accumulates, strokes orbit + spin). Each asserts the returned `(OrientedBox, [StrokeId: Transform])` pair is consistent (box and strokes from the same delta).

**Core — `AppController` (recording doubles):**
- region-first routing: clicking a member of a multi-selection keeps the whole selection and begins translate; empty-inside-box begins translate; corner → resize; node → rotate; outside-on-stroke replaces; outside-empty → marquee.
- Cmd: click toggles one stroke; Cmd-marquee toggles each intersected.
- transient lifetime: Space-up clears selection; Space-up *during* a gesture defers the clear to the next `pointerUp`; `Esc` deactivates fiti regardless of selection (no selection-specific branch).
- `pointerHover` emits the correct `CursorSpec` per hovered region.
- selection-set change recomputes the box at rotation 0.
- tool-gated `run(.clear)`: in `.selection` with a selection → erases only those strokes; in `.selection` with no selection → no-op (strokes untouched, `canUndo` unchanged); in `.pen` → clears all. `clear()` (Cmd+K path) always wipes everything regardless of tool.
- rigid group rotation: four strokes forming a box, select all, rotate — each stroke's resulting transform preserves the arrangement; one undo entry restores all.

**AppKit (smoke):** `CursorRenderer` returns a non-nil `NSCursor` for every `SystemCursor` (including the diagonal-selector fallback path); `CanvasView.setSelectionBox` draws the rotated chrome (light pixel-sample).

`Editor.transformStrokes` / `eraseStrokes` are already covered; resize/rotate just feed transforms it already handles.

## Non-goals / simplifications

- Non-uniform (per-axis) scale. `Transform.scale` is a single value; edges aren't interactive.
- Recovering box orientation after deselect/reselect. Reselecting the same strokes recomputes an upright box (rotation 0); orientation is session state, not stored per group.
- Per-stroke restyle (color/width) of a selection.
- Cross-display selection (single-display canvas, per the roadmap).
- A toolbar button for the tool; press-and-hold Space remains the only entry.

## Acceptance criteria

- [ ] While holding Space, clicking any member of a multi-selection (or the empty interior of its box) drags the whole selection; releasing Space clears the selection.
- [ ] Space+Cmd+click toggles a single stroke; Space+Cmd+drag marquee toggles each intersected stroke (Cmd only matters while Space holds the selection tool).
- [ ] Dragging a corner scales the selection uniformly with the opposite corner pinned; it cannot collapse or flip.
- [ ] Dragging the rotate node rotates the selection around its center as a rigid unit (a box of strokes stays a box); Shift snaps to 15°.
- [ ] The selection box is oriented — it tilts with the content, stays snug, and persists at its angle; the rotate node travels with it.
- [ ] Hovering shows the right cursor per region: hand inside, the angle-correct diagonal on corners (even when the box is rotated), rotate arrows on the node, arrow outside.
- [ ] Each gesture commits one undoable op; undo restores the prior transforms.
- [ ] `Delete` while Space is held erases the selection if any, else does nothing; `Delete` in pen mode (Space up) clears all; `Cmd+K` always clears everything regardless of tool. `Esc` deactivates fiti (release Space to clear a selection).
- [ ] `Sources/Core/` has zero AppKit/CoreGraphics/Network/SwiftUI imports; region/cursor/gesture/lifetime logic is unit-tested without drawing.
- [ ] Full suite stays under 5 seconds (`just check`).

## Open questions / future

- Diagonal cursor on a rotated box is bucketed into the four available system cursors (45° granularity). Custom per-angle cursor images could be a later polish if it feels coarse.
- Snap rotation to 15° on Shift only; finer/other snap angles deferred.
- Oriented box across deselect/reselect: if all selected strokes share one rotation, the box could re-orient to it; deferred (upright on reselect for now).
- Eraser tool reuses `SelectionMath.hitTest`; natural follow-on.
