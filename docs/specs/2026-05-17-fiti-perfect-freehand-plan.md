# fiti perfect-freehand Swift Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port perfect-freehand 1.2.3 (Steve Ruiz, MIT) from TypeScript to Swift as a local SPM package at `Packages/PerfectFreehand/`, validated against the upstream TS reference via checked-in JSON fixtures, then cut over fiti's `CanvasView` from uniform-width `CGPath` strokes to polygon-fill rendering.

**Architecture:** Standalone Swift package, AppKit-free, mirroring the TS public API 1:1 for fixture byte-parity. Output type `Point2D`; input via `StrokeInputPoint` protocol; `StrokeOptions` and `TaperOptions` structs mirror the TS option shapes. fiti consumes the package via xcodegen's local SPM mechanism. Renderer cutover atomic in the final commit. Fixture regeneration tooling uses `bun` (wrapped in just recipes) — runtime never sees bun or node.

Full design context: [`2026-05-17-fiti-perfect-freehand-design.md`](./2026-05-17-fiti-perfect-freehand-design.md). When in doubt, the design spec wins.

**Tech Stack:** Swift 6 (strict concurrency), SPM, Swift Testing, AppKit (consumer only), bun (dev-time fixture regen only).

**Upstream reference:** Local clone at `.llm/perfect-freehand/`. Algorithm source is at `.llm/perfect-freehand/packages/perfect-freehand/src/`. TS tests at `.llm/perfect-freehand/packages/perfect-freehand/src/test/`.

---

## File structure overview

**Create (in `Packages/PerfectFreehand/`):**

```
Packages/PerfectFreehand/
├── Package.swift
├── README.md                          (mirrors TS README; "ported from 1.2.3" note)
├── LICENSE                            (verbatim copy of .llm/perfect-freehand/LICENSE)
├── Sources/PerfectFreehand/
│   ├── GetStroke.swift                (public entry — `getStroke(points:options:) -> [Point2D]`)
│   ├── GetStrokePoints.swift
│   ├── GetStrokeOutlinePoints.swift
│   ├── GetStrokeRadius.swift
│   ├── SimulatePressure.swift
│   ├── Vec.swift                      (2D vector ops, internal-package)
│   ├── Constants.swift                (RATE_OF_PRESSURE_CHANGE, FIXED_PI etc.)
│   └── Types.swift                    (StrokeOptions, TaperOptions, TaperValue, Point2D, StrokeInputPoint)
└── Tests/PerfectFreehandTests/
    ├── FixtureTests.swift             (byte-parity against TS-generated JSON, abs ≤ 1e-9)
    ├── PropertyTests.swift            (closed polygon, symmetry, scale linearity, etc.)
    ├── VecTests.swift
    ├── GetStrokePointsTests.swift
    ├── GetStrokeOutlinePointsTests.swift
    ├── GetStrokeRadiusTests.swift
    ├── SimulatePressureTests.swift
    └── Fixtures/
        ├── regenerate.ts              (bun-run, generates JSON fixtures from upstream)
        ├── package.json               (declares packageManager: bun@<version>)
        ├── tsconfig.json
        ├── basic-line.json
        ├── long-curve.json
        ├── closed-loop.json
        ├── zigzag.json
        ├── single-point.json
        ├── two-points.json
        ├── varying-pressure.json
        ├── no-pressure-simulate-true.json
        ├── no-pressure-simulate-false.json
        ├── constant-pressure.json
        ├── streamline-0.json
        ├── streamline-1.json
        ├── thinning-0.json
        ├── thinning-1.json
        ├── taper-aggressive.json
        ├── empty-input.json
        ├── two-identical-points.json
        └── very-small-size.json
```

**Modify:**
- `project.yml` — declare local SPM dependency
- `justfile` — `just test`, `just test-integration`, `just check` each add a `swift test --package-path` step; new `[group('pf')]` recipes for fixture regen
- `Sources/AppKit/CanvasView.swift` — renderer cutover in final commit
- `Sources/Core/Rendering/StrokePoint+PerfectFreehand.swift` (new) — protocol conformance bridge
- `Sources/Core/Rendering/FitiStrokeOptions.swift` (new) — central options wrapper
- `Tests/AppKitTests/` — one new integration test verifying polygon-fill produces non-zero pixels
- `ONBOARDING.md` — acknowledgments entry + regen-fixtures note
- `docs/specs/2026-05-16-fiti-roadmap.md` — tick the perfect-freehand item

---

## Task 1: Bootstrap the package (compiles, no logic)

**Files:**
- Create: `Packages/PerfectFreehand/Package.swift`
- Create: `Packages/PerfectFreehand/LICENSE`
- Create: `Packages/PerfectFreehand/README.md`
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/GetStroke.swift` (stub)
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/Types.swift` (minimal `Point2D` for the stub)
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/BootstrapTests.swift`
- Modify: `project.yml`
- Modify: `justfile`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerfectFreehand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerfectFreehand", targets: ["PerfectFreehand"])
    ],
    targets: [
        .target(name: "PerfectFreehand", path: "Sources/PerfectFreehand"),
        .testTarget(name: "PerfectFreehandTests",
                    dependencies: ["PerfectFreehand"],
                    path: "Tests/PerfectFreehandTests",
                    exclude: ["Fixtures"])
    ]
)
```

- [ ] **Step 2: Copy upstream LICENSE verbatim**

```bash
cp .llm/perfect-freehand/LICENSE Packages/PerfectFreehand/LICENSE
```

- [ ] **Step 3: Write `Packages/PerfectFreehand/README.md`**

```markdown
# PerfectFreehand (Swift)

Swift port of [perfect-freehand](https://github.com/steveruizok/perfect-freehand) 1.2.3 (MIT, Steve Ruiz).

Given an array of input points and a `StrokeOptions`, returns a closed polygon's vertices representing a tapered, velocity-aware stroke outline — suitable for filling on any 2D canvas.

```swift
import PerfectFreehand

var options = StrokeOptions()
options.size = 8
options.simulatePressure = true

let polygon: [Point2D] = getStroke(points: inputPoints, options: options)
```

See upstream README for option semantics. This port mirrors the TS public API 1:1; fixture-parity tests assert byte equivalence within `abs ≤ 1e-9`.

## License

MIT — see `LICENSE` (preserved from upstream).
```

