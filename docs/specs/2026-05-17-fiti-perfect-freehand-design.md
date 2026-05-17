# fiti Perfect-Freehand Swift Port — Design

Date: 2026-05-17
Status: Design. Implementation plan to follow.

## Goal

Replace fiti's uniform-width `CGPath` strokes with [perfect-freehand](https://github.com/steveruizok/perfect-freehand)'s tapered, velocity-aware curves. Strokes go from looking like pixel-art lines to looking like ink. Algorithm is ported to Swift as a standalone, MIT-licensed local Swift package inside the fiti repo, with byte-parity tests against the original TypeScript implementation.

## Background

The POC's CanvasView strokes a `CGPath` via `addLine` for every point — every segment is the same width. This works for proof-of-concept but reads as "first-pass software" because real ink and pencil strokes vary width with pressure and velocity.

perfect-freehand (Steve Ruiz, MIT) is a ~600-line TypeScript library that takes an array of input points and produces a closed polygon representing a tapered stroke outline. The `simulatePressure: true` option synthesizes pressure from velocity, so even mouse-drawn strokes get natural-feeling tapers at start and end. The scratch POC at `../scratch/scratch/packages/web/src/canvas/strokePath.ts` validated the look-and-feel with these defaults: `{ smoothing: 0.5, thinning: 0.5, streamline: 0.5, simulatePressure: true, taper: 0, cap: true }`. fiti adopts the same defaults.

## Scope

**In v1:**
- Full 1:1 port of perfect-freehand's `getStroke` API and all its dependencies
- New local Swift package at `Packages/PerfectFreehand/`
- Cross-language byte-parity tests via TS-generated fixtures
- Renderer cutover: CanvasView fills polygons instead of stroking paths
- Hardcoded defaults matching scratch's options; no toolbar exposure of perfect-freehand parameters

**Deferred (in roadmap):**
- Exposing `smoothing` / `thinning` / `streamline` via toolbar widgets (if defaults turn out to feel wrong)
- Real pressure values from trackpad / stylus input (today: mouse only, simulatePressure handles it)
- Promotion of `Packages/PerfectFreehand/` to its own public GitHub repo + SPM registry entry
- Performance benchmarks beyond a sanity-check timing test

## Architecture

### Local Swift Package

Lives at `Packages/PerfectFreehand/` inside the fiti repo. fiti's `project.yml` declares it as a local SPM dependency; Core imports `PerfectFreehand` for the algorithm. The package has no AppKit/CoreGraphics/Network dependencies — pure-Swift math, suitable for any SPM consumer.

Layout:

```
Packages/PerfectFreehand/
├── Package.swift
├── README.md                          (mirrors TS README; "ported from" note)
├── LICENSE                            (verbatim upstream MIT)
├── Sources/PerfectFreehand/
│   ├── GetStroke.swift                (public entry — equivalent to TS getStroke)
│   ├── GetStrokePoints.swift          (point sampling, streamline)
│   ├── GetStrokeOutlinePoints.swift   (outline polygon construction)
│   ├── GetStrokeRadius.swift          (per-point radius from pressure + thinning)
│   ├── SimulatePressure.swift         (velocity → synthesized pressure)
│   ├── Vec.swift                      (2D vector ops)
│   ├── Constants.swift
│   └── Types.swift                    (StrokeOptions, TaperOptions, StrokeInputPoint)
└── Tests/PerfectFreehandTests/
    ├── FixtureTests.swift             (byte-parity against TS-generated JSON)
    ├── PropertyTests.swift            (invariants: closed polygon, symmetry, etc.)
    ├── VecTests.swift                 (per-function unit tests, mirrors TS test suite)
    ├── GetStrokePointsTests.swift
    ├── GetStrokeOutlinePointsTests.swift
    ├── GetStrokeRadiusTests.swift
    ├── SimulatePressureTests.swift
    └── Fixtures/
        ├── regenerate.ts              (bun-run TS script that generates the fixtures)
        ├── package.json               (declares packageManager: bun@<version>)
        ├── basic-line.json
        ├── long-curve.json
        ├── closed-loop.json
        ├── ...                        (15 fixtures total — see Testing Strategy)
```

