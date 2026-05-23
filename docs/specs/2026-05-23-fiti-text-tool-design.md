# fiti Text Tool — Design

Status: approved design, ready for implementation planning.
Date: 2026-05-23.

## Summary

Add a Text tool to fiti. Pressing `t` enters a sticky Text mode; clicking places a
caret and typing renders text in the current color/opacity at a size derived from
the current stroke size, in Helvetica. Clicking an existing text re-opens it for
editing. Text items are first-class canvas objects: selectable, movable, rotatable,
and scalable through the same machinery as freehand strokes, with the same undo model
and the same two-canvas (committed-bake + live-overlay) rendering.

This feature also introduces a `CanvasItem` sum type that unifies freehand strokes and
text under one identity/transform/z-order model, so future item types (shapes) slot in
as new cases rather than parallel subsystems.

## Goals

- A sticky Text tool reachable with `t`, leaving with `p` (pen) or the toolbar.
- Click blank canvas to start a new text; click existing text to edit it (caret lands
  at the clicked character).
- Multi-line text: `Shift+Return` inserts a newline, `Return` commits.
- Text renders in the active color (including opacity) and a font size derived from the
  active stroke size; Helvetica to start.
- Text is selectable, movable, rotatable, and scalable in selection mode, exactly like
  strokes, sharing the undo stack.
- Editing reuses the immutable two-canvas pattern: the item under edit leaves the bake
  and is drawn live until committed.
- Core stays platform-free; CoreText is confined to the AppKit adapter behind a port.

## Non-goals (deferred)

- Text effects (outline/border/shadow for legibility). Designed to be addable later.
- Rich text: one font, one size, one color per text item. No mixed runs.
- Font picker: Helvetica only for v1.
- Auto-wrap: lines come only from explicit `Shift+Return`; there is no wrap width.
- Intra-edit undo (Cmd+Z while a caret session is live). The edit buffer is not on the
  undo stack until commit; Cmd combos pass through to the menubar during editing.

## Locked decisions

1. Multi-line; `Shift+Return` = newline, `Return` = commit.
2. Sticky Text mode (Figma-style): enter with `t`, stays active; click blank = new text,
   click existing text = edit it; tool switching is by tool key / toolbar, not Esc.
3. Click-to-edit places the caret at the clicked character (precise), via a reverse
   hit-test in the measuring port.
4. Items are modeled as a `CanvasItem` sum type (`stroke` | `text`, future `shape`),
   not a protocol. Document storage, undo, selection, transform, and rendering all
   generalize to `CanvasItem`.
5. Text bounds use strategy B4: a `TextMeasuring` port measures the final string once at
   commit; the resulting local-space size is frozen onto the `TextItem`. The document
   carries this derived field for O(1), port-free selection/hit-test in Core, and the
   port remains available to re-derive if ever needed. Rationale documented in
   `architecture.md`.
6. Esc is layered: while typing it commits the text and drops to pen (escape the typing);
   when not typing it deactivates fiti (escape the overlay), matching today's Esc.
7. New keybindings: `t` (text tool), `p` (pen tool). Everything else is existing behavior
   gated on whether a text session is active.

## Model layer

`Sources/Core/Model/`.

`ItemId` replaces `StrokeId` as the shared identity type. `StrokeId` remains as a
deprecated typealias during migration, then is removed.

```swift
public typealias ItemId = String

public enum CanvasItem: Equatable, Codable, Sendable {
    case stroke(Stroke)
    case text(TextItem)
    // future: case shape(ShapeItem)

    public var id: ItemId { get }                 // switch
    public var transform: Transform { get set }    // switch; set rewraps the case
    public var createdAt: Double { get }
    public var color: RGBA { get }                 // shared fill/opacity accessor
}

public struct TextItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var string: String          // may contain "\n"
    public var fontName: String        // "Helvetica" for v1
    public var fontSize: Double         // derived from current stroke size at creation
    public var color: RGBA             // fill + opacity from the active color
    public var transform: Transform    // placement / move / rotate / scale
    public var bounds: Size            // local-space layout size, measured at commit (B4)
    public let createdAt: Double
}
```

