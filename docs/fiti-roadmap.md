# fiti Roadmap

Living document (started 2026-05-16, refreshed 2026-05-23).
Status: Backlog. Items here are not committed scope. Each item becomes a brainstorm → design spec → implementation plan when it's time to land.

## What this is

A running list of things that move fiti from "POC + hardened" to "an app I actually want to use." Items are roughly grouped by impact, not committed to an order. Anything that's a separate independent spec gets a checkbox so we can tick it off as work begins.

## Shipped

- [x] Menubar status item (active/idle SF Symbol icons; menu for activate/deactivate, preferences, clear, undo, redo, quit) — `Sources/AppKit/MenubarController.swift`.
- [x] Floating toolbar (color quick-picks, custom color, width slider, opacity slider, hide/show button) — `Sources/AppKit/ToolbarController.swift`.
- [x] Hide / show drawings (toolbar button + `AppController.drawingsVisible` state). Global hotkey is still missing — see open items below.
- [x] User-customizable activation hotkey via `sindresorhus/KeyboardShortcuts`. Default Opt+F. Preferences UI with `RecorderCocoa` ships in 0.2.0.
- [x] Launch-at-login toggle via `SMAppService.mainApp` — Preferences UI in 0.2.0.
- [x] Perfect-freehand Swift port (tapered, velocity-aware strokes). `simulatePressure: true` synthesises pressure from velocity for mouse input.
- [x] Retina-correct two-canvas bake (`window.backingScaleFactor` multiplier + CTM compensation).
- [x] Hold-to-straighten gesture (Notability-style draw-and-hold-to-snap, then rubber-band the endpoint).
- [x] Real code signing (Developer ID Application cert via `FITI_CODE_SIGN_IDENTITY`), notarization in CI, reproducible CI builds via GitHub secrets.
- [x] Dev HTTP surface gated behind `#if DEBUG` — Release binaries do not link Network or expose `localhost:9876`.
- [x] Disappearing drawings (auto-fade) — opt-in toolbar toggle (clock glyph). 10s solid + 2s linear fade, then `editor.clear()` in one undoable op. `Sources/Core/Control/AppController.swift` owns the state machine; `Sources/AppKit/TimerFadeTicker.swift` drives the 30Hz tick.
- [x] Active-app keyboard shortcuts — `1`-`8` (color), `s` / `Shift+S` (size), `o` / `Shift+O` (opacity), `h` (hide), `f` (auto-fade), `Delete` (clear). Pure-Core `KeyCommandRegistry` is the source of truth, dispatched by `Sources/AppKit/KeyMonitor.swift`. Discoverable via toolbar tooltips and the menubar "Drawing" submenu.
- [x] Canvas follows the toolbar to whichever monitor it lives on. `NSWindow.didChangeScreenNotification` observer on the toolbar panel relocates the full-screen canvas; drawings clear on monitor switch (one-`Cmd+Z` restores at original coordinates).
- [x] Tool system — pen / selection / text as a `currentTool` orthogonal to `Mode`. Shortcuts `p` (pen), `t` (text), `Space` (press-and-hold for selection, restores the prior tool on release); pen/text toolbar buttons indicate the active tool. `Sources/Core/Model/Tool.swift`, `KeyCommandRegistry`, `Sources/AppKit/KeyMonitor.swift`, `Sources/AppKit/ToolbarController.swift`.
- [x] Selection tool — click / `Cmd`-click / drag-marquee to select; drag the body to translate, corner handles to scale, the rotation node to rotate (`Shift` snaps 15°); `Delete` erases the selection (one undoable op), `Delete` with no selection still clears all. Core math in `Sources/Core/Selection/` (`SelectionMath`, `SelectionTransforms`, `OrientedBox`); gesture routing in `Sources/Core/Control/AppController+SelectionGesture.swift`; chrome in `Sources/AppKit/CanvasView.swift`. `Editor` gained item-generic `transformItems` / `eraseItems`.
- [x] Text tool — `t` places a caret; type to set text in the current color/size (Helvetica, `Shift+Return` for newlines, `Return` commits); click existing text to edit. Text is a first-class `CanvasItem` so it selects/moves/rotates/resizes like strokes. Layout bounds are frozen at commit via the `TextMeasuring` port (see `docs/architecture.md` "Text geometry"). `Sources/Core/Model/{CanvasItem,TextItem}.swift`, `Sources/Core/Control/AppController+TextTool.swift`, `Sources/AppKit/CoreTextMeasurer.swift`.
- [x] Restyle the selection — with the selection tool and a live selection, the color/size/opacity shortcuts (`1`-`8`, `s` / `Shift+S`, `o` / `Shift+O`) retarget the selected items instead of the drawing defaults (text re-measured via the port), one undo step each. `Sources/Core/Control/AppController+Commands.swift`.
- [x] App icon — Icon Composer `fiti.icon` wired via `project.yml` (`ASSETCATALOG_COMPILER_APPICON_NAME`). The menubar status item keeps its SF Symbol glyph by design — SF Symbols are fine in the menu bar but not licensed for app icons.