### Naming and Attribution

Each Swift source file mirrors its TS counterpart's name 1:1 (`getStroke.ts` → `GetStroke.swift`) so the port traces cleanly. Every Swift file starts with:

```swift
// ABOUTME: Ported from perfect-freehand@<version>/<source.ts> (MIT, Steve Ruiz).
// ABOUTME: <one-line description of what this file does>
```

The full upstream MIT LICENSE text is checked in verbatim at `Packages/PerfectFreehand/LICENSE`. fiti's ONBOARDING.md gains a one-line acknowledgments entry pointing at the package's LICENSE.

### Future Promotion

When the package is stable and we want to publish it independently:

```
git subtree split --prefix=Packages/PerfectFreehand -b perfect-freehand-swift
# push the new branch to its own repo
```

Then fiti's `Package.swift` changes the reference from `path:` to `url:`. No code changes inside the package. This is a one-way decision deferred to when stability is established.

## Algorithm Scope

Port the complete public API surface 1:1:

| TS source | Swift port | Responsibility |
|-----------|-----------|----------------|
| `getStroke.ts` | `GetStroke.swift` | Top-level entry: input points + options → polygon vertices |
| `getStrokePoints.ts` | `GetStrokePoints.swift` | Streamline-aware input sampling, distance filtering |
| `getStrokeOutlinePoints.ts` | `GetStrokeOutlinePoints.swift` | Builds left + right offset polygons, joins, caps, tapers |
| `getStrokeRadius.ts` | `GetStrokeRadius.swift` | Per-point radius from pressure + thinning + easing |
| `simulatePressure.ts` | `SimulatePressure.swift` | Velocity → synthesized pressure for non-stylus input |
| `vec.ts` | `Vec.swift` | 2D vector math (add, sub, scale, dot, perpendicular, etc.) |
| `constants.ts` | `Constants.swift` | π fractions, default option values |
| `types.ts` | `Types.swift` | `StrokeOptions`, `TaperOptions`, `StrokeInputPoint` protocol |

### StrokeOptions

Mirrors the TS `StrokeOptions` exactly so fixture-parity is achievable:

```swift
public struct StrokeOptions: Sendable {
    public var size: Double = 8
    public var thinning: Double = 0.5
    public var smoothing: Double = 0.5
    public var streamline: Double = 0.5
    public var simulatePressure: Bool = true
    public var easing: (@Sendable (Double) -> Double)? = nil
    public var start: TaperOptions = .init()
    public var end:   TaperOptions = .init()
    public var last:  Bool = false
}

public struct TaperOptions: Sendable {
    public var taper: TaperValue = .auto    // .none / .auto / .length(Double)
    public var cap: Bool = true
    public var easing: (@Sendable (Double) -> Double)? = nil
}

public enum TaperValue: Sendable, Equatable {
    case none
    case auto
    case length(Double)
}
```

### StrokeInputPoint and Point2D

TS accepts `[number, number]`, `[number, number, number]`, or `{x, y, pressure?}`. The Swift port standardizes on a protocol for inputs and a concrete struct for outputs:

```swift
public protocol StrokeInputPoint {
    var x: Double { get }
    var y: Double { get }
    var pressure: Double? { get }
}

public struct Point2D: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
```

`getStroke` returns `[Point2D]` — a closed polygon's vertices. The TS reference returns `number[][]` (array of `[x, y]` pairs); the fixture JSON uses that shape too, and tests decode it as `[[Double]]` then convert to `[Point2D]` before comparing.

The package provides one default input-conforming type (`InputPoint`) plus conformances for `CGPoint` (when AppKit is available — guarded by `#if canImport(CoreGraphics)`) and `(Double, Double)` tuples via a helper. fiti's `StrokePoint` conforms in a Core-side extension; perfect-freehand types never leak into fiti's doc model.

### Easing Closures

`StrokeOptions.easing` and `TaperOptions.easing` are `((Double) -> Double)?` and default to `nil`, which means "use the built-in linear easing." JSON fixtures cannot serialize closures, so v1 fixtures never pass a custom easing — they exercise the linear default only. Custom easing is a real public API surface (consumers can still pass closures from Swift), but cross-language byte parity for non-linear easings is out of scope for v1 fixtures. Property tests can cover the closure-call-path with simple inline closures.