`Stroke` is unchanged except `id: ItemId`.

`FitiDoc` generalizes:

```swift
public var items: [ItemId: CanvasItem]   // was: strokes
public var itemOrder: [ItemId]           // was: strokeOrder (unified z-order)
```

Renames: `doc.strokes`/`strokeOrder` to `items`/`itemOrder`; Editor/AppController
"stroke" surface becomes "item" where it is now generic (see below). The pen path still
produces a `Stroke`, wrapped as `.stroke(...)`.

`fontSize` derivation: `fontSize = currentWidth * 4` (default width 6 to 24pt). A single
tunable mapping in one place; not exposed in the model beyond the stored result.

## Editor and undo

`Editor` remains the sole mutation surface and keeps the forward-edit `InverseOp` model,
generalized from `Stroke` to `CanvasItem`.

`InverseOp` cases:
- `deleteItem(ItemId)` / `restoreItem(snapshot: CanvasItem, atIndex: Int)`
- `deleteItems([ItemId])` / `restoreItems(entries: [ItemRestoreEntry])` (entry carries a
  `CanvasItem` snapshot + index)
- `setTransforms(entries:)` — unchanged; already `id + transform`, so move/rotate/scale
  work identically for text.
- `replaceItems(entries: [CanvasItem])` — swaps full item values in place (same id, same
  z-order); inverse restores prior values. Mirrors the `setTransforms` swap-with-inverse
  shape. This is how a committed text edit lands.

`Editor` methods:
- Pen path unchanged (`startStroke`/`appendPoint`/`endStroke`), wrapping its result as
  `.stroke(...)`.
- `addItem(_ item: CanvasItem)` — commit a new text (undo to `deleteItem`).
- `replaceItem(_ item: CanvasItem)` — commit an edit to an existing text (undo restores
  prior value).
- `transformItems(_:)`, `eraseItems(_:)`, `clear()` — renamed generalizations.

`Editor` never measures. `AppController` measures the final string at commit, builds the
`TextItem` with its `bounds`, and hands the finished `CanvasItem` to the Editor. Editor
stays a pure mutation surface; measurement lives at the composition boundary, once, at
commit.

## The `TextMeasuring` port

`Sources/Core/Ports/TextMeasuring.swift`. Two methods, both trivially faked:

```swift
public protocol TextMeasuring {
    func measure(string: String, fontName: String, fontSize: Double) -> Size
    func caretIndex(at localPoint: Point, string: String,
                    fontName: String, fontSize: Double) -> Int
}
```

- `measure` — called once at commit to freeze `TextItem.bounds`.
- `caretIndex` — called on click-into-text to set the initial caret index, keeping
  click-to-edit routing in testable Core.

Adapter: `Sources/AppKit/CoreTextMeasurer.swift` implements both with CoreText
(`CTLine`/`CTFrame`, `CTLineGetStringIndexForPosition`).

Test fake (deterministic monospace approximation):

```
charWidth  = fontSize / 2
lineWidth  = chars_in_line * charWidth
width      = max lineWidth over all "\n"-split lines
height     = fontSize + (newlineCount * fontSize * 1.5)
caretIndex = clamp by line (localY / lineHeight) then column (round localX / charWidth)
```

## Selection, transform, and rendering

`SelectionMath` generalizes over `CanvasItem` with a small per-kind branch:
- World AABB: a stroke's is the AABB of its transformed `points`; a text's is its local
  `bounds` rect with the four corners pushed through its `transform`, then AABB'd.
- Hit-test: stroke uses distance-to-polyline within `width/2 + tolerance`; text uses
  point-inside-oriented-box (reusing the existing `OrientedBox` containment).
- `marqueeHit` / `selectionBounds`: same logic, iterating `items` with the per-kind box.

