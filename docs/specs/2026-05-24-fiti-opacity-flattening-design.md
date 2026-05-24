# fiti Opacity Flattening Design (v2: transparency-layer flatten)

Date: 2026-05-24
Status: Design approved in principle, written up for review.

Supersedes the v1 attempt (preserved on the `opacity-flattening-v1` branch),
which was visually correct but ~450x too slow: its compositor drew each item
into its own full-canvas pixel buffer and walked every pixel, an O(items x
canvas) shape that beachballed on every stroke. See `docs/perf-baseline.md`.

## Problem

Every mark composites source-over at its own alpha, so two marks of the same
color at 50% darken to ~75% where they overlap. Drawing several strokes to
"color in" a region looks blotchy. We want overlapping marks of the same color
to read as one flat region at the intended opacity.

## Goals

- Overlapping marks of the same color read as a single flat region, not an
  accumulation of alphas.
- WYSIWYG: the in-progress stroke flattens with its same-color neighbors live,
  and what is drawn is pixel-identical to what commits on pen-up. (This is the
  primary requirement; the feature is not worth shipping if drawing differs from
  the committed result.)
- Fast: the committed bake and the live per-frame path stay in the single-digit
  millisecond range, matching the source-over baseline. Per-frame cost must not
  scale with the number of already-drawn marks.
- Always on (the darkening is treated as a defect, not a mode).
- Core stays pure: grouping is a pure, unit-testable function; only pixel
  compositing lives in the AppKit adapter.

## Non-goals

- Max-opacity-wins across mixed opacities. Grouping is keyed on `(hue, alpha)`,
  so two same-color marks at different opacities that overlap still accumulate.
  Accepted: the real use case is coloring in at one opacity.
- Per-pixel maximum across a genuine cross-hue conflict. When a different color
  truly sits between two same-color marks in the overlap region in z-order, the
  same-color marks cannot merge without changing visible layering, so that one
  overlap may still accumulate. Rare and unavoidable for any flat-layer scheme.
- Exact-shape overlap testing. Overlap uses axis-aligned bounding boxes (AABB).

## Core concept: one flatten routine, two callers

The committed bake and the live in-progress render call the same group-flatten
routine with the same inputs, so their output is pixel-identical. WYSIWYG is a
structural property, not something to verify after the fact.

### Grouping (pure, Core)

`LayerPlan` (reused from the v1 branch, re-keyed) groups items into flattened
layers. The group key is `(r, g, b, a)` exactly. Items of the same key always
merge; a different-key mark introduces an ordering constraint only where its
AABB overlaps, so cross-color z-order is preserved. Greedy constraint-respecting
clustering, emitted bottom-to-top. Grouping measured 0.03 ms in v1; it is not a
performance factor.

### Flattening one group (AppKit)

For each group, in composite order:

1. `beginTransparencyLayer`.
2. Draw every item in the group opaque (alpha forced to 1) with source-over.
   Opaque-over-opaque is a flat coverage union, with no alpha accumulation.
3. `endTransparencyLayer` with the context alpha set to the group's alpha.

The group's alpha is applied once to the flattened union. Because every item in
a group shares the same alpha (it is part of the key), a non-overlapping item
reproduces its own alpha and an overlapping region reads the single group alpha,
flat. Native CoreGraphics bounds the work to the drawn region; there are no
per-item pixel buffers and no per-pixel loop. This is the entire speed fix.

Drawing an item "opaque" means filling its geometry with its color at alpha 1.
The drawing functions gain an explicit alpha-override path for this; the rest of
`drawItem` / `drawStroke` / text drawing is unchanged.

Source-over compositing is associative, so a union rendered to an image and then
drawn under/over another mark yields the same coverage as drawing all marks
directly. That equivalence is what lets the live cache (below) match the bake.

## Architecture

### Committed bake

`CanvasView.bakeCommitted` flattens all committed groups through the routine
above into the committed CGImage. Runs only when the bake signature changes.

The bake signature must capture every field that affects appearance or grouping:
transform, hue (r, g, b), alpha, width (strokes), and text content (string, font,
size). v1's signature left strokes at a constant tag, so a restyled committed
stroke did not re-bake; this design includes that fix (a standalone bug fix,
commit `3903e60` on the branch).

### Live flattening (cached opaque union)

The in-progress stroke belongs to one `(hue, alpha)` group. Its committed
members are lifted out of the static bake so they can flatten live with the
stroke, exactly as v1 did, but the per-frame cost is made O(1):

- At pen-down (when the lifted set changes): render the group's committed
  members once into a cached opaque-union image (each drawn opaque, source-over).
  Rebuild the static bake without those members.
- Each frame during the drag: `beginTransparencyLayer`; draw the cached
  opaque-union image (one blit); draw the in-progress stroke opaque;
  `endTransparencyLayer` at the group alpha. Composite that on top of the static
  bake.
- At pen-up: the stroke commits, the lifted set empties, the static bake rebuilds
  with all members, and the cached union is discarded.

Per-frame work is one image blit plus one stroke fill, independent of how many
marks are already on the canvas. This is the deliberate departure from v1, which
re-flattened every lifted member every frame.