## Open: visibility & interaction

### Global hide/show hotkey
- [ ] Toolbar already has a hide/show button; need a system-wide hotkey so you can toggle visibility without going through the toolbar. Default: `Opt+H`. Wire through `KeyboardShortcuts.Name.toggleDrawingsVisible` so it gets the same rebind-in-Preferences treatment as the activation hotkey.
- [ ] `Opt+H` in most apps types the `˙` combining-diacritic. That character is rarely needed in normal typing; rebinding is the escape hatch for anyone who does need it.
- [ ] Fall-through when there's nothing to hide: if `editor.doc.itemOrder.isEmpty`, the hotkey should *not* intercept the keystroke — pass it through so apps still see `Opt+H` and the `˙` character types normally. Only swallow the event when there's actually something to toggle.
  - Implementation tension: `KeyboardShortcuts` is Carbon-backed (`RegisterEventHotKey`), which always intercepts at the OS level — there's no "decline" return code. Two options to get fall-through: (a) after receiving the event, re-synthesise and post the original keypress via `CGEventPost` when we want to "let it through" — gross but doesn't need extra entitlements; (b) bypass the library for this one binding and use a `CGEventTap` (needs Accessibility permission in System Settings → Privacy & Security). Option (a) is the lower-friction default; revisit if it has noticeable latency or feels janky.
- [ ] The hotkey works regardless of fiti's activation state — it's purely about whether marks are rendered. Activating fiti is still `Opt+F`.

### Reserved keyboard slot
- [ ] `e`: eraser tool, when "Eraser as a UI tool" (below) ships. Deliberately absent from `KeyCommandRegistry` today; the registry's tests assert it resolves to `nil` so a binding can't be added silently. (`t`, `p`, and `Space` were reserved here too and have since shipped.)

## Open: stroke rendering & tools

### Flatten overlapping same-opacity marks
- [ ] Two 50%-opacity strokes that cross currently darken at the intersection (`1 − 0.5×0.5 = 0.75` coverage) because each is composited source-over with its own alpha. We want the union of same-opacity marks to read as one flat mark, so a `+` drawn at 50% looks uniformly 50% everywhere.
- [ ] Fix is the "flatten, then composite once" trick (how highlighter layers work): render the union of a group's shapes at full opacity into an offscreen, then blit that offscreen once at the target alpha. Overlap is absorbed into the union.
- [ ] Grouping: group committed items by exact `RGBA`, flatten each group, composite groups in z-order. Same-color marks merge; different colors still layer naturally. Known v1 edge: two *different* opacities of the same hue overlapping would need a per-pixel `max` blend — out of scope for v1, group by full RGBA.
- [ ] Pipeline impact: this breaks the current per-item bake cache (`BakeSignatureEntry` per stroke), since a stroke's appearance now depends on its neighbors. Move to a per-color-group offscreen cache, re-baked when any group member changes (fine at annotation-scale stroke counts). Auto-fade global opacity stays a final multiplier over the composited result (and stops double-darkening under fade). Decide: in-progress live stroke probably accepts a transient seam where it crosses committed same-color marks until commit; default-on vs. a toggle (leaning default — the darkening reads as a bug).

