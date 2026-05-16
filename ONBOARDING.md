# Onboarding

fiti is a native Swift macOS port of [telestrator](https://github.com/steveruizok/telestrator) — a transparent always-on-top drawing overlay. The current scope is a proof-of-concept that validates a hexagonal Core ↔ adapters split, a borderless transparent window with cursor click-through, and an HTTP dev surface so Claude Code can observe and drive the running app.

**Status: pre-implementation.** The design is committed at [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md); source code, project file, and justfile are not yet written. The commands listed below describe the planned recipes per the spec.

## Stack

- Language: Swift 5+ (macOS 14+)
- Frameworks: AppKit (window, input), Core Graphics (rendering), Foundation, Network (dev HTTP via `NWListener`)
- Build: xcodegen + xcodebuild — `project.yml` is the declarative spec, `*.xcodeproj` is generated, never committed
- Task runner: [`just`](https://just.systems) (authoritative)
- Tests: Swift Testing (`@Test`, `#expect`)
- Lint: SwiftLint, plus a `scripts/check-core-imports.sh` grep step that fails if `Sources/Core/` imports AppKit / CoreGraphics / Network / SwiftUI

## Common commands

These are the planned `just` recipes (see spec § Justfile):

- Generate Xcode project: `just generate`
- Build: `just build`
- Test: `just test`
- Lint: `just lint`
- Full CI gate (test + lint + build): `just check`
- Run with dev HTTP: `just run` (foreground) or `just run-bg` + `just stop`
- Inspect running app: `just inspect-state` / `inspect-doc` / `inspect-screenshot` / `inspect-pointer EVENT X Y` / `inspect-undo` / `inspect-redo` / `inspect-clear` / `inspect-activate` / `inspect-deactivate`
- Clean: `just clean`
- Install pre-commit hook (runs `just check`): `just install-hooks`

## Architecture

Hexagonal. `Sources/Core/` is pure Swift — `FitiDoc`, `Stroke`, `Editor`, `AppController`, and the `Renderer` / `WindowControl` / `InputSource` / `Clock` / `IdGenerator` ports. `Sources/AppKit/` provides the transparent always-on-top `NSWindow`, the `CanvasView` renderer (two CGLayer-style buffers for committed + in-progress strokes), and the `NSEvent`-driven input source. `Sources/DevHTTP/` is the `NWListener` dev API on port 9876. `Sources/App/` is the only place that imports both AppKit and Core to wire ports to adapters.

The document model is identity-bearing: each stroke has a stable `StrokeId`, points freeze at `endStroke`, and later mutations target a `transform` field. Undo/redo is an `InverseOp` stack applied as forward edits (not history rewinds), so the same pattern works whether the backing store is plain Swift or an Automerge doc later.

## Key paths

- `docs/specs/2026-05-16-fiti-poc-design.md` — POC design, authoritative
- `.llm/telestrator/` — vendored MIT-licensed Electron reference (read-only, gitignored)
- `Sources/Core/` — pure domain (planned)
- `Sources/AppKit/` — macOS shell + renderer + input adapter (planned)
- `Sources/DevHTTP/` — `NWListener`-based dev HTTP server (planned)
- `Sources/App/` — `main.swift`, argv, dependency wiring (planned)
- `Tests/CoreTests/` — pure-Swift tests against `Sources/Core` (planned)
- `Tests/DevHTTPTests/` — HTTP route tests against a fake `AppController` (planned)
- `Resources/Info.plist`, `Resources/fiti.entitlements` — bundle metadata (planned)
- `project.yml` — xcodegen spec (planned)
- `justfile` — task recipes (planned)

## Dig deeper

- [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md) — POC design, scope, ports, HTTP routes, decision log
- [`.llm/telestrator/renderer/lib/state.ts`](./.llm/telestrator/renderer/lib/state.ts) — telestrator's state machine (the conceptual ancestor)
- [`CLAUDE.md`](./CLAUDE.md) — project rules