### Numeric Type

`Double` throughout (TS `number` is double). Considered `CGFloat`; rejected because the package must stay AppKit-free for SPM portability, and `CGFloat == Double` on 64-bit anyway.

### Out of Scope

- The TS package's CSS/HTML conveniences (none — pure-math package)
- The benchmark suite (upstream `bench/` is dev-only)
- The dev viewer app (`packages/dev/`)

## fiti Integration

### No Stroke or StrokePoint Changes

The doc model already records what perfect-freehand needs: input points, base width, and a `pressureEnabled` flag. Per the render-time computation decision, no `bakedPolygon` field is added; the polygon is derived state, never persisted.

### Conformance Extension

```swift
// Sources/Core/Rendering/StrokePoint+PerfectFreehand.swift
import PerfectFreehand

extension StrokePoint: StrokeInputPoint {
    public var pressure: Double? { nil }
}
```

`nil` (not `0.5`) is intentional — it lets `simulatePressure: true` synthesize from velocity. Passing a constant would kill the taper.

### Options Wrapper

```swift
// Sources/Core/Rendering/FitiStrokeOptions.swift
import PerfectFreehand

enum FitiStrokeOptions {
    static func make(width: Double, last: Bool) -> StrokeOptions {
        var opts = StrokeOptions()
        opts.size = width
        opts.thinning = 0.5
        opts.smoothing = 0.5
        opts.streamline = 0.5
        opts.simulatePressure = true
        opts.start = TaperOptions(taper: .none, cap: true)
        opts.end   = TaperOptions(taper: .none, cap: true)
        opts.last = last
        return opts
    }
}
```

This is the single tuning surface. If a default turns out wrong in practice, it changes here. The roadmap's "expose options later" item becomes "promote one of these constants to a UserDefaults-backed Toolbar slider."

### CanvasView Render Path

Today `drawStroke(_ stroke:, in:, isInProgress:)` builds a `CGPath` via `addLine` and strokes it. The new shape:

```swift
let opts = FitiStrokeOptions.make(width: stroke.width, last: !isInProgress)
let polygon = getStroke(points: stroke.points, options: opts)
let path = CGMutablePath()
path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
for v in polygon.dropFirst() { path.addLine(to: CGPoint(x: v.x, y: v.y)) }
path.closeSubpath()
ctx.setFillColor(/* stroke.color → CGColor */)
ctx.addPath(path)
ctx.fillPath()
```

Three behavioral facts:

1. `last: false` for the in-progress stroke — perfect-freehand handles the trailing-point geometry differently for live preview so the tail doesn't snap visually on every move.
2. `last: true` for committed strokes — produces their final shape.
3. The two-canvas split's bake cache invalidation key already keys on the stroke array's signature, so the algorithm runs once per committed-stroke change, not on every redraw.

### What Stays Unchanged

- HTTP `/doc`, `/state`, `/snapshot.png` payloads — they serialize inputs, not polygons. `/snapshot.png` renders through the same code path as on-screen, so it reflects the new look.
- Menubar, toolbar, all keyboard shortcuts.
- Editor model and InverseOp stack — strokes are still identity-bearing, still undoable.

## Testing Strategy

### Layer 1 — Fixture-Driven Byte Parity (`FixtureTests`)

Each fixture is a checked-in JSON file containing `{name, input, options, expected}`. Tests load the file, run the Swift `getStroke` with the same input + options, and assert each output vertex matches `expected` within `abs ≤ 1e-9` per component.

```json
{
  "name": "basic-line",
  "input": [[10, 10, 0.5], [50, 10, 0.5], [90, 10, 0.5]],
  "options": { "size": 8, "thinning": 0.5, "smoothing": 0.5,
               "streamline": 0.5, "simulatePressure": true,
               "start": { "taper": 0, "cap": true },
               "end":   { "taper": 0, "cap": true },
               "last": true },
  "expected": [[9.21, 5.43], [10.55, 4.81], ...]
}
```