### Perfect-freehand option sliders
- [ ] v1 ships with `smoothing/thinning/streamline = 0.5` and `simulatePressure: true` hardcoded. Promote one or more to toolbar sliders only if real use reveals the defaults feel wrong (too laggy, too jittery, taper too aggressive). Likely candidates if anything turns out wrong: a single "smoothness" slider scaling `smoothing + streamline` together, then `thinning` if the velocity-taper feels off.

### Shape tools (rect, ellipse, arrow)
- [ ] Each new shape becomes a `CanvasItem` case (e.g. `.arrow(ArrowItem)`, `.rect(RectItem)`), **not** a `Stroke` with a `kind` discriminator — the `CanvasItem` sum type added with the text tool was built for exactly this. A new case gets selection, move/rotate/resize, and the color/size/opacity shortcuts essentially for free; render path switches on the case; hit-test/bounds grow a per-case branch in `SelectionMath`.

#### Arrow tool
- [ ] Activate with `a`; drag tail → head to place a clean arrow. Arrowhead is computed from the shaft direction (two barbs at ±~30°, length proportional to width). Bounds are exact and cheap from the endpoints — no measuring port needed (unlike text).
- [ ] Recommended over gesture-detection. The shaft can reuse the hold-to-straighten/reorient gesture so it feels like the pen, straight-by-default.
- [ ] Deferred alternative — *detect* a hand-drawn arrowhead on the end of a line and convert it to a real arrow (Notability-style). Punted because "did the user draw an arrowhead?" is fuzzy shape recognition with a high false-positive cost; build the `ArrowItem` primitive first, layer detection on later if wanted.
- [ ] Open design questions: single vs. double-headed; filled triangle vs. open "V" head; does the head scale with width; curved arrows (lean no for v1, straight only).

### Eraser as a UI tool
- [ ] A `.eraser` tool whose pointer finds the topmost item under it and erases it. The hit-test helper now exists (`SelectionMath.hitTestItem`, shared with the selection tool) and `Editor.eraseItems` is in place — the data path already works via HTTP, so this is mostly a tool-routing + cursor surface. Activate with `e` (see reserved slot above).

## Open: distribution & polish

### Persistence
- [ ] Strokes don't survive app restart. For real daily-driver usage we probably want a session that persists, with a "clear" that's separate from "quit." Could be as simple as JSON-encoding `FitiDoc` to `~/Library/Application Support/fiti/session.json` on every change. Needs a versioned doc shape so future schema changes are migratable.
- [ ] Open question: persistence of toolbar position, hide-state, opacity — already in UserDefaults under `fiti.*` keys; doc persistence is a separate concern.

### Multi-display
- Shipped (0.3.0): the canvas window follows whichever monitor hosts the toolbar. One display at a time; strokes clear on a monitor switch.
- [ ] Richer version: one canvas per display, all sharing the same `Editor`. Strokes get a `displayId` or get coordinates resolved to a global space — open design question. Affects how the selection tool's marquee behaves across displays.

## Code-level cleanup (not features)

- [ ] `Sources/DevHTTP/DevHTTPServer.swift:12` — `@unchecked Sendable` is a Swift-6 concession. Proper fix: make `DevHTTPServer` an actor, or replace the `start()` busy-wait with a semaphore signaled from the NWListener state handler. Resolves the `boundPort` data race in the same step.

## Out of scope (deliberately not on this list)

These are punted, not forgotten, but I'm not planning to revisit them soon:

- Pen / touch / iPad input
- Automerge / CRDT sync (the doc shape is ready; nothing else is)
- Cloud sync, accounts, sharing
- iOS / iPadOS port
- A web companion

## Open questions worth answering before picking anything up

1. **What's the upgrade story when the document shape changes?** Persistence implies versioned doc; we should pick that scheme before writing the first version to disk.
2. **Do we want a "presentation mode" preset?** One hotkey that activates, hides all previous marks, and resets the color/width to defaults — useful for "start a fresh annotation pass." Now actionable: keyboard shortcuts and disappearing drawings both ship.