### Snapshot

`SnapshotRenderer` flattens committed groups through the same routine, so
`GET /snapshot.png` matches the committed screen. A snapshot has no in-progress
stroke, so it composites the plain plan.

### Fade

`globalOpacity` (auto-fade) stays a single multiplier on the final blit. It is
unchanged and now correct, because within-group overlaps are already flat.

## Data flow

```
Editor.doc (items, itemOrder)
  -> RenderFrame (items, liveItems, inProgress, canvasSize)
       -> LayerPlan.compute (key = hue+alpha)        [pure, Core]
            -> [FlattenLayer]
                 -> flatten routine                  [AppKit: per-group
                    (transparency layer, draw         transparency layer,
                     opaque, composite at alpha)       opaque draw, alpha blit]
                      -> committed bake CGImage       (CanvasView)
                      -> live: cached union + stroke  (CanvasView, per frame)
                      -> snapshot PNG                 (SnapshotRenderer)
```

## Files

- Create: `Sources/Core/Rendering/LayerPlan.swift` (port from branch; group key
  becomes `(r, g, b, a)`).
- Modify: `Sources/Core/Selection/SelectionMath.swift` (make `worldAABB` public;
  port from branch).
- Create: `Sources/AppKit/GroupCompositor.swift` (the transparency-layer flatten
  routine, shared).
- Modify: `Sources/AppKit/StrokeDrawing.swift` (opaque-draw path).
- Modify: `Sources/AppKit/CanvasView.swift` (broaden bake signature; bake via the
  routine; live cached-union lift; keep the perf probe hooks).
- Modify: `Sources/AppKit/SnapshotRenderer.swift` (flatten via the routine).
- Tests under `Tests/CoreTests` (grouping) and `Tests/AppKitTests` (pixel + WYSIWYG).

## Testing

Core (pure, fast):

- Same-key marks merge into one layer; different non-overlapping key stays
  independent but does not split a same-key run; a genuine cross-key overlap
  between two same-key marks splits them; different alpha of the same hue lands
  in different groups (keyed on alpha).

AppKit (pixel-sample on the offscreen bake):

- A `+` of two same-color 50% strokes: the intersection equals the arms (flat),
  not darker.
- WYSIWYG: render a committed same-color mark plus an in-progress crossing stroke
  via the live path, and the same two marks both committed via the bake; the
  intersection pixel matches between the two renders.
- Cross-color overlap: the later group shows on top (z-order preserved).
- Restyle a committed stroke: the signature changes and the image updates.

Performance (the perf probe, against `docs/perf-baseline.md`):

- Committed bake stays single-digit ms.
- Live per-frame composite stays sub-millisecond and does not grow with the
  number of committed marks (draw N marks, then measure a live stroke; the
  per-frame time must be flat in N).

Each milestone re-measures with `just inspect-perf`; if the bake or live path
leaves the single-digit-ms range, stop and rethink before continuing.

## Known limitations

- Mixed-opacity same-hue overlaps accumulate (accepted; keyed on alpha).
- A genuine cross-hue conflict can leave a same-hue overlap accumulated.
- AABB overlap is conservative: boxes that touch but whose shapes do not may add
  an unneeded ordering constraint. Errs toward slightly more darkening, never
  toward wrong z-order.

## Implementation notes

Two refinements were added during implementation:

- Per-group clipping. `GroupCompositor` clips each group's transparency layer to the padded
  union of its items' world AABBs (padded by the stroke's world-space width so ink is never
  shaved). CoreGraphics sizes a transparency-layer offscreen to the current clip; without the
  clip every group paid a full-canvas offscreen and the committed bake hitched ~30 ms with
  multiple colors. With clipping the bake is ~2 ms.
- Below/above bake split for live z-order. The in-progress stroke's group is composited in its
  true z-slot, not simply on top: the static bake is split into the groups below the active
  group and the groups above it, and the live frame draws below, then the active group (cached
  union plus the live stroke at the group alpha), then above. This makes cross-color z-order
  while drawing match the committed result (a different-color mark above the active group stays
  on top during the drag).

## Alternatives considered: global per-color levels

A simpler model would assign each (color, opacity) one fixed global level, so all red 50%
always composites at the same level regardless of draw order.

Pros: perfect same-color flatness and full determinism; trivial grouping (one layer per
distinct color+opacity, no overlap analysis); and it eliminates the cross-hue-conflict
limitation below entirely (all same-color marks always merge).

Con (why rejected): it replaces draw-order stacking with color-order stacking. A mark drawn
last over a different color would sink to its color's fixed level instead of appearing on top,
breaking the "last drawn is on top" expectation that annotation relies on. There is also no
non-arbitrary way to order colors against each other: a fixed palette order is wrong relative
to what was drawn, and most-recent-use ordering makes every mark of a color jump z-level at
once. We kept overlap-aware grouping, which merges same-color marks everywhere except where
merging would reorder a real overlap, preserving draw-order z-order. The cross-hue-conflict
darkening (Known limitations) is the residue of that choice.
