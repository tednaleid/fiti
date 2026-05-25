# fiti Outline / Halo (prototype)

Status: design approved 2026-05-25. Prototype on branch `outline-halo`.
Global toggle to start; per-tool / per-mark control is a deliberate follow-up.

## Summary

Add a global, non-destructive render-mode toggle that draws a contrasting halo
around every mark (pen strokes, arrows, and text) so annotations stay legible on
any background. The halo color is auto-derived from the mark's own color by
luminance (white halo on dark colors, dark halo on light ones), the way
CleanShot's "Outlined" text style works. When off, rendering is byte-for-byte
today's behavior.

This is a prototype to let us evaluate the look across all three mark types
before deciding the eventual scope (likely per-tool + per-mark).

## Goals

- A global "Outline" toggle in Preferences (checkbox), plus a dev HTTP route.
- A contrasting halo on pen strokes, arrows, and text.
- Halo color auto-contrast from the draw color, preserving the mark's alpha.
- Non-destructive: the document model is unchanged; toggling re-bakes and repaints.
- All the decision logic (enabled, halo color, halo width) is a pure Core
  function, unit-tested; AppKit only does the CoreGraphics/CoreText drawing.

## Non-goals

- Per-tool or per-mark outline selection (global only for now; the likely
  eventual combo, but out of scope for this prototype).
- Any other catalog effect (drop shadow, glow, sticker border, highlighter
  underlay). Gradient fill is recorded on the roadmap as a future possibility.
- Outlining the watercolor wash. Outline and watercolor are independent toggles;
  if both are on, watercolor strokes stay washes (no halo) while text and arrows
  get the halo.
- Any change to how marks are stored or serialized.

## Decisions (from brainstorming)

- Color: auto-contrast by luminance (white on dark, black on light), alpha
  preserved. No new color UI.
- Scope: a global toggle for the prototype, so the look can be tried on all three
  mark types. Per-tool + per-mark is the expected follow-up, not built now.
- Architecture fork: thread an `outline` flag into the draw functions (which own
  the geometry), rather than a global mutable render flag. The draw functions
  call a pure Core resolver for the color and width; they hold no policy.

## Architecture

Mirrors the existing `FadeSettings` / watercolor toggle shape.

### Pure Core: the policy lives here

- `Sources/Core/Rendering/OutlineStyle.swift` (new):
  ```swift
  public struct ResolvedOutline: Equatable {
      public let haloColor: RGBA
      public let haloWidth: Double   // points
  }

  /// Pure outline policy. Returns nil when disabled. haloColor is the
  /// luminance-contrast of `color` (light halo on dark colors, dark halo on
  /// light ones) preserving alpha; haloWidth is `sizeBasis * widthFactor` points.
  public func resolveOutline(enabled: Bool, color: RGBA, sizeBasis: Double,
                             widthFactor: Double) -> ResolvedOutline?
  ```
  - `enabled == false` -> nil.
  - Luminance (Rec.601: `0.299r + 0.587g + 0.114b`) below
    `OutlineTuning.luminanceThreshold` -> white halo `(1,1,1,color.a)`, else black
    `(0,0,0,color.a)`. Alpha is always the mark's alpha so a faded mark's halo
    fades with it.
  - `haloWidth = sizeBasis * widthFactor`.
- `Sources/Core/Rendering/OutlineTuning.swift` (new): pure constants gathered in
  one place. `strokeWidthFactor` (halo lineWidth as a fraction of stroke/arrow
  width), `textWidthFactor` (halo as a fraction of font size), `luminanceThreshold`.
  Values are hand-tuned after the first end-to-end render.
- `Sources/Core/Ports/OutlineSettings.swift` (new): `@MainActor protocol
  OutlineSettings: AnyObject { var outlineEnabled: Bool { get set } }` plus an
  in-memory `DefaultOutlineSettings` (default off). Mirrors `WatercolorSettings`.

### AppKit: thin rendering of the resolved values

- `Sources/AppKit/UserDefaultsOutlineSettings.swift` (new): UserDefaults adapter,
  key `fiti.outlineEnabled`, default off. Mirrors `UserDefaultsWatercolorSettings`.
- Draw-function changes (all in `Sources/AppKit/StrokeDrawing.swift` and
  `Sources/AppKit/ArrowDrawing.swift`): add `outline: Bool = false` to `drawItem`,
  `drawStroke`, `drawArrow`, and the text path (`drawText` / `drawTextString`).
  Each computes its halo by calling the Core `resolveOutline(...)`:
  - **Pen stroke** (`drawStroke`): with the perfect-freehand polygon already in
    hand, if `resolveOutline(enabled: outline, color: stroke.color,
    sizeBasis: stroke.width, widthFactor: OutlineTuning.strokeWidthFactor)` is
    non-nil, stroke that polygon in `haloColor` at `haloWidth` (round join/cap)
    BEFORE the existing fill, so the halo sits outside the mark.
  - **Arrow** (`drawArrow`): same, using `arrow.width` as the size basis; stroke
    the merged silhouette polygon in the halo color behind the existing fill
    (the same-color corner-rounding stroke stays).
  - **Text** (`drawTextString`): if resolved, add `.strokeColor = haloColor` and
    `.strokeWidth = -100 * haloWidth / fontSize` (negative = fill-and-stroke; the
    NSAttributedString strokeWidth is a percentage of font size) to the run
    attributes. This is the standard outlined-glyph treatment.