Move/rotate/scale need no new math. `SelectionTransforms` operates on `transform` maps,
and `recomputeSelectionBox` builds the oriented box from the selection AABB union. A
selected text gets an axis-aligned box that rotates only when the selection is rotated,
identical to a rotated stroke. Resize scales `transform.scale` (scales the rendered
glyphs, consistent with strokes); it does not re-flow the font size.

`RenderFrame` generalizes: `items: [CanvasItem]`, `liveItems: [CanvasItem]` (in-flight
transform overrides, so dragging a text matches dragging a stroke), `inProgress: Stroke?`
(pen, unchanged). `RenderFrame.from` takes an `editingItemId: ItemId?` and excludes that
item from the committed bake; the live edit-session path draws it instead (same as the
in-progress pen stroke exclusion).

Bake invalidation: today `BakeSignatureEntry` is `{id, transform}`, sufficient because a
committed stroke's pixels never change. A committed text can change content via
`replaceItem` (same id and transform, new string), so the signature gains a content tag:
a hash of `string + fontName + fontSize + color`. Strokes are immutable post-commit, so
`id + transform` still covers them.

Adapter rendering: `drawStroke` generalizes to `drawItem(_ item: CanvasItem)`. `.stroke`
keeps the perfect-freehand path; `.text` lays out the string with CoreText in the item's
color and draws it, applying `transform` via the same `saveGState` to CTM to
`restoreGState` pattern strokes already use.

## Text editing session

The edit buffer is pure Core; CoreText is confined to the adapter.

```swift
public struct TextEditSession: Equatable, Sendable {
    public var itemId: ItemId?      // nil = new text; set = editing an existing item
    public var string: String       // may contain "\n"
    public var caret: Int            // character index into string
    public var transform: Transform  // placement (where the click landed)
    public var color: RGBA
    public var fontName: String
    public var fontSize: Double
}
```

On `AppController`: `var textSession: TextEditSession?` plus an `onTextSessionChanged`
publisher the adapter renders from. Editing operations are pure string/index logic, fully
unit-testable: `insert(_:)`, `deleteBackward`, `insertNewline`, and
`moveCaret(.left/.right/.up/.down/.lineStart/.lineEnd)`. Caret up/down works off
`\n`-delimited lines (no auto-wrap, so line/column structure is derivable from the string
alone).

### AppController routing (text mode)

- `t` sets `currentTool = .text` (sticky; I-beam cursor). `p` sets `currentTool = .pen`.
- pointerDown: commit any active session first; then Core hit-tests items.
  - Click on existing text item: begin editing it (load its string; caret =
    `port.caretIndex(at:)`; mark it the `editingItemId` so it leaves the bake).
  - Click anywhere else (blank or a stroke): start a new empty session at the click.
    In text mode, clicks concern text, not selecting strokes.
- Commit (Return, click-away, or Esc-while-typing): `port.measure(...)` to `bounds`; if
  the string is non-empty, build the `TextItem` and `editor.addItem` (new) or
  `replaceItem` (existing). An emptied existing text commits as `eraseItems`. A new empty
  text is discarded. Return keeps you in text mode; Esc-while-typing drops to pen.

### Keyboard capture

`KeyMonitor` gains a branch: when `controller.isEditingText`, keystrokes route to the
session rather than to command shortcuts or the Space tool switch:
- `Return` to commit; `Shift+Return` to `insertNewline`; `Esc` to commit + pen;
  `Backspace` to `deleteBackward`; arrows to `moveCaret`; other printable input to
  `insert(event.characters)`.
- While editing, `s`/`o`/`Space`/`t`/`p` all type rather than firing shortcuts. The
  Space-hold-for-selection switch is suspended in text mode (selection is reached from
  pen mode). `Cmd` combos still pass through to the menubar.

### Cursor

Add `SystemCursor.iBeam` mapped to `NSCursor.iBeam` in `CursorRenderer`. Text mode shows
the I-beam.

### Live rendering