- [ ] **Step 4: Stub `Types.swift`**

```swift
// ABOUTME: Ported from perfect-freehand@1.2.3/types.ts (MIT, Steve Ruiz).
// ABOUTME: Public types — StrokeOptions, TaperOptions, Point2D, StrokeInputPoint.

import Foundation

public struct Point2D: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public protocol StrokeInputPoint {
    var x: Double { get }
    var y: Double { get }
    var pressure: Double? { get }
}

public struct StrokeOptions: Sendable {
    public var size: Double = 8
    public init() {}
}
```

(StrokeOptions stays minimal here — the full set lands in Task 4. Just enough to compile.)

- [ ] **Step 5: Stub `GetStroke.swift`**

```swift
// ABOUTME: Ported from perfect-freehand@1.2.3/getStroke.ts (MIT, Steve Ruiz).
// ABOUTME: Top-level entry — composes the rest of the algorithm. Currently a stub.

import Foundation

public func getStroke<P: StrokeInputPoint>(points: [P], options: StrokeOptions = StrokeOptions()) -> [Point2D] {
    return []
}
```

- [ ] **Step 6: Write `BootstrapTests.swift`**

```swift
// ABOUTME: Smoke test that the package compiles and the public API is reachable.

import Testing
@testable import PerfectFreehand

@Suite("Bootstrap")
struct BootstrapTests {
    struct P: StrokeInputPoint {
        let x: Double; let y: Double; let pressure: Double?
    }

    @Test("getStroke is callable and returns an empty array (stub)")
    func empty() {
        let result = getStroke(points: [P](), options: StrokeOptions())
        #expect(result.isEmpty)
    }
}
```

- [ ] **Step 7: Declare the package in `project.yml`**

Add a top-level `packages` key (or extend the existing one if present) and add a dependency to `fiti`, `fiti-unit`, and `fiti-integration`:

```yaml
packages:
  PerfectFreehand:
    path: Packages/PerfectFreehand

targets:
  fiti:
    # ... existing settings ...
    dependencies:
      - package: PerfectFreehand
  fiti-unit:
    # ... existing settings ...
    dependencies:
      - package: PerfectFreehand
  fiti-integration:
    # ... existing settings ...
    dependencies:
      - package: PerfectFreehand
```

Read the current `project.yml` carefully before editing — the targets section uses inline `settings` blocks; add `dependencies:` alongside `settings:`. If `dependencies:` already exists for a target, append; do not replace.

- [ ] **Step 8: Add the new `swift test` step to justfile recipes**

In `justfile`, after the existing `xcodebuild ... fiti-unit` line in the `test` recipe, add a chained step:

```just
test: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} CODE_SIGN_IDENTITY="{{sign_identity}}"
    swift test --package-path Packages/PerfectFreehand
```

Same for `test-integration` (append the same `swift test --package-path` line) and the `check` recipe will pick it up transitively because `check: test test-integration lint build`.

- [ ] **Step 9: Run the full gate**

```bash
just generate
just check
```

Expected: 1 new test added (the bootstrap test), all existing tests still pass, lint clean, build succeeds.

- [ ] **Step 10: Commit**

```bash
git add Packages/PerfectFreehand project.yml justfile
git commit -m "$(cat <<'EOF'
Bootstrap PerfectFreehand local Swift package

Skeleton of the Swift port of perfect-freehand@1.2.3 (Steve Ruiz, MIT).
Package.swift declares a library target and test target. LICENSE
preserved verbatim from upstream. Stub getStroke returns [] so
fiti can link the package without behavior changes; real algorithm
lands across the next several commits.

project.yml gains a packages: entry and adds PerfectFreehand as a
dependency on fiti / fiti-unit / fiti-integration so all three see
the symbol. justfile's test and test-integration recipes gain a
`swift test --package-path Packages/PerfectFreehand` step so the
package's own tests run alongside fiti's xcodebuild test suite.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Fixture infrastructure (no fixtures yet)

**Files:**
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/regenerate.ts`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/package.json`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/tsconfig.json`
- Modify: `justfile` (add `ensure-bun` private, `install-pf-deps`, `regen-pf-fixtures`)
- Modify: `.gitignore` (ignore `node_modules/` under the Fixtures dir)

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "perfect-freehand-fixtures",
  "private": true,
  "type": "module",
  "packageManager": "bun@1.1.0",
  "dependencies": {
    "perfect-freehand": "1.2.3"
  }
}
```

Pin perfect-freehand to 1.2.3 — the version we're porting. Bumping requires conscious thought (and likely a Swift port update).

- [ ] **Step 2: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
```

- [ ] **Step 3: Write `regenerate.ts`**

```typescript
// ABOUTME: Regenerates JSON fixtures for the Swift PerfectFreehand port by
// ABOUTME: running the upstream TS implementation against fixed inputs.

import { getStroke, type StrokeOptions } from 'perfect-freehand'
import { writeFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

type FixtureFile = {
    name: string
    input: Array<[number, number] | [number, number, number]>
    options: StrokeOptions
    // `expected` is regenerated; whatever's in the file gets overwritten.
    expected?: number[][]
}

const files = readdirSync(here).filter(f => f.endsWith('.json') && f !== 'package.json' && f !== 'tsconfig.json')

for (const file of files) {
    const path = join(here, file)
    const fixture: FixtureFile = JSON.parse(await Bun.file(path).text())
    const polygon = getStroke(fixture.input, fixture.options)
    fixture.expected = polygon
    writeFileSync(path, JSON.stringify(fixture, null, 2) + '\n')
    console.log(`✓ ${file} — ${polygon.length} vertices`)
}
```

Note: this script regenerates the `expected` field on every `.json` file in the Fixtures dir. The `input` and `options` fields are hand-authored (added in Tasks 9 and 10); the script never touches them.

- [ ] **Step 4: Add the three justfile recipes**

Append to `justfile`:

```just
# ─── perfect-freehand fixture regen (dev-time only — runtime uses checked-in JSON) ───

# Private guard: bail with a friendly install hint if bun isn't available.
[private]
ensure-bun:
    @command -v bun >/dev/null 2>&1 || { \
        echo "bun is required to regenerate PerfectFreehand fixtures."; \
        echo "Install with: brew install bun"; \
        exit 1; }

[group('pf')]
install-pf-deps: ensure-bun
    @cd Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures && bun install

[group('pf')]
regen-pf-fixtures: install-pf-deps
    @cd Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures && bun run regenerate.ts
```

- [ ] **Step 5: Gitignore `node_modules` under the Fixtures dir**

Append to `.gitignore`:

```
Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/node_modules/
Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/bun.lock
Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/bun.lockb
```

- [ ] **Step 6: Sanity-check the just recipe (don't fail if bun is missing)**

```bash
just --list | grep pf
```

Expected: shows `install-pf-deps` and `regen-pf-fixtures` (and NOT `ensure-bun` since it's `[private]`). Do not actually run `regen-pf-fixtures` yet — there are no fixtures with `input`/`options` to regenerate. The recipe will be exercised first in Task 9.

- [ ] **Step 7: Run check**

```bash
just check
```

Expected: green (no new tests, no logic added). Just verifies the project.yml/justfile changes didn't break anything.

- [ ] **Step 8: Commit**

```bash
git add Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures justfile .gitignore
git commit -m "$(cat <<'EOF'
PerfectFreehand: fixture-regen infrastructure

Adds the regenerate.ts script (bun-run, TypeScript) that imports the
upstream perfect-freehand@1.2.3 npm package and rewrites the
"expected" field on each fixture JSON file from the TS implementation.
The "input" and "options" fields stay hand-authored; the script
only overwrites "expected".

justfile gets `install-pf-deps` and `regen-pf-fixtures` wrapped
around bun, with a private `ensure-bun` guard that prints a brew
install hint instead of `command not found` if bun is missing.

No fixtures are generated yet — that lands with Tasks 9 and 10.
gitignore covers node_modules and bun.lock(b) under the Fixtures dir.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Port `Vec.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/Vec.swift`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/VecTests.swift`

**TS source to port:** `.llm/perfect-freehand/packages/perfect-freehand/src/vec.ts`

- [ ] **Step 1: Read the TS source**

Read `.llm/perfect-freehand/packages/perfect-freehand/src/vec.ts`. Catalog every exported function. Each will be a `static func` on a Swift `enum Vec` (no instances; enum-as-namespace pattern). Operate on `[Double]` arrays of length 2 to match TS shapes exactly — internal algorithm uses arrays, not `Point2D`. `Point2D` is the public output type only.

- [ ] **Step 2: Write failing Swift unit tests**

Create `VecTests.swift`. There's no upstream `vec.spec.ts`, so write tests from first principles. Cover every exported TS function with at least:
- One positive case with concrete inputs and expected outputs
- One edge case (zero vector, identical points, etc. where applicable)

Use `#expect(a == b)` for exact match where the math admits exact doubles (add, sub, etc.); use a small-epsilon helper `expectClose(_ actual: Double, _ expected: Double, abs: Double = 1e-12)` for trig-involving cases.

- [ ] **Step 3: Run, expect failure**

```bash
swift test --package-path Packages/PerfectFreehand
```

Expected: build error or test failures (Vec doesn't exist).

- [ ] **Step 4: Port the TS to Swift**

Create `Vec.swift`. ABOUTME header:

```swift
// ABOUTME: Ported from perfect-freehand@1.2.3/vec.ts (MIT, Steve Ruiz).
// ABOUTME: 2D vector math — internal helpers used by the algorithm.
```

Then port every TS function as a `static func` on `enum Vec`. Mirror function names exactly (TS `add` → Swift `Vec.add`). Use `[Double]` arrays of length 2 throughout — do NOT use `Point2D` internally (Point2D is the public output type only).

Example shape (you fill in all the functions per the TS source):

```swift
import Foundation

enum Vec {
    static func add(_ A: [Double], _ B: [Double]) -> [Double] {
        return [A[0] + B[0], A[1] + B[1]]
    }
    static func sub(_ A: [Double], _ B: [Double]) -> [Double] {
        return [A[0] - B[0], A[1] - B[1]]
    }
    // ... mul, div, per, neg, len, len2, dist, dist2, dot, lrp, uni, etc.
}
```

`enum Vec` is `internal` (package-default access). It's only used by other PerfectFreehand files.

- [ ] **Step 5: Run, expect pass**

```bash
swift test --package-path Packages/PerfectFreehand
```

Expected: all Vec tests pass; bootstrap test still passes.

- [ ] **Step 6: Run full check**

```bash
just check
```

- [ ] **Step 7: Commit**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand/Vec.swift Packages/PerfectFreehand/Tests/PerfectFreehandTests/VecTests.swift
git commit -m "$(cat <<'EOF'
PerfectFreehand: port Vec (2D vector math)

Internal `enum Vec` namespace with static functions mirroring the TS
vec.ts 1:1 (add, sub, mul, div, per, neg, len, dist, dot, lrp, uni,
etc.). Operates on [Double] arrays of length 2 to match the TS array
shapes exactly so downstream algorithm files port cleanly.

VecTests covers each function with positive cases and edge cases
(zero vector, identical points). Upstream has no vec.spec.ts, so
tests are first-principles.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Port `Constants.swift` + finish `Types.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/Constants.swift`
- Modify: `Packages/PerfectFreehand/Sources/PerfectFreehand/Types.swift` (expand from Task 1's stub to the full options surface)

**TS sources:** `.llm/perfect-freehand/packages/perfect-freehand/src/constants.ts` and `.llm/perfect-freehand/packages/perfect-freehand/src/types.ts`

- [ ] **Step 1: Read both TS files**

`constants.ts` is tiny — port verbatim. `types.ts` contains the full StrokeOptions, TaperOptions, the `Easing` shape, etc. — port to Swift structs with `Sendable` and default values.

- [ ] **Step 2: No new tests required for Constants** (it's data) — but write a property test in `PropertyTests.swift` (create if missing) that asserts `StrokeOptions()` produces the documented default values, so future careless edits to defaults get caught.

- [ ] **Step 3: Write `Constants.swift`**

```swift
// ABOUTME: Ported from perfect-freehand@1.2.3/constants.ts (MIT, Steve Ruiz).
// ABOUTME: Numeric constants used by the algorithm (PI fractions, rate of pressure change, etc.).

import Foundation

enum PFConstants {
    // Port the TS constants verbatim. Match TS names with Swift conventions.
}
```

(Replace the comment with actual constants from `constants.ts`.)

- [ ] **Step 4: Expand `Types.swift`** to the full options surface

```swift
public enum TaperValue: Sendable, Equatable {
    case none
    case auto
    case length(Double)
}

public struct TaperOptions: Sendable {
    public var taper: TaperValue = .auto
    public var cap: Bool = true
    public var easing: (@Sendable (Double) -> Double)? = nil
    public init() {}
}

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
    public init() {}
}
```

Confirm the defaults match what perfect-freehand's `getStroke.ts` falls back to when options are omitted. Refer to the TS source's `??` defaults at the top of `getStroke.ts` — those are authoritative.

Keep `Point2D` and `StrokeInputPoint` from Task 1.

- [ ] **Step 5: Run, expect pass**

```bash
swift test --package-path Packages/PerfectFreehand
```

Plus the new PropertyTests assertion that `StrokeOptions()` produces the expected defaults.

- [ ] **Step 6: Run full check**

```bash
just check
```

- [ ] **Step 7: Commit**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand
git commit -m "$(cat <<'EOF'
PerfectFreehand: port Constants + finish Types

Constants.swift mirrors perfect-freehand@1.2.3/constants.ts verbatim.
Types.swift expands from the Task-1 stub to the full StrokeOptions /
TaperOptions / TaperValue surface, with defaults matching the TS
falls-throughs in getStroke.ts. Point2D and StrokeInputPoint unchanged
from Task 1.

PropertyTests.swift adds a defaults-assertion so accidental edits to
the default values get caught at test time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Port `SimulatePressure.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/SimulatePressure.swift`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/SimulatePressureTests.swift`

**TS source:** `.llm/perfect-freehand/packages/perfect-freehand/src/simulatePressure.ts` (or wherever it's exported from — search if not at that path).

- [ ] **Step 1: Locate and read the TS source.** simulatePressure is a function called inside `getStrokePoints.ts`; check whether it's a standalone file or inlined. If inlined, the Swift port still lives in its own file (`SimulatePressure.swift`) for clarity. The TS function takes the current pressure, current distance, current radius, and synthesizes the next pressure value from rate-of-change.

- [ ] **Step 2: Write failing tests.** First-principles cases: starting pressure (zero history) yields a sane starting value; pressure rises monotonically toward 1.0 as distance accumulates; pressure responsive to distance changes (faster = lower).

- [ ] **Step 3: Port the function**, in `SimulatePressure.swift`. Mirror TS signature exactly. Use the constants from Task 4.

- [ ] **Step 4: Run, expect pass**

```bash
swift test --package-path Packages/PerfectFreehand
```

- [ ] **Step 5: Run full check**

```bash
just check
```

- [ ] **Step 6: Commit**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand/SimulatePressure.swift Packages/PerfectFreehand/Tests/PerfectFreehandTests/SimulatePressureTests.swift
git commit -m "$(cat <<'EOF'
PerfectFreehand: port SimulatePressure

Velocity-to-pressure synthesis. Mirrors perfect-freehand@1.2.3's
implementation; uses PFConstants.RATE_OF_PRESSURE_CHANGE (or whatever
the upstream constant is named). Lets simulatePressure: true mode
produce velocity-aware tapers for non-stylus input.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Port `GetStrokeRadius.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokeRadius.swift`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokeRadiusTests.swift`

**TS source:** `.llm/perfect-freehand/packages/perfect-freehand/src/getStrokeRadius.ts`
**TS tests (mirror these):** `.llm/perfect-freehand/packages/perfect-freehand/src/test/getStrokeRadius.spec.ts`

- [ ] **Step 1: Read both TS files (source + tests).**

- [ ] **Step 2: Write failing Swift tests mirroring the TS test cases** in `GetStrokeRadiusTests.swift`. Use the same input + expected pairs from `getStrokeRadius.spec.ts` (translate from `expect(a).toEqual(b)` to `#expect(a == b)`; use `expectClose` for float cases).

- [ ] **Step 3: Port the function** to Swift. Signature mirrors TS exactly. Supports the `easing` closure from `StrokeOptions`.

- [ ] **Step 4: Run, expect pass.**

```bash
swift test --package-path Packages/PerfectFreehand
```

- [ ] **Step 5: Run full check.**

```bash
just check
```

- [ ] **Step 6: Commit.**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokeRadius.swift Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokeRadiusTests.swift
git commit -m "$(cat <<'EOF'
PerfectFreehand: port GetStrokeRadius

Per-point radius from pressure + thinning + easing. Mirrors
perfect-freehand@1.2.3/getStrokeRadius.ts. Tests translate the
upstream getStrokeRadius.spec.ts cases 1:1 into Swift Testing form.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Port `GetStrokePoints.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokePoints.swift`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokePointsTests.swift`

**TS source:** `.llm/perfect-freehand/packages/perfect-freehand/src/getStrokePoints.ts`
**TS tests:** `.llm/perfect-freehand/packages/perfect-freehand/src/test/getStrokePoints.spec.ts` (mirror these)

- [ ] **Step 1: Read both TS files.** This function does input sampling with streamline-aware averaging and produces an array of `StrokePoint` (internal-to-algorithm) with `{point, pressure, distance, vector, runningLength}` shape. Port that internal struct to Swift as an internal type (`InternalStrokePoint` or similar — distinct from fiti's `StrokePoint`; doesn't conflict because they're in different modules).

- [ ] **Step 2: Write failing Swift tests** mirroring `getStrokePoints.spec.ts`. The TS tests pass arrays of input points and assert specific properties of the output array (length, first/last point coordinates, etc.).

- [ ] **Step 3: Port the function** to Swift. Mirror signature exactly.

- [ ] **Step 4: Run, expect pass.**

```bash
swift test --package-path Packages/PerfectFreehand
```

- [ ] **Step 5: Run full check.**

```bash
just check
```

- [ ] **Step 6: Commit.**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokePoints.swift Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokePointsTests.swift
git commit -m "$(cat <<'EOF'
PerfectFreehand: port GetStrokePoints

Input sampling with streamline-aware averaging. Produces the internal
StrokePoint shape ({point, pressure, distance, vector, runningLength})
consumed by getStrokeOutlinePoints. Mirrors perfect-freehand@1.2.3/
getStrokePoints.ts. Tests translate upstream getStrokePoints.spec.ts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Port `GetStrokeOutlinePoints.swift`

**Files:**
- Create: `Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokeOutlinePoints.swift`
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokeOutlinePointsTests.swift`

**TS source:** `.llm/perfect-freehand/packages/perfect-freehand/src/getStrokeOutlinePoints.ts`
**TS tests:** `.llm/perfect-freehand/packages/perfect-freehand/src/test/getStrokeOutlinePoints.spec.ts` (mirror these)

This is the heaviest port. The function takes streamlined points (from Task 7) and produces the outline polygon — left and right offset curves joined at caps with optional tapers.

- [ ] **Step 1: Read both TS files carefully.** Note: this function uses every prior building block (Vec, GetStrokeRadius, SimulatePressure indirectly through GetStrokePoints, constants).

- [ ] **Step 2: Write failing Swift tests** mirroring the spec. The TS tests include both shape-checking and snapshot tests (`__snapshots__/getStrokeOutlinePoints.spec.ts.snap` in the upstream test dir). Skip the snapshots in this commit — they're inputs for the cross-language fixture work in Task 9.

- [ ] **Step 3: Port the function** to Swift. This is large — ~150 lines of TS. Take care to:
  - Mirror the TS branching structure exactly.
  - Preserve the comments from the TS source (they explain the math).
  - Use `Vec.*` static functions for vector ops.
  - Internal-package access; no public API beyond what `getStroke.ts` calls.

- [ ] **Step 4: Run, expect pass.**

```bash
swift test --package-path Packages/PerfectFreehand
```

- [ ] **Step 5: Run full check.**

```bash
just check
```

- [ ] **Step 6: Commit.**

```bash
git add Packages/PerfectFreehand/Sources/PerfectFreehand/GetStrokeOutlinePoints.swift Packages/PerfectFreehand/Tests/PerfectFreehandTests/GetStrokeOutlinePointsTests.swift
git commit -m "$(cat <<'EOF'
PerfectFreehand: port GetStrokeOutlinePoints

The outline-polygon construction step — takes streamlined points,
walks the centerline, emits left and right offset vertices,
joins them at caps with optional tapers. Heaviest port in the
package; mirrors perfect-freehand@1.2.3/getStrokeOutlinePoints.ts
including the source comments (the math is non-obvious).

Tests translate upstream getStrokeOutlinePoints.spec.ts shape and
property cases; snapshots are deferred to the cross-language
fixture work in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Port `GetStroke.swift` + first 8 fixtures

**Files:**
- Modify: `Packages/PerfectFreehand/Sources/PerfectFreehand/GetStroke.swift` (replace Task-1 stub with real composition)
- Create: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/FixtureTests.swift`
- Create: 8 JSON fixture files in `Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/`

**TS source:** `.llm/perfect-freehand/packages/perfect-freehand/src/getStroke.ts`
**TS tests:** `.llm/perfect-freehand/packages/perfect-freehand/src/test/getStroke.spec.ts`

- [ ] **Step 1: Read the TS source for `getStroke`** — it's the composition root: feeds input through getStrokePoints, then getStrokeOutlinePoints, returns the polygon.

- [ ] **Step 2: Replace the Task-1 stub** in `GetStroke.swift`:

```swift
// ABOUTME: Ported from perfect-freehand@1.2.3/getStroke.ts (MIT, Steve Ruiz).
// ABOUTME: Composition root — feeds input through GetStrokePoints +
// ABOUTME: GetStrokeOutlinePoints to produce a closed polygon.

import Foundation

public func getStroke<P: StrokeInputPoint>(points: [P],
                                            options: StrokeOptions = StrokeOptions()) -> [Point2D] {
    // ... convert P to [Double] (or internal point shape), call
    // GetStrokePoints, then GetStrokeOutlinePoints, then map output to
    // [Point2D].
}
```

- [ ] **Step 3: Write the 8 input/options JSON fixtures (without `expected` — that comes from bun)**

Create these files in `Packages/PerfectFreehand/Tests/PerfectFreehandTests/Fixtures/`. Each is a `{name, input, options}` object — `expected` gets populated by `just regen-pf-fixtures`. Sample shapes:

`basic-line.json`:
```json
{
  "name": "basic-line",
  "input": [[10, 10, 0.5], [50, 10, 0.5], [90, 10, 0.5]],
  "options": {
    "size": 8, "thinning": 0.5, "smoothing": 0.5, "streamline": 0.5,
    "simulatePressure": true,
    "start": { "taper": 0, "cap": true },
    "end":   { "taper": 0, "cap": true },
    "last": true
  }
}
```

The 8 fixtures for this commit (definitions live in the spec, Section "Fixture coverage"):
- `basic-line.json` — three colinear points
- `long-curve.json` — ~20 points along a sine curve
- `closed-loop.json` — points that return near the start
- `single-point.json` — one point (produces a dot)
- `two-points.json` — two points (minimal valid stroke)
- `zigzag.json` — ~10 points alternating direction
- `varying-pressure.json` — points with explicit pressure values varying 0.1..1.0
- `no-pressure-simulate-true.json` — points with pressure=0, simulatePressure=true

Use the design spec's option shapes as the default; vary `options` per fixture only where the fixture name says so.

- [ ] **Step 4: Run `just regen-pf-fixtures`** to populate `expected` from the TS reference

```bash
just regen-pf-fixtures
```

Expected: 8 ✓ lines, each `.json` file now has an `expected` array. If bun is missing, you'll get the friendly hint — install bun and retry.

- [ ] **Step 5: Write `FixtureTests.swift`**

```swift
// ABOUTME: Cross-language byte-parity tests. Loads checked-in JSON fixtures
// ABOUTME: generated by the TS reference and asserts the Swift port produces
// ABOUTME: matching output within abs ≤ 1e-9 per component.

import Testing
import Foundation
@testable import PerfectFreehand

@Suite("Fixtures")
struct FixtureTests {
    struct Fixture: Decodable {
        let name: String
        let input: [[Double]]
        let options: FixtureOptions
        let expected: [[Double]]
    }
    struct FixtureOptions: Decodable {
        let size: Double
        let thinning: Double
        let smoothing: Double
        let streamline: Double
        let simulatePressure: Bool
        let start: FixtureTaper
        let end: FixtureTaper
        let last: Bool
    }
    struct FixtureTaper: Decodable {
        let taper: Double
        let cap: Bool
    }

    private static func loadAll() throws -> [Fixture] {
        // Locate Fixtures dir relative to the test bundle and load all *.json
        // except package.json / tsconfig.json. Return parsed Fixtures.
        // (Implementation: enumerate Bundle.module.resourcePath, filter,
        // decode each. May need to add `resources: [.copy("Fixtures")]` to
        // the test target in Package.swift — verify and adjust.)
    }

    @Test("all fixtures match TS output within abs <= 1e-9", arguments: try Self.loadAll())
    func match(fixture: Fixture) {
        let input = fixture.input.map { coords in
            InputPoint(x: coords[0], y: coords[1], pressure: coords.count > 2 ? coords[2] : nil)
        }
        var opts = StrokeOptions()
        opts.size = fixture.options.size
        opts.thinning = fixture.options.thinning
        opts.smoothing = fixture.options.smoothing
        opts.streamline = fixture.options.streamline
        opts.simulatePressure = fixture.options.simulatePressure
        opts.start = TaperOptions(taper: .length(fixture.options.start.taper), cap: fixture.options.start.cap)
        opts.end   = TaperOptions(taper: .length(fixture.options.end.taper), cap: fixture.options.end.cap)
        opts.last = fixture.options.last

        let actual = getStroke(points: input, options: opts)
        #expect(actual.count == fixture.expected.count, "vertex count mismatch in \(fixture.name)")
        for (i, (a, e)) in zip(actual, fixture.expected).enumerated() {
            #expect(abs(a.x - e[0]) <= 1e-9, "x[\(i)] mismatch in \(fixture.name): \(a.x) vs \(e[0])")
            #expect(abs(a.y - e[1]) <= 1e-9, "y[\(i)] mismatch in \(fixture.name): \(a.y) vs \(e[1])")
        }
    }
}

public struct InputPoint: StrokeInputPoint {
    public let x: Double
    public let y: Double
    public let pressure: Double?
    public init(x: Double, y: Double, pressure: Double? = nil) {
        self.x = x; self.y = y; self.pressure = pressure
    }
}
```

Note on `TaperValue`: the fixture's taper number is mapped to `.length(n)` if non-zero, `.none` if zero. Confirm this matches TS semantics (TS accepts `false`, `true`, or a number) — adjust the mapping if needed after reading `types.ts`.

Note on fixture-loading: SPM test targets need explicit `resources: [.copy("Fixtures")]` in Package.swift to bundle the fixture files. Update Package.swift's testTarget definition to include this and remove the `exclude: ["Fixtures"]` from Task 1's bootstrap definition.

- [ ] **Step 6: Run tests, expect pass (or near-pass)**

```bash
swift test --package-path Packages/PerfectFreehand
```

If any fixture fails, the failure message identifies which fixture and which vertex. If the Swift output diverges from TS at the last few ULPs, double-check trig function usage (`Foundation.cos` vs `Swift.cos`); the underlying libm should be identical on macOS but verify. If divergence is structural (different vertex counts), the algorithm port has a bug — debug.

- [ ] **Step 7: Run full check**

```bash
just check
```

- [ ] **Step 8: Commit**

```bash
git add Packages/PerfectFreehand
git commit -m "$(cat <<'EOF'
PerfectFreehand: complete getStroke + 8 cross-language fixtures

Replaces the Task-1 stub with the real composition root: feeds input
through GetStrokePoints, then GetStrokeOutlinePoints, returns the
closed polygon as [Point2D]. Mirrors perfect-freehand@1.2.3/
getStroke.ts.

Adds FixtureTests.swift and 8 JSON fixtures (basic-line, long-curve,
closed-loop, single-point, two-points, zigzag, varying-pressure,
no-pressure-simulate-true) generated from the upstream TS reference
via `just regen-pf-fixtures`. Byte-parity asserted within
abs ≤ 1e-9. The Swift port now produces output identical to TS for
the full input/options surface exercised by these fixtures.

Package.swift's testTarget gains `resources: [.copy("Fixtures")]`
so the JSON files ship inside the test bundle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Remaining ~7 fixtures + full PropertyTests

**Files:**
- Create: 7 more JSON fixture files
- Modify: `Packages/PerfectFreehand/Tests/PerfectFreehandTests/PropertyTests.swift` (expand with all the invariants from the spec)

- [ ] **Step 1: Write the 7 remaining fixtures' input + options:**
- `no-pressure-simulate-false.json` (pressure=0, simulatePressure=false — should produce minimal-radius strokes)
- `constant-pressure.json` (all points pressure=0.7)
- `streamline-0.json` (basic-line variant, streamline=0)
- `streamline-1.json` (same variant, streamline=1)
- `thinning-0.json` (basic-line variant, thinning=0 — uniform width)
- `thinning-1.json` (basic-line variant, thinning=1 — max variation)
- `taper-aggressive.json` (long-curve variant, start.taper=20, end.taper=20)
- `empty-input.json` (input: [])
- `two-identical-points.json` (input: [[50,50,0.5], [50,50,0.5]])
- `very-small-size.json` (basic-line variant, size=0.5)

(That's 10 — fine, more is better; "~7" was a rough number.)

- [ ] **Step 2: Run `just regen-pf-fixtures`** to populate `expected` for all of them

```bash
just regen-pf-fixtures
```

- [ ] **Step 3: Expand `PropertyTests.swift`** with all the invariants from the design spec:
- Empty input → empty output (overlaps with `empty-input.json` fixture but property-test asserts behavior, not byte match)
- Single point → small closed polygon around that point
- Output closed: last vertex connects to first (vertex count ≥ 3, or last == first within epsilon)
- Straight horizontal line → output symmetric about centerline
- Scaling `size` by N scales the polygon's distance-from-centerline by N
- `last: false` vs `last: true` produce different last-region geometry
- For a strictly monotonic input, output doesn't self-intersect (run a line-line intersection check on all polygon edge pairs)

- [ ] **Step 4: Add a sanity-only performance test** (prints, doesn't fail):

```swift
@Test("getStroke on 1000-point input completes in reasonable time")
func perfSanity() {
    let input = (0..<1000).map { i in InputPoint(x: Double(i), y: sin(Double(i) / 50) * 100) }
    let start = Date()
    _ = getStroke(points: input, options: StrokeOptions())
    let elapsed = Date().timeIntervalSince(start)
    print("getStroke 1000pts: \(elapsed * 1000) ms")
    #expect(elapsed < 0.5)  // half-second floor as a really-broken-only check
}
```

- [ ] **Step 5: Run all tests, expect pass**

```bash
swift test --package-path Packages/PerfectFreehand
```

- [ ] **Step 6: Run full check**

```bash
just check
```

- [ ] **Step 7: Commit**

```bash
git add Packages/PerfectFreehand
git commit -m "$(cat <<'EOF'
PerfectFreehand: full fixture coverage + property tests

Adds the remaining ~10 fixtures covering the option matrix: streamline
0/1, thinning 0/1, taper aggressive, constant-pressure, no-pressure
simulate=false, plus edge cases (empty input, two-identical-points,
very-small-size). All generated via `just regen-pf-fixtures`.

PropertyTests now covers the design spec's invariants: empty input,
single-point, polygon closure, horizontal-line symmetry, size-scaling
linearity, last:false vs last:true geometry, monotonic-input non-self
intersection. Plus a sanity-only timing print for 1000-point strokes.

This commit is the point at which the Swift port has parity with
upstream perfect-freehand@1.2.3 across the option surface fiti uses.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Renderer cutover

**Files:**
- Create: `Sources/Core/Rendering/StrokePoint+PerfectFreehand.swift`
- Create: `Sources/Core/Rendering/FitiStrokeOptions.swift`
- Modify: `Sources/AppKit/CanvasView.swift` (drawStroke and bake call sites)
- Create: `Tests/AppKitTests/CanvasViewPerfectFreehandTests.swift`
- Modify: `ONBOARDING.md`
- Modify: `docs/specs/2026-05-16-fiti-roadmap.md`

The atomic visible-change commit. Until this commit, fiti's behavior is unchanged; after this commit, strokes render as perfect-freehand polygons.

- [ ] **Step 1: Create the conformance bridge**

`Sources/Core/Rendering/StrokePoint+PerfectFreehand.swift`:

```swift
// ABOUTME: Adapts fiti's StrokePoint to PerfectFreehand's StrokeInputPoint
// ABOUTME: protocol. Pressure is nil because mouse input has none — simulatePressure
// ABOUTME: in the options synthesizes a velocity-derived value at the algorithm layer.

import PerfectFreehand

extension StrokePoint: StrokeInputPoint {
    public var pressure: Double? { nil }
}
```

This file lives in `Sources/Core/Rendering/` — verify that's an acceptable directory (or place under `Sources/Core/` directly if `Rendering/` doesn't exist; the directory split is organizational, not architectural).

Note on import discipline: `Sources/Core/` historically must not import AppKit/CoreGraphics/Network/SwiftUI. `PerfectFreehand` is none of those — it's a pure-Swift dependency — so this import is fine. The `just lint` import-discipline grep won't catch `import PerfectFreehand`. If the grep is over-permissive (just checks specific banned modules), no change needed; if it's a whitelist, extend it.

- [ ] **Step 2: Create the options wrapper**

`Sources/Core/Rendering/FitiStrokeOptions.swift`:

```swift
// ABOUTME: fiti's central perfect-freehand options. Single tuning surface;
// ABOUTME: if a default feels wrong in practice, it changes here.

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

- [ ] **Step 3: Write the failing AppKit integration test**

`Tests/AppKitTests/CanvasViewPerfectFreehandTests.swift`:

```swift
// ABOUTME: Confirms the perfect-freehand renderer path produces non-zero
// ABOUTME: polygon-fill pixels at expected locations.

import AppKit
import Testing
@testable import Fiti  // or whatever the existing AppKit test bundle imports

@Suite("CanvasView perfect-freehand rendering")
@MainActor
struct CanvasViewPerfectFreehandTests {
    @Test("a horizontal stroke fills a band of pixels along its path")
    func horizontalStrokeFills() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 10,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 15), StrokePoint(x: 50, y: 15), StrokePoint(x: 90, y: 15)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 100, height: 30)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // A pixel right on the stroke's centerline should be solid red.
        let center = try #require(rep.colorAt(x: 50, y: 15))
        #expect(center.redComponent > 0.5)
        #expect(center.alphaComponent > 0.5)
        // A pixel far above the stroke should be transparent.
        let above = try #require(rep.colorAt(x: 50, y: 2))
        #expect(above.alphaComponent < 0.01)
    }
}
```

- [ ] **Step 4: Run, expect failure**

```bash
just test-integration
```

Expected: the test fails because `CanvasView.drawStroke` still strokes a CGPath instead of filling a polygon (so a thick band of pixels won't be filled at width 10 unless the algorithm output is wide enough — actually the existing CGPath stroke at width 10 would also produce a band, so this test might pass before the cutover. Better fail signal: check a pixel where perfect-freehand's taper produces ALPHA but a CGPath stroke produces FULL OPAQUE, or vice versa. Use a pixel near the start where perfect-freehand tapers down to zero — that pixel will be transparent under perfect-freehand but opaque under CGPath. Adjust the test to that distinguishing pixel — see TS reference's `getStrokeOutlinePoints` taper behavior to find a distinguishing region.)

If you can't easily construct a distinguishing test, write a weaker test that just confirms non-zero pixels exist in the stroke path (won't distinguish but at least confirms the new render path doesn't crash or produce empty output).

- [ ] **Step 5: Swap the render path in `CanvasView.swift`**

Find `drawStroke` (currently invoked in both `draw(_:)` for in-progress and `bakeCommitted` for committed). Today it does some variant of:

```swift
private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
    ctx.setStrokeColor(stroke.color.cgColor)
    ctx.setLineWidth(CGFloat(stroke.width))
    let path = CGMutablePath()
    let pts = stroke.points
    guard !pts.isEmpty else { return }
    path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
    for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
    ctx.addPath(path)
    ctx.strokePath()
}
```

(Confirm the actual shape by reading CanvasView.swift — adjust accordingly.)

Replace with:

```swift
import PerfectFreehand
// ... at the top of the file