**Fixture coverage (15 scenarios):**

| Category | Scenarios |
|----------|-----------|
| Topology | basic-line, long-curve, closed-loop, zigzag, single-point (dot), two-points |
| Pressure | constant-pressure, varying-pressure, no-pressure-simulate-true, no-pressure-simulate-false |
| Options | streamline-0, streamline-1, thinning-0, thinning-1, taper-aggressive |
| Edge cases | empty-input, two-identical-points, very-small-size |

(Slight overlap: "empty-input" and "two-identical-points" share the edge-case bucket — total still ~15 once consolidated.)

### Layer 2 — Property Tests (`PropertyTests`)

Swift-side invariants that must hold regardless of fixture:

- Empty input → empty output.
- Single-point input → small closed circle around that point.
- Output polygon closed (vertex count ≥ 3; last segment connects back to first).
- Straight horizontal line → output symmetric about its centerline (every left vertex has a mirror right vertex).
- Scaling `size` by N scales the polygon radius from centerline by N (all other options fixed).
- `last: false` and `last: true` produce different last-region geometry (preview vs final).
- Output polygon doesn't self-intersect for a strictly monotonic input (straight line, no doubling back).

### Layer 3 — fiti Integration Test (one test in `Tests/AppKitTests/`)

Renders a single stroke through the new CanvasView path and asserts the rendered bitmap has non-zero pixels in a known region. Extends the existing `CanvasViewBakeTests` pattern. Doesn't re-test perfect-freehand internals — verifies the wire-up.

### Fixture Regeneration via bun

A short TypeScript script lives at `Packages/PerfectFreehand/Tests/Fixtures/regenerate.ts`. It imports the upstream perfect-freehand npm package, runs each scenario, and writes the `expected` array to its JSON file. **bun runs it; node is not used.** Fixtures are checked into git. The script is dev-only — runtime never sees bun, npm, or any Node-shaped tooling.

```just
[private]
ensure-bun:
    @command -v bun >/dev/null 2>&1 || { \
        echo "bun is required to regenerate PerfectFreehand fixtures."; \
        echo "Install with: brew install bun"; \
        exit 1; }

[group('pf')]
install-pf-deps: ensure-bun
    @cd Packages/PerfectFreehand/Tests/Fixtures && bun install

[group('pf')]
regen-pf-fixtures: install-pf-deps
    @cd Packages/PerfectFreehand/Tests/Fixtures && bun run regenerate.ts
```

`ensure-bun` is `[private]` so it doesn't clutter `just --list`. Contributors without bun get one clean install hint instead of a `command not found`. CI never touches bun because fixtures are committed.

### Test Target Wiring

The package's test target runs via `swift test --package-path Packages/PerfectFreehand`. Because `xcodebuild test` on fiti doesn't automatically run SPM downstream tests, `just test` and `just check` get an explicit step:

```just
test: generate
    xcodebuild ... fiti-unit ...
    swift test --package-path Packages/PerfectFreehand
```

Same for `test-integration`. The new `swift test` step is fast (the package's tests don't touch AppKit), so it doesn't materially extend CI time.

### Performance Sanity Check (Not Gating)

One test inside `PerfectFreehandTests` times `getStroke` on a 1000-point input and prints the duration. If it's > 50 ms, that's a real signal worth chasing. Sanity-only — not a fail condition for CI.

## Migration Plan

No feature flag and no parallel renderer kept around. Package builds and ships unused until the final cutover commit, at which point the renderer switches over and the old `addLine` code is deleted.

Eleven commits, each green at HEAD:

