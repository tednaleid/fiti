# fiti

For project orientation (stack, build/test commands, architecture, entry points), see [ONBOARDING.md](./ONBOARDING.md).

Designs and specs live in `docs/specs/`. The active POC design is [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md).

## Rules

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest.
- Red/green testing: write a failing test first, then make it pass. Full suite must stay under 5 seconds.
- `Sources/Core/` is pure Swift and must not import `AppKit`, `CoreGraphics`, `Network`, or `SwiftUI`. The `fiti-unit` test target enforces this at the build-graph level (it does not compile `Sources/AppKit` or `Sources/App`), and `just lint` re-checks via grep.
- All ports live in `Sources/Core/Ports/`. Concrete adapters live in `Sources/AppKit/`, `Sources/DevHTTP/`, or `Sources/App/`. Test doubles live under `Tests/`.
- The justfile is the entry point for everything. Never bare `rm -rf`; always `just clean`. See Commands below — do not bypass.
- Build output lives at `/tmp/fiti-build` (`SYMROOT={{build_dir}}`). The repo is under Dropbox and in-tree builds get resource-fork-poisoned for codesign. Never override this.
- The dev HTTP introspection API runs on `localhost:9876` when the app is launched with `--dev`. Same port as `../montty` and `../limn`.
- HTTP dev routes bypass the activation gate (they call `AppController` methods directly). Don't add an activation check to them.
- Commit only when asked. Never `--no-verify`. Always use a HEREDOC for commit messages.

## Commands

Every command goes through `just`. Do not invoke the underlying tool directly — `xcodebuild`, `swiftlint`, raw `curl`, `xcodegen generate`, and bare `rm -rf` are all wrong unless you are debugging the recipe itself. If a recipe doesn't exist yet for something you want to do, add it; don't one-shot the raw command.

**Build, test, lint.** Use `just check` before declaring work done; it is the CI gate and runs tests + lint + build. Individually: `just test` runs Swift Testing under `xcodebuild`, `just lint` runs SwiftLint plus the `Sources/Core/` import-discipline grep, `just build` produces the `.app` under `/tmp/fiti-build`. `just clean` removes build artifacts. `just generate` regenerates `fiti.xcodeproj` from `project.yml` — needed after editing `project.yml`.

**Running the app.** `just run` launches in the foreground; `just run-bg` launches in the background and `just stop` quits it (graceful via `osascript`, falling back to `pkill`). Both pass `--dev --port 9876` so the introspection API is up.

**Driving and inspecting the running app.** When you want to observe state or inject input, use the `inspect-*` recipes — not raw `curl`. Plain `curl localhost:9876/...` works but skips the `jq` formatting, the screenshot file-path convention (`.llm/inspect/screenshot-YYYYMMDD-HHMMSS.png`), and the consistency that makes scripted sessions reproducible.

- `just inspect-state` — current `mode`, click-through, undo/redo depth
- `just inspect-doc` — full `FitiDoc` JSON
- `just inspect-screenshot [path]` — render the current frame to a PNG under `.llm/inspect/`
- `just inspect-pointer EVENT X Y` — inject a pointer event (`EVENT` is `down`, `move`, or `up`)
- `just inspect-activate` / `just inspect-deactivate` — toggle capture vs click-through
- `just inspect-clear` — `POST /clear`
- `just inspect-undo` / `just inspect-redo` — exercise the undo stack

If a recipe is missing for something you need to do repeatedly, add it to the justfile rather than running the raw command twice.
