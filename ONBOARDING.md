# Onboarding

fiti is a native Swift macOS port of [telestrator](https://github.com/steveruizok/telestrator) — a transparent always-on-top drawing overlay. The current scope is a proof-of-concept that validates a hexagonal Core ↔ adapters split, a borderless transparent window with cursor click-through, and an HTTP dev surface so Claude Code can observe and drive the running app.

**Status: POC + hardening complete.** All seven acceptance criteria from the POC design pass. The hardening plan (`docs/specs/2026-05-16-fiti-hardening-plan.md`) is also done: a `fiti-integration` test target covers the AppKit boundary, `Editor` and `AppController` are `@MainActor`-isolated, `CanvasView` uses a two-canvas split (committed strokes baked, in-progress drawn live), and `Ctrl+F` works globally when Accessibility permission is granted. Next: shapes, fading, pen pressure, toolbar — see [Out of scope] in the design doc.

## Stack

- Language: Swift 6 language mode (macOS 14+), Xcode 26.5 / Swift 6.3.2 toolchain
- Frameworks: AppKit (window, input), Core Graphics (rendering), Foundation, Network (dev HTTP via `NWListener`)
- Build: xcodegen + xcodebuild — `project.yml` is the declarative spec, `*.xcodeproj` is generated, never committed
- Task runner: [`just`](https://just.systems) (authoritative)
- Tests: Swift Testing (`@Test`, `#expect`)
- Lint: SwiftLint, plus a `scripts/check-core-imports.sh` grep step that fails if `Sources/Core/` imports AppKit / CoreGraphics / Network / SwiftUI

## Common commands

These `just` recipes run the project end-to-end:

- Generate Xcode project: `just generate`
- Build: `just build`
- Test: `just test`
- Lint: `just lint`
- Full CI gate (test + lint + build): `just check`
- Run with dev HTTP: `just run` (foreground) or `just run-bg` + `just stop`
- Inspect running app: `just inspect-state` / `inspect-doc` / `inspect-screenshot` / `inspect-pointer EVENT X Y` / `inspect-undo` / `inspect-redo` / `inspect-clear` / `inspect-activate` / `inspect-deactivate`
- Clean: `just clean`
- Install pre-commit hook (runs `just check`): `just install-hooks`

## Code signing

Builds default to ad-hoc signing (`-`), which works but invalidates macOS Accessibility grants every rebuild — you'd need to toggle Fiti off-and-on in System Settings → Privacy & Security → Accessibility after every `just install`.

To make grants persist across rebuilds, set a stable signing identity:

1. Copy `.env.example` to `.env` (gitignored).
2. Set `FITI_CODE_SIGN_IDENTITY` to a code-signing identity available on your machine. List them with `security find-identity -v -p codesigning`. A real Developer ID Application cert (free with any paid Apple Developer membership) or a self-signed `Code Signing` cert from Keychain Access both work.
3. Run `just install` once and grant Fiti Accessibility access. The grant persists across all future rebuilds with that identity.

Without `.env`, the ad-hoc fallback is used — fine for CI and contributors who don't need the global Ctrl+F hotkey to survive rebuilds.

## Architecture

Hexagonal. `Sources/Core/` is pure Swift — `FitiDoc`, `Stroke`, `Editor`, `AppController`, and the `Renderer` / `WindowControl` / `InputSource` / `Clock` / `IdGenerator` ports. `Sources/AppKit/` provides the transparent always-on-top `NSWindow`, the `CanvasView` renderer (two CGLayer-style buffers for committed + in-progress strokes), and the `NSEvent`-driven input source. `Sources/DevHTTP/` is the `NWListener` dev API on port 9876. `Sources/App/` is the only place that imports both AppKit and Core to wire ports to adapters.

The document model is identity-bearing: each stroke has a stable `StrokeId`, points freeze at `endStroke`, and later mutations target a `transform` field. Undo/redo is an `InverseOp` stack applied as forward edits (not history rewinds), so the same pattern works whether the backing store is plain Swift or an Automerge doc later.

## Keyboard shortcuts

- `Ctrl+F` — toggle activate/deactivate (works globally if Accessibility permission is granted; otherwise only when fiti has focus)
- `Esc` — deactivate (release cursor; click-through on; strokes remain visible)
- `Cmd+K` — clear all strokes (only fires while the overlay has key focus)
- `Cmd+Z` / `Cmd+Shift+Z` — undo / redo (only while the overlay has key focus)

Per-stroke erase is HTTP-only — use `just inspect-erase ID`.

## Key paths

- `docs/specs/2026-05-16-fiti-poc-design.md` — POC design, authoritative
- `.llm/telestrator/` — vendored MIT-licensed Electron reference (read-only, gitignored)
- `Sources/Core/` — pure domain (complete: Model + Editor + AppController + ports)
- `Sources/AppKit/` — macOS shell + renderer + input adapter (complete — POC)
- `Sources/DevHTTP/` — `NWListener`-based dev HTTP server (complete)
- `Sources/App/` — `main.swift`, argv, dependency wiring (complete)
- `Tests/CoreTests/` — pure-Swift tests against `Sources/Core` (complete)
- `Tests/DevHTTPTests/` — HTTP route tests against a fake `AppController` (complete)
- `Resources/Info.plist`, `Resources/fiti.entitlements` — bundle metadata
- `project.yml` — xcodegen spec
- `justfile` — task recipes

## Dig deeper

- [`docs/architecture.md`](./docs/architecture.md) — module diagram, ports & adapters table, two-canvas split, dev HTTP surface
- [`docs/specs/2026-05-16-fiti-roadmap.md`](./docs/specs/2026-05-16-fiti-roadmap.md) — what's next: menubar, toolbar, perfect-freehand, distribution
- [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md) — POC design, scope, ports, HTTP routes, decision log
- [`.llm/telestrator/renderer/lib/state.ts`](./.llm/telestrator/renderer/lib/state.ts) — telestrator's state machine (the conceptual ancestor)
- [`CLAUDE.md`](./CLAUDE.md) — project rules