- `Sources/AppKit/GroupCompositor.swift`: `compositeGroups(_:in:outline:)` passes
  the flag to its `drawItem(item.withAlpha(1), ..., outline: outline)`.
- `Sources/AppKit/CanvasView.swift`: read `OutlineSettings` (settable property,
  defaulting to `DefaultOutlineSettings()` so existing tests are unaffected); add
  the flag to the bake-rebuild condition (alongside `bakedWatercolor`), pass it to
  `compositeGroups` in `bakeCommitted` and to the live `drawItem` / in-progress
  draws; `refresh()` re-renders on toggle.
- `Sources/AppKit/SnapshotRenderer.swift`: add `outline: Bool = false`, thread it
  through the same way the `watercolor` flag is threaded.

### Wiring and dev surface

- `Sources/App/main.swift`: one shared `UserDefaultsOutlineSettings` instance,
  injected into the canvas, Preferences, and the dev surface; toggles call
  `canvas.refresh()`.
- `Sources/AppKit/PreferencesController.swift` + `PreferencesWindow.swift`: an
  "Outline" checkbox row, mirroring the watercolor checkbox; window grows to fit.
- `Sources/DevHTTP/`: `var outlineEnabled` + `func setOutline(_:)` on the
  `DevHTTPSurface` protocol; a `POST /outline` route; `outlineEnabled` in `/state`;
  `FitiDevHTTPSurface` reads/writes the shared settings + refresh closure;
  `just inspect-outline-on` / `-off` recipes.

### Flattening interaction

The outline lives inside each item's draw, so it flows through the existing
opacity-flattening unchanged. No bypass and no active-layer-lift change (unlike
watercolor): `compositeGroups` still draws each item opaque in its transparency
layer, now including the halo, then composites the group at its alpha. Two
overlapping same-color outlined marks union flat within the layer as before.

## File structure

New:
- `Sources/Core/Rendering/OutlineStyle.swift` (`ResolvedOutline` + `resolveOutline`)
- `Sources/Core/Rendering/OutlineTuning.swift`
- `Sources/Core/Ports/OutlineSettings.swift`
- `Sources/AppKit/UserDefaultsOutlineSettings.swift`

Modified:
- `Sources/AppKit/StrokeDrawing.swift` (drawItem/drawStroke/drawText + outline)
- `Sources/AppKit/ArrowDrawing.swift` (drawArrow + outline)
- `Sources/AppKit/GroupCompositor.swift` (compositeGroups pass-through)
- `Sources/AppKit/CanvasView.swift` (settings, bake invalidation, live draws, refresh)
- `Sources/AppKit/SnapshotRenderer.swift` (outline pass-through)
- `Sources/AppKit/PreferencesController.swift`, `PreferencesWindow.swift` (checkbox)
- `Sources/App/main.swift` (shared instance wiring)
- `Sources/DevHTTP/DevHTTPSurface.swift`, `DevHTTPServer.swift` (+ `DevHTTPServer+Outline.swift`)
- `Sources/App/FitiDevHTTPSurface.swift` (shared settings + refresh)
- `justfile` (inspect recipes)
- `docs/fiti-roadmap.md` (record gradient fill + the remaining catalog effects)

## Testing

Swift Testing, suite under 5 seconds, red/green.

Core (`fiti-unit`), all on the pure resolver and settings:
- `resolveOutline` returns nil when disabled.
- A dark color yields a white halo; a light color yields a black halo; assert at
  the `luminanceThreshold` boundary in both directions.
- Halo alpha equals the input color's alpha (faded mark -> faded halo).
- `haloWidth == sizeBasis * widthFactor`.
- `OutlineSettings` in-memory default is off and round-trips.
- `UserDefaultsOutlineSettings` defaults off when unset and round-trips (AppKit
  target).

AppKit (`test-integration`), pixel sampling like the watercolor renderer tests
(the irreducible drawing, which cannot be a Core unit test):
- With outline on, a stroke shows halo-colored pixels just outside the fill edge
  that are absent with outline off.
- The halo color matches the resolved contrast (white pixels around a dark-red
  stroke).
- Outlined text shows contrast-colored pixels on the glyph contours.
- Outline off renders byte-for-byte as today (existing bake/flatten tests pass).
- Preferences checkbox and the dev route round-trip the setting.

## Engineering principles

- Red/green TDD per task; `just check` (the pre-commit gate) green at every
  commit; never `--no-verify`.
- Hexagonal: the entire outline policy (enabled, color, width) is the pure Core
  `resolveOutline` plus constants, driven by in-memory doubles in tests. AppKit
  is a thin renderer that calls the resolver and issues CoreGraphics/CoreText
  strokes. The toggle is a Core port with a UserDefaults adapter.

## Risks and notes

- Performance is a non-issue: an outline is one extra native stroke pass (or two
  attributes for text). No offscreen, no blur, no per-pixel work. Safe live.
- `strokeWidthFactor` / `textWidthFactor` will be hand-tuned after the first
  render; stroke/arrow and text likely want different weights, which is why they
  are separate constants. If a single factor turns out fine, they collapse later.
- Stroke halo draw order: stroke-behind (wide halo stroke, then fill on top) keeps
  the halo outside the mark. Text uses NSAttributedString's negative `strokeWidth`
  (fill-and-stroke centered on the glyph contour), the standard outlined-glyph
  look, which is what CleanShot does.
- Global mode means all-or-nothing for the prototype. Per-tool + per-mark is the
  follow-up once the look is validated.