private func drawStroke(_ stroke: Stroke, in ctx: CGContext, isInProgress: Bool) {
    let opts = FitiStrokeOptions.make(width: stroke.width, last: !isInProgress)
    let polygon = getStroke(points: stroke.points, options: opts)
    guard polygon.count >= 3 else { return }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
    for v in polygon.dropFirst() { path.addLine(to: CGPoint(x: v.x, y: v.y)) }
    path.closeSubpath()
    ctx.setFillColor(stroke.color.cgColor)
    ctx.addPath(path)
    ctx.fillPath()
}
```

Update the call sites in `bakeCommitted` and `draw(_:)` to pass the `isInProgress` argument: false in bake, true in the live overlay.

- [ ] **Step 6: Run, expect pass**

```bash
just test-integration
```

Total integration test count goes up by 1 (the new perfect-freehand test).

- [ ] **Step 7: Run full check**

```bash
just check
```

- [ ] **Step 8: Update ONBOARDING.md**

Add a one-line entry to "Dig deeper" or create a brief "Acknowledgments" section:

```markdown
## Acknowledgments

This project uses a Swift port of [perfect-freehand](https://github.com/steveruizok/perfect-freehand) (MIT, Steve Ruiz) for stroke rendering. See `Packages/PerfectFreehand/LICENSE`.

If you ever need to regenerate the cross-language test fixtures for the port (after upgrading upstream or to investigate a parity failure): `brew install bun`, then `just regen-pf-fixtures`.
```

- [ ] **Step 9: Update the roadmap**

In `docs/specs/2026-05-16-fiti-roadmap.md`, tick the Perfect-freehand entry:

```diff
 ### Perfect-freehand Swift port
-- [ ] Real reason to do this: ...
+- [x] Real reason to do this: ...
```

(Tick all bullets under that section, leaving the text intact.)

- [ ] **Step 10: Commit**

```bash
git add Sources/Core/Rendering Sources/AppKit/CanvasView.swift Tests/AppKitTests/CanvasViewPerfectFreehandTests.swift ONBOARDING.md docs/specs/2026-05-16-fiti-roadmap.md
git commit -m "$(cat <<'EOF'
Cut CanvasView over to PerfectFreehand polygon-fill rendering

The visible quality jump. drawStroke now calls getStroke (port of
perfect-freehand@1.2.3) and fills the resulting closed polygon
instead of stroking a uniform-width CGPath. Committed strokes pass
last: true; the live in-progress stroke passes last: false so its
tail doesn't snap visually on every move.

Sources/Core/Rendering/StrokePoint+PerfectFreehand.swift conforms
fiti's StrokePoint to the package's StrokeInputPoint protocol
(pressure returns nil; simulatePressure: true synthesizes from
velocity at the algorithm layer).

Sources/Core/Rendering/FitiStrokeOptions.swift holds fiti's
hardcoded option defaults — single tuning surface for the constants
ported from scratch's POC (smoothing/thinning/streamline = 0.5,
simulatePressure: true, taper: 0).