| # | Commit | Surface |
|---|--------|---------|
| 1 | Bootstrap package: `Packages/PerfectFreehand/Package.swift`, stub `getStroke` returning `[]`, LICENSE, README, project.yml SPM dependency added. fiti builds + tests still pass. | Setup |
| 2 | Fixture infrastructure: `regenerate.ts`, `install-pf-deps` / `regen-pf-fixtures` / `ensure-bun` justfile recipes, `package.json` declaring `packageManager: bun@<version>`. No fixtures generated yet. | Infrastructure |
| 3 | Port `Vec.swift` — vector ops with Swift unit tests (add, sub, scale, dist, dot, perpendicular, lrp, etc.) | Math primitives |
| 4 | Port `Constants.swift` + `Types.swift` (StrokeOptions, TaperOptions, StrokeInputPoint protocol) | Public types |
| 5 | Port `SimulatePressure.swift` with Swift unit tests | Pressure synthesis |
| 6 | Port `GetStrokeRadius.swift` with Swift unit tests + easing-function support | Width modulation |
| 7 | Port `GetStrokePoints.swift` with Swift unit tests | Input sampling |
| 8 | Port `GetStrokeOutlinePoints.swift` with Swift unit tests | Outline polygon |
| 9 | Port `GetStroke.swift` composing all of the above + first 8 fixtures (basic-line, long-curve, closed-loop, single-point, two-points, zigzag, varying-pressure, no-pressure-simulate-true). FixtureTests assert byte-parity within `abs ≤ 1e-9`. | Composition + cross-language validation |
| 10 | Remaining ~7 fixtures (streamline-0/1, thinning-0/1, taper-aggressive, edge cases) + PropertyTests covering all the invariants. | Coverage breadth |
| 11 | The cutover: add `StrokePoint+PerfectFreehand.swift`, `FitiStrokeOptions.swift`, change `CanvasView.drawStroke` to call `getStroke` and fill the polygon. Remove the old `addLine` code. Add the AppKit integration test. Update ONBOARDING (license attribution + regen-fixtures note). Mark the roadmap item done. | Renderer swap + cleanup |

Per-step TDD invariants:

- Each port commit (3–8) writes failing Swift unit tests first, mirroring the TS source's `test/*.test.ts` cases where they exist.
- Steps 9 and 10 add cross-language fixture tests — proof that the math composes correctly.
- Step 11 is atomic: one diff carries the visible before/after.

Execution: same pattern as toolbar — dispatch one implementer subagent per commit via the subagent-driven-development workflow. Math-heavy ports (6–8) get extra care; mechanical commits (1–4) are cheap. After all eleven land, one final code-review pass plus memory updates if anything surprising surfaced.

Estimated effort: 11 commits, each ~30–60 minutes of subagent work. Roughly half a focused session end-to-end.

## Decisions Log

- **Standalone Swift Package vs. inside `Sources/Core/`.** Standalone forces clean API discipline (the package can't reach into fiti internals), keeps Core focused, and leaves room for community publication. Promotion to its own repo later is a `git subtree split` plus URL change.
- **Render-time vs. commit-time polygon computation.** Render-time keeps the doc model a clean record of inputs. The bake cache amortizes cost for committed strokes; in-progress recomputation per frame is well within the JS reference's budget, so the Swift port has headroom.
- **Hide all perfect-freehand options for v1.** Ship the scratch defaults. Iterate if any default feels wrong in practice. Backlog has a follow-on item to promote individual constants to toolbar widgets if needed.
- **1:1 TS API mirror.** Required for fixture byte-parity testing. A Swiftier wrapper API can layer on later.
- **bun, not node.** One binary, no version managers; bun runs TypeScript natively. All bun calls are wrapped in justfile recipes; recipes detect missing bun with a friendly hint.
- **No feature flag for the cutover.** YAGNI; we're confident in the look, the algorithm is well-validated, and an atomic cutover commit tells the cleanest story in the diff.

## Open Questions / Future Work

- **Real pressure input.** Today the port carries pressure through (the protocol has `var pressure: Double?`) but fiti's mouse-driven `StrokePoint` returns nil. When we wire up a trackpad/stylus input adapter, populate the field; perfect-freehand's `thinning` already handles real pressure.
- **Toolbar exposure of options.** If `streamline: 0.5` feels laggy or `thinning: 0.5` looks wrong, promote that constant to a Toolbar slider. Backlog entry exists.
- **Promote PerfectFreehand to its own repo.** When stable and we have a use case beyond fiti. Mechanical when ready.
- **Two-canvas retina detail.** Existing code-cleanup item in the roadmap. Becomes more visible once strokes have real curvature; worth addressing in the same wave or shortly after.