The adapter subscribes to `onTextSessionChanged` and draws the live string plus a caret
(caret pixel position computed from its own CoreText layout). This is the "draw it live,
do not bake it" half of the two-canvas pattern. A new text has no committed item; an
edited text is excluded from the bake by `editingItemId`.

## Interaction model summary

- Tool switching: `t` (text), `p` (pen), plus toolbar icons where present. Space-hold
  selection is unchanged (transient, from pen).
- `Return` = commit and keep placing text; `Shift+Return` = newline.
- `p` / toolbar = leave text for pen without deactivating.
- Esc, layered: while typing it commits the text and drops to pen; when not typing it
  deactivates fiti (cursor released, click-through on, drawings still visible). This
  falls out of the capture rule with no special-casing.
- Selecting, moving, rotating, and scaling text happen in selection mode (Space from
  pen); text mode is dedicated to entering and editing text.

## Consistency calls

- Text items auto-fade like strokes (they are items with `createdAt`). A fresh
  `createdAt` on commit resets the fade timer; editing an existing text via `replaceItem`
  resets it too. The active edit session is excluded and does not fade mid-edit.
- `Cmd+K` clear and tool-gated `Delete` treat text as items (cleared/deleted with
  strokes), inheriting current behavior.

## Hexagonal architecture notes

- Core (`Sources/Core/`) gains `CanvasItem`, `TextItem`, `TextEditSession`, the
  generalized `Editor`/`SelectionMath`/`RenderFrame`, and the `TextMeasuring` port. None
  of it imports AppKit/CoreGraphics/CoreText.
- The AppKit adapter owns CoreText: `CoreTextMeasurer` (the port), live text + caret
  drawing, and `drawItem`'s text branch.
- The only platform-derived data that enters the model is `TextItem.bounds`, supplied by
  the port at commit (B4). Everything else Core needs is authored data or pure logic.
- The edit buffer's string/caret logic and the click-to-caret-index routing are pure Core
  (the port's `caretIndex` is faked in tests), so the editing state machine is unit
  testable without drawing.

## Documentation tasks (part of the plan)

- Add to `architecture.md`: the B4 rationale (the `TextMeasuring` port, measure-once-at-
  commit, why a derived `bounds` field lives in the document, and the re-derive escape
  hatch). Add a pointer comment near `TextItem.bounds` in code.
- Add to `architecture.md` a short geometry glossary: AABB (axis-aligned bounding box),
  bounding box, and oriented box, with the tilted-box-vs-upright-box distinction.

## Testing strategy

Pure Core, no drawing:
- `CanvasItem` accessors (id/transform get+set/createdAt/color) per case.
- `Editor` generalized ops and undo/redo: add/replace/erase/transform items, including
  `replaceItems` round-trips for text edits.
- `SelectionMath` over mixed stroke+text docs: AABB, hit-test (point in rotated text
  box), marquee, selection bounds.
- `TextEditSession` edit operations: insert, deleteBackward, insertNewline, caret motion
  including up/down across `\n` lines and clamping at ends.
- `AppController` text routing with a `FakeTextMeasurer`: click-blank starts a new
  session; click-on-text begins editing at the reverse-mapped caret; Return commits and
  stays in text mode; Esc-while-typing commits and drops to pen; Esc-when-idle
  deactivates; empty-commit discards; emptied-existing-commit erases; fontSize derives
  from current width; color/opacity from current color.
- Bake signature: a text content change yields a different signature even when transform
  is unchanged.

Adapter (integration target): `CoreTextMeasurer` returns plausible non-zero sizes and a
caret index within range (smoke level); `drawItem` text branch does not crash and honors
the transform. Heavy glyph-accuracy assertions are out of scope.

## Open questions / future

- Text effects (outline/border) for legibility on busy backgrounds: deliberately deferred;
  `TextItem` can gain effect fields later without disturbing this design.
- Precise caret for complex scripts / bidi is best-effort; v1 targets Latin text.
- Font picker and multiple fonts: future.