CanvasViewPerfectFreehandTests verifies the new render path produces
non-zero polygon-fill pixels at expected locations.

ONBOARDING.md gains an Acknowledgments section pointing at the
package's LICENSE plus the fixture-regen recipe. Roadmap's
perfect-freehand entry is ticked off.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Manual smoke

No code changes. Verify the visible-quality jump on actual hardware.

- [ ] **Step 1: Stop, install, launch**

```bash
just stop && just run-bg
```

- [ ] **Step 2: Activate (Ctrl+G), draw slow and fast strokes**

Draw a slow curve. Then a fast flick. Both should produce strokes that taper at the ends (start and end) — the slow stroke shows the taper most clearly; the fast flick shows it more aggressively due to velocity-driven pressure synthesis.

Compare to your memory of the uniform-width strokes from before this commit. Strokes should now look like ink rather than uniform pencil lines.

- [ ] **Step 3: Try the toolbar's other widths**

Set width to 1, draw. Set width to 20, draw. Tapers and overall shape should scale with size; the visual quality (tapered ends, no uniform-edge look) should hold across the size range.

- [ ] **Step 4: Hit undo / redo / clear**

`Cmd+Z`, `Cmd+Shift+Z`, `Cmd+K`. All should still work — perfect-freehand affects rendering, not the document model.

- [ ] **Step 5: Test the inspect pipeline**

```bash
just inspect-screenshot
```

The snapshot should reflect the new look. Open the PNG and verify it matches what's on-screen.

If anything looks wrong (no tapers, broken strokes, crashes), flag it. Otherwise — done.

---

## Self-review checklist

After all tasks complete:

- [ ] `just check` passes end-to-end
- [ ] `swift test --package-path Packages/PerfectFreehand` passes (all 8-10 ported-function tests, all 17-18 fixture tests, all property tests, perf sanity prints under 50ms)
- [ ] All fixture `expected` arrays were regenerated from `just regen-pf-fixtures` against perfect-freehand@1.2.3
- [ ] `Sources/Core/` still passes the import-discipline check (`just lint`)
- [ ] Manual smoke (Task 12) confirms the visible quality jump
- [ ] No file in the package missing the `// ABOUTME: Ported from perfect-freehand@1.2.3/<source.ts> (MIT, Steve Ruiz).` header
- [ ] No `// TODO` or `// FIXME` markers in any new file
- [ ] Roadmap perfect-freehand entry is ticked off
- [ ] ONBOARDING.md has the acknowledgments entry
- [ ] No regressions in existing fiti tests (unit, integration, dev HTTP)
