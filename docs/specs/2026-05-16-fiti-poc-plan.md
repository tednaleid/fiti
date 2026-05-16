# fiti POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the proof-of-concept native Swift telestrator described in [`./2026-05-16-fiti-poc-design.md`](./2026-05-16-fiti-poc-design.md): a transparent always-on-top macOS window with mouse-driven freehand drawing, a hexagonal Core ↔ adapters split, and an HTTP dev surface on `localhost:9876` that lets Claude observe and drive the running app.

**Architecture:** xcodegen + xcodebuild Swift project with two targets (`fiti` app, `fiti-unit` tests). Pure-Swift `Sources/Core/` holds the domain (`FitiDoc`, `Editor`, `AppController`, ports). `Sources/AppKit/`, `Sources/DevHTTP/`, and `Sources/App/` are adapters and wiring. The test target's source list excludes AppKit so Core tests can't see it.

**Tech Stack:** Swift 5+, macOS 14+, AppKit, Core Graphics, Foundation, Network.framework (`NWListener` for dev HTTP), xcodegen, just, SwiftLint, Swift Testing (`@Test`, `#expect`).

**Source of truth:** [`./2026-05-16-fiti-poc-design.md`](./2026-05-16-fiti-poc-design.md). Do not re-derive design decisions; if the plan and spec disagree, the spec wins and the plan needs fixing.

**Conventions used in every task:**
- All Swift files begin with two `// ABOUTME: ` lines (per Ted's global rule).
- Tests use `import Testing` + `@Test` + `#expect` — never XCTest.
- Run `just test` after every implementation step that has tests; expect green.
- Commit after each task completes. Commit messages use a HEREDOC and end with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- Never `--no-verify`. Never `rm -rf` outside `just clean`. Never bypass the justfile.

---

## Phase 1 — Bootstrap

Goal: a generated Xcode project that builds, an empty `just check` that passes, CI that runs it, and the hexagonal-boundary lint script. No domain code yet; a single smoke test proves Swift Testing works.

### Task 1.1: Project metadata and gitignore

**Files:**
- Create: `project.yml`
- Modify: `.gitignore`

- [ ] **Step 1: Extend `.gitignore`**

Append these lines to `.gitignore` (keep the existing `.llm` entry on its own line):

```
# Xcode generated artifacts
*.xcodeproj/
DerivedData/
*.xcuserstate
xcuserdata/

# Build outputs (we keep them in /tmp, but be defensive)
/build/
*.app

# Swift Package Manager
.swiftpm/
.build/
Package.resolved

# macOS
.DS_Store
```

- [ ] **Step 2: Write `project.yml`**

Create `project.yml` with two targets — `fiti` (the app) and `fiti-unit` (the test bundle whose `sources:` list deliberately excludes `Sources/AppKit` and `Sources/App` so Core/DevHTTP tests can't see them):

```yaml
name: fiti
options:
  bundleIdPrefix: com.fiti
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "5.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    SWIFT_STRICT_CONCURRENCY: minimal

targets:
  fiti:
    type: application
    platform: macOS
    sources:
      - path: Sources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fiti.app
        PRODUCT_NAME: Fiti
        INFOPLIST_FILE: Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: Resources/fiti.entitlements
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"

  fiti-unit:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
      - path: Sources/Core
      - path: Sources/DevHTTP
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fiti.app.tests
        GENERATE_INFOPLIST_FILE: "YES"
        TEST_HOST: ""
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore project.yml
git commit -m "$(cat <<'EOF'
Bootstrap xcodegen project spec

Two-target shape: fiti (app) and fiti-unit (tests).
fiti-unit's sources list excludes Sources/AppKit and Sources/App
so Core tests cannot import AppKit at the build-graph level.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.2: Initial Sources/ tree with placeholder file

xcodegen needs at least one source file per target to generate without warnings. Create stub files we'll fill in during Phase 2.

**Files:**
- Create: `Sources/Core/Model/.gitkeep`
- Create: `Sources/Core/Editor/.gitkeep`
- Create: `Sources/Core/Control/.gitkeep`
- Create: `Sources/Core/Ports/.gitkeep`
- Create: `Sources/Core/_CoreBootstrap.swift` (placeholder so xcodegen finds at least one Swift file; basename must be unique across all `Sources/` subdirs to avoid Xcode's per-target basename collision)
- Create: `Sources/AppKit/_AppKitBootstrap.swift`
- Create: `Sources/DevHTTP/_DevHTTPBootstrap.swift`
- Create: `Sources/App/main.swift`
- Create: `Tests/CoreTests/SmokeTests.swift`
- Create: `Tests/DevHTTPTests/.gitkeep`

- [ ] **Step 1: Create `.gitkeep` markers**

```bash
mkdir -p Sources/Core/Model Sources/Core/Editor Sources/Core/Control Sources/Core/Ports
mkdir -p Sources/AppKit Sources/DevHTTP Sources/App
mkdir -p Tests/CoreTests Tests/DevHTTPTests
touch Sources/Core/Model/.gitkeep Sources/Core/Editor/.gitkeep Sources/Core/Control/.gitkeep Sources/Core/Ports/.gitkeep
touch Tests/DevHTTPTests/.gitkeep
```

- [ ] **Step 2: Create `Sources/Core/_CoreBootstrap.swift`**

```swift
// ABOUTME: Placeholder so xcodegen has at least one source in the Core module.
// ABOUTME: Delete in Phase 2 once the first real Core type lands.

import Foundation

internal enum FitiCoreBootstrap {}
```

Repeat the same pattern for `Sources/AppKit/_AppKitBootstrap.swift` (rename the enum to `FitiAppKitBootstrap` and add `import AppKit` instead of `Foundation`) and `Sources/DevHTTP/_DevHTTPBootstrap.swift` (rename to `FitiDevHTTPBootstrap`, `import Foundation` only). Filename basenames must be unique within a target — Xcode/swiftc disambiguates by basename, so all three must NOT share the same `_Bootstrap.swift` name.

- [ ] **Step 3: Create `Sources/App/main.swift`**

```swift
// ABOUTME: Application entry point. Wiring lands in Phase 5.
// ABOUTME: This stub exists so xcodegen produces a buildable app target.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Create `Tests/CoreTests/SmokeTests.swift`**

```swift
// ABOUTME: Single trivial Swift Testing case to prove the test target builds and runs.
// ABOUTME: Delete or replace once real Core tests exist (Phase 2).

import Testing

@Test func swiftTestingIsWired() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
Add empty Sources/ tree and smoke test

Placeholder Swift files so xcodegen has at least one source per
target. Smoke test proves Swift Testing is wired before we add
domain code in Phase 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.3: Resources (Info.plist, entitlements)

xcodegen will complain at generate-time if `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` point at non-existent files. Create them now with the minimum needed for a transparent overlay app.

**Files:**
- Create: `Resources/Info.plist`
- Create: `Resources/fiti.entitlements`

- [ ] **Step 1: Create `Resources/Info.plist`**

`LSUIElement = true` makes fiti a "background" app with no Dock icon — appropriate for an always-on-top overlay.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2026 Ted Naleid. All rights reserved.</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `Resources/fiti.entitlements`**

Empty for POC — no sandboxing, no special permissions yet.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 3: Commit**

```bash
git add Resources/
git commit -m "$(cat <<'EOF'
Add Info.plist and entitlements

LSUIElement=true so fiti runs as an agent app with no Dock icon —
appropriate for an always-on-top overlay. Entitlements file is
empty for POC.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.4: Initial Justfile

Set up the recipes we'll need immediately (`generate`, `build`, `clean`) plus structure for what comes later.

**Files:**
- Create: `justfile`

- [ ] **Step 1: Create `justfile`**

```just
# fiti — native Swift telestrator POC
# All commands route through this file. Use `just <recipe>`, never the underlying tool directly.

build_dir := "/tmp/fiti-build"
dev_port  := "9876"

# List available recipes
default:
    @just --list

# ─── setup ────────────────────────────────────────────────────────────────

# Generate fiti.xcodeproj from project.yml (run after editing project.yml)
[group('setup')]
generate:
    xcodegen generate

# Install pre-commit hook that runs `just check`
[group('setup')]
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    printf '#!/bin/sh\njust check\n' > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "Installed pre-commit hook: .git/hooks/pre-commit"

# ─── build ────────────────────────────────────────────────────────────────

# Build the app (Debug). Output lives in /tmp/fiti-build (Dropbox/iCloud
# would otherwise poison the resource forks and break codesign).
[group('build')]
build: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti -configuration Debug build SYMROOT={{build_dir}}

# Remove build artifacts and the generated Xcode project
[group('build')]
clean:
    rm -rf {{build_dir}} fiti.xcodeproj DerivedData
    @echo "Clean complete."
```

- [ ] **Step 2: Verify the recipe list works**

```bash
just --list
```

Expected: lists `default`, `generate`, `install-hooks`, `build`, `clean` under the right groups.

- [ ] **Step 3: Verify generate**

```bash
just generate
```

Expected: `fiti.xcodeproj/` directory created. `ls fiti.xcodeproj` shows `project.pbxproj`.

- [ ] **Step 4: Verify build**

```bash
just build
```

Expected: `xcodebuild` runs, produces `Fiti.app` at `/tmp/fiti-build/Debug/Fiti.app`. Builds without errors (warnings about empty enum are fine).

- [ ] **Step 5: Commit**

```bash
git add justfile
git commit -m "$(cat <<'EOF'
Add initial justfile (generate, build, clean, install-hooks)

build_dir = /tmp/fiti-build keeps build artifacts out of the
Dropbox-managed working tree so resource forks don't break codesign.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.5: Test recipe + smoke-test green run

**Files:**
- Modify: `justfile` (add `test` recipe)

- [ ] **Step 1: Add `test` recipe**

Append to `justfile` under the existing groups:

```just
# ─── test ─────────────────────────────────────────────────────────────────

# Run the Swift Testing test bundle
[group('test')]
test: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}}

# Run a single test by name (e.g., just test-only swiftTestingIsWired)
[group('test')]
test-only NAME: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} -only-testing:'fiti-unit/{{NAME}}'
```

- [ ] **Step 2: Run the smoke test**

```bash
just test
```

Expected: the `swiftTestingIsWired` test passes. Output includes `Test Suite 'All tests' passed`.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "$(cat <<'EOF'
Add test recipe and verify Swift Testing is wired

`just test` runs the fiti-unit scheme via xcodebuild. test-only
takes a test identifier (suite or function) for targeted runs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.6: Core import discipline script

**Files:**
- Create: `scripts/check-core-imports.sh`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# ABOUTME: Fails if Sources/Core/ imports anything outside the allow-list.
# ABOUTME: Belt to xcodegen's target-source-list suspenders; runs in `just lint`.

set -euo pipefail

if [ ! -d Sources/Core ]; then
    echo "scripts/check-core-imports.sh: Sources/Core does not exist (yet?); skipping."
    exit 0
fi

# Allow: Foundation, Testing (Swift Testing — only imported in test files but
# safe to permit anywhere). Forbid: AppKit, CoreGraphics, Network, SwiftUI,
# UIKit, Combine.
FORBIDDEN='^import (AppKit|CoreGraphics|Network|SwiftUI|UIKit|Combine)\b'

violations=$(grep -rEn "$FORBIDDEN" Sources/Core || true)

if [ -n "$violations" ]; then
    echo "Forbidden imports detected in Sources/Core/:"
    echo
    echo "$violations"
    echo
    echo "Sources/Core/ must stay platform-neutral. Move adapter code to Sources/AppKit, Sources/DevHTTP, or Sources/App."
    exit 1
fi

echo "Sources/Core import discipline: OK"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/check-core-imports.sh
```

- [ ] **Step 3: Run it**

```bash
./scripts/check-core-imports.sh
```

Expected: `Sources/Core import discipline: OK` (the bootstrap file imports only `Foundation`).

- [ ] **Step 4: Commit**

```bash
git add scripts/check-core-imports.sh
git commit -m "$(cat <<'EOF'
Add scripts/check-core-imports.sh

Greps Sources/Core for forbidden imports (AppKit, CoreGraphics,
Network, SwiftUI, UIKit, Combine). Wired into `just lint` next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.7: SwiftLint config + lint/check recipes

**Files:**
- Create: `.swiftlint.yml`
- Modify: `justfile`

- [ ] **Step 1: Create minimal `.swiftlint.yml`**

```yaml
disabled_rules:
  - trailing_whitespace
  - todo
  - line_length

opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - sorted_imports
# Note: `unused_import` is an analyzer-only rule (requires `swiftlint analyze`
# with a compile-invocation log) and produces a miscategorization warning on
# every `swiftlint lint` run. The check-core-imports.sh script already covers
# our architectural concern about platform imports, so the analyzer rule is
# omitted here.

# Single-char identifiers like r/g/b/a (color components) and x/y (geometry)
# are conventional and appear throughout the codebase. Relax the default
# minimum length so SwiftLint doesn't flag them.
identifier_name:
  min_length:
    warning: 1
    error: 1

included:
  - Sources
  - Tests

excluded:
  - .build
  - fiti.xcodeproj
```

- [ ] **Step 2: Add `lint` and `check` recipes**

Append to `justfile`:

```just
# ─── check ────────────────────────────────────────────────────────────────

# Run SwiftLint plus the Sources/Core import-discipline check
[group('check')]
lint:
    swiftlint lint --strict
    ./scripts/check-core-imports.sh

# Full CI gate: test + lint + build. Run this before every commit.
[group('check')]
check: test lint build
```

- [ ] **Step 3: Verify lint passes**

```bash
just lint
```

Expected: SwiftLint emits "Done linting" with 0 violations; the import script reports OK. If SwiftLint is not installed, install via `brew install swiftlint` first.

- [ ] **Step 4: Verify check passes**

```bash
just check
```

Expected: test green, lint green, build green. Total runtime under 30s on a clean cache.

- [ ] **Step 5: Commit**

```bash
git add .swiftlint.yml justfile
git commit -m "$(cat <<'EOF'
Add SwiftLint config and `just lint` / `just check` recipes

`just check` is the CI gate: test + lint + build. lint runs
SwiftLint (strict) plus the Sources/Core import-discipline script.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.8: Run-mode recipes (run, run-bg, stop)

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Append run recipes**

```just
# ─── run ──────────────────────────────────────────────────────────────────

# Build and launch the app in the foreground (--dev enables HTTP introspection)
[group('run')]
run: build
    {{build_dir}}/Debug/Fiti.app/Contents/MacOS/Fiti --dev --port {{dev_port}}

# Build and launch in the background, for scripted testing
[group('run')]
run-bg: build
    @{{build_dir}}/Debug/Fiti.app/Contents/MacOS/Fiti --dev --port {{dev_port}} &
    @sleep 1
    @echo "fiti running in background. Use 'just stop' to quit."

# Graceful quit (osascript); falls back to pkill if Apple Events fail
[group('run')]
stop:
    @osascript -e 'tell application "Fiti" to quit' 2>/dev/null \
        || pkill -f 'Fiti.app/Contents/MacOS/Fiti' 2>/dev/null \
        || echo "fiti not running"
```

- [ ] **Step 2: Sanity-check the recipe list**

```bash
just --list
```

Expected: `run`, `run-bg`, `stop` appear under the `run` group.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "$(cat <<'EOF'
Add run / run-bg / stop recipes

`just run` foreground; `just run-bg` + `just stop` for scripted
testing. Both pass --dev --port 9876 so the introspection API is
up. stop tries osascript first, falls back to pkill.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.9: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  check:
    runs-on: macos-14
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - name: Install just
        uses: taiki-e/install-action@v2
        with:
          tool: just

      - name: Install xcodegen and swiftlint
        run: |
          brew install xcodegen swiftlint

      - name: Run check
        run: just check
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
Add GitHub Actions CI workflow

Runs `just check` on macos-14. Uses taiki-e/install-action for
`just` (per just-bootstrap guidance — avoids the deprecated
extractions/setup-just). Installs xcodegen + swiftlint via brew.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.10: ONBOARDING.md refresh

**Files:**
- Modify: `ONBOARDING.md`

- [ ] **Step 1: Replace the pre-implementation disclaimer**

Edit the second paragraph of `ONBOARDING.md`. Replace:

```
**Status: pre-implementation.** The design is committed at [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md); source code, project file, and justfile are not yet written. The commands listed below describe the planned recipes per the spec.
```

with:

```
**Status: bootstrap complete; domain code in progress.** The design is committed at [`docs/specs/2026-05-16-fiti-poc-design.md`](./docs/specs/2026-05-16-fiti-poc-design.md) and the implementation plan at [`docs/specs/2026-05-16-fiti-poc-plan.md`](./docs/specs/2026-05-16-fiti-poc-plan.md). `project.yml`, `justfile`, CI, and the Sources/ skeleton exist; `just check` is green. Phases 2–5 add the domain, AppKit shell, dev HTTP server, and end-to-end wiring.
```

- [ ] **Step 2: Remove `(planned)` markers from rows that now exist**

Strike `(planned)` from these rows in the Key paths section:

- `Sources/Core/` — pure domain (~~planned~~)
- `Sources/AppKit/` — macOS shell + renderer + input adapter (~~planned~~)
- `Sources/DevHTTP/` — `NWListener`-based dev HTTP server (~~planned~~)
- `Sources/App/` — `main.swift`, argv, dependency wiring (~~planned~~)
- `Tests/CoreTests/` — pure-Swift tests against `Sources/Core` (~~planned~~)
- `Tests/DevHTTPTests/` — HTTP route tests against a fake `AppController` (~~planned~~)
- `Resources/Info.plist`, `Resources/fiti.entitlements` — bundle metadata (~~planned~~)
- `project.yml` — xcodegen spec (~~planned~~)
- `justfile` — task recipes (~~planned~~)

Mark them `(skeleton — Phase 2+ fills in)` instead, except `project.yml`, `justfile`, `Resources/*` which are complete.

- [ ] **Step 3: Verify `just check` still green**

```bash
just check
```

Expected: still passes.

- [ ] **Step 4: Commit**

```bash
git add ONBOARDING.md
git commit -m "$(cat <<'EOF'
Refresh ONBOARDING.md after bootstrap

Bootstrap is complete: project.yml, justfile, CI, Sources/
skeleton, smoke test all in place. `just check` is green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

**End of Phase 1.** Verify state:

```bash
just check  # green
git log --oneline | head -15  # 10 new commits (1.1 through 1.10) on top of the existing 3
```

## Phase 2 — Core domain

Goal: a fully tested `FitiCore` (Model + Ports + Editor + AppController) compiled into both targets, with every behavior covered by Swift Testing cases. No AppKit or networking code. At phase end, `just test` runs ~40 tests in under 1 second, and the Editor + AppController together model the spec's `FitiDoc` semantics.

Drop `Sources/Core/_CoreBootstrap.swift` at the first task that adds a real Core file (it's no longer needed).

### Task 2.1: `RGBA` model

**Files:**
- Create: `Sources/Core/Model/RGBA.swift`
- Create: `Tests/CoreTests/ModelTests/RGBATests.swift`
- Delete: `Sources/Core/_CoreBootstrap.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CoreTests/ModelTests/RGBATests.swift
// ABOUTME: Tests for the RGBA color model — sRGB, 0...1 components.
// ABOUTME: Phase 2.1 of the POC plan.

import Testing

@Suite("RGBA")
struct RGBATests {
    @Test("constructs with rgba components")
    func construct() {
        let c = RGBA(r: 1, g: 0.5, b: 0, a: 1)
        #expect(c.r == 1)
        #expect(c.g == 0.5)
        #expect(c.b == 0)
        #expect(c.a == 1)
    }

    @Test("is equatable")
    func equatable() {
        #expect(RGBA(r: 1, g: 0, b: 0, a: 1) == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(RGBA(r: 1, g: 0, b: 0, a: 1) != RGBA(r: 0, g: 1, b: 0, a: 1))
    }
}
```

Note on imports: the `fiti-unit` test target compiles `Sources/Core` directly alongside `Tests/`, so Core types live in the same compilation unit as the tests. No `@testable import` is needed (and would fail because there's no separate framework to import). Tests use `import Testing` plus whatever else they actually need — `import Foundation` is fine when a test uses `JSONEncoder`/`Date`/etc. (see Task 2.3's `PointerTypeTests` for an example). This was confirmed during Task 2.1 (see commit `95220e8`).

- [ ] **Step 2: Run the test, expect failure**

```bash
just test
```

Expected: build error — `RGBA` is undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Core/Model/RGBA.swift
// ABOUTME: sRGB color with linear-floating-point components in 0...1.
// ABOUTME: Stored on every Stroke; serialized in HTTP /doc responses.

import Foundation

public struct RGBA: Equatable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
```

- [ ] **Step 4: Delete the bootstrap stub**

```bash
git rm Sources/Core/_CoreBootstrap.swift
```

- [ ] **Step 5: Run the test, expect pass**

```bash
just test
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Model/RGBA.swift Tests/CoreTests/ModelTests/RGBATests.swift
git commit -m "$(cat <<'EOF'
Add RGBA model

sRGB color stored on every Stroke. Drop the _CoreBootstrap.swift stub
now that real Core code exists.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.2: `StrokePoint` model

**Files:**
- Create: `Sources/Core/Model/StrokePoint.swift`
- Create: `Tests/CoreTests/ModelTests/StrokePointTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/ModelTests/StrokePointTests.swift
// ABOUTME: Tests for the StrokePoint — (x, y, pressure) triple.

import Testing

@Suite("StrokePoint")
struct StrokePointTests {
    @Test("constructs with x, y, pressure")
    func construct() {
        let p = StrokePoint(x: 10, y: 20, pressure: 0.5)
        #expect(p.x == 10)
        #expect(p.y == 20)
        #expect(p.pressure == 0.5)
    }

    @Test("default pressure is 0.5 (mouse default)")
    func defaultPressure() {
        let p = StrokePoint(x: 0, y: 0)
        #expect(p.pressure == 0.5)
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
just test
```

Expected: `StrokePoint` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Model/StrokePoint.swift
// ABOUTME: One sample on a freehand stroke — (x, y, pressure) in logical points.
// ABOUTME: Pressure defaults to 0.5 for mouse input; real values come from pen later.

import Foundation

public struct StrokePoint: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var pressure: Double

    public init(x: Double, y: Double, pressure: Double = 0.5) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/StrokePoint.swift Tests/CoreTests/ModelTests/StrokePointTests.swift
git commit -m "Add StrokePoint model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.3: `Transform`, `Size`, `PointerType`

Three tiny types in one task — each is a record with no behavior, so batching keeps the plan readable.

**Files:**
- Create: `Sources/Core/Model/Transform.swift`
- Create: `Sources/Core/Model/Size.swift`
- Create: `Sources/Core/Model/PointerType.swift`
- Create: `Tests/CoreTests/ModelTests/TransformTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/ModelTests/TransformTests.swift
// ABOUTME: Tests for Transform, Size, PointerType — the small model types.

import Testing

@Suite("Transform")
struct TransformTests {
    @Test("identity is x=0,y=0,scale=1,rotate=0")
    func identity() {
        let t = Transform.identity
        #expect(t.x == 0)
        #expect(t.y == 0)
        #expect(t.scale == 1)
        #expect(t.rotate == 0)
    }
}

@Suite("Size")
struct SizeTests {
    @Test("constructs with width and height")
    func construct() {
        let s = Size(width: 100, height: 200)
        #expect(s.width == 100)
        #expect(s.height == 200)
    }
}

@Suite("PointerType")
struct PointerTypeTests {
    @Test("encodes as lowercased string")
    func encoding() throws {
        let data = try JSONEncoder().encode(PointerType.mouse)
        #expect(String(data: data, encoding: .utf8) == "\"mouse\"")
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement all three**

```swift
// Sources/Core/Model/Transform.swift
// ABOUTME: Per-stroke affine transform applied on top of frozen point geometry.
// ABOUTME: POC always uses .identity; drag/resize/rotate edits land later.

import Foundation

public struct Transform: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var rotate: Double  // degrees

    public init(x: Double, y: Double, scale: Double, rotate: Double) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotate = rotate
    }

    public static let identity = Transform(x: 0, y: 0, scale: 1, rotate: 0)
}
```

```swift
// Sources/Core/Model/Size.swift
// ABOUTME: Logical-point size for canvas dimensions.
// ABOUTME: Avoids importing CoreGraphics in Sources/Core.

import Foundation

public struct Size: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
```

```swift
// Sources/Core/Model/PointerType.swift
// ABOUTME: Where a stroke's input came from. Drives perfect-freehand's
// ABOUTME: simulatePressure decision when we port that algorithm later.

import Foundation

public enum PointerType: String, Equatable, Codable, Sendable {
    case mouse, pen, touch
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/Transform.swift Sources/Core/Model/Size.swift Sources/Core/Model/PointerType.swift Tests/CoreTests/ModelTests/TransformTests.swift
git commit -m "Add Transform, Size, PointerType models

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.4: `Stroke` model

**Files:**
- Create: `Sources/Core/Model/Stroke.swift`
- Create: `Tests/CoreTests/ModelTests/StrokeTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/ModelTests/StrokeTests.swift
// ABOUTME: Tests for the Stroke value type.

import Testing

@Suite("Stroke")
struct StrokeTests {
    @Test("constructs with all fields")
    func construct() {
        let s = Stroke(
            id: "stroke-1",
            color: RGBA(r: 1, g: 0, b: 0, a: 1),
            width: 4,
            transform: .identity,
            points: [StrokePoint(x: 0, y: 0)],
            pointerType: .mouse,
            pressureEnabled: false,
            createdAt: 100
        )
        #expect(s.id == "stroke-1")
        #expect(s.color.r == 1)
        #expect(s.width == 4)
        #expect(s.transform == .identity)
        #expect(s.points.count == 1)
        #expect(s.pointerType == .mouse)
        #expect(s.pressureEnabled == false)
        #expect(s.createdAt == 100)
    }

    @Test("appending points produces a new value (struct semantics)")
    func valueSemantics() {
        var a = Stroke(id: "s", color: RGBA(r:0,g:0,b:0,a:1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let b = a
        a.points.append(StrokePoint(x: 1, y: 1))
        #expect(a.points.count == 1)
        #expect(b.points.count == 0)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Model/Stroke.swift
// ABOUTME: One drawn stroke — frozen geometry + per-stroke metadata.
// ABOUTME: Points freeze at endStroke; later edits target `transform`.

import Foundation

public typealias StrokeId = String

public struct Stroke: Equatable, Codable, Sendable {
    public let id: StrokeId
    public var color: RGBA
    public var width: Double
    public var transform: Transform
    public var points: [StrokePoint]
    public let pointerType: PointerType
    public let pressureEnabled: Bool
    public let createdAt: Double  // seconds since epoch

    public init(
        id: StrokeId,
        color: RGBA,
        width: Double,
        transform: Transform,
        points: [StrokePoint],
        pointerType: PointerType,
        pressureEnabled: Bool,
        createdAt: Double
    ) {
        self.id = id
        self.color = color
        self.width = width
        self.transform = transform
        self.points = points
        self.pointerType = pointerType
        self.pressureEnabled = pressureEnabled
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Model/Stroke.swift Tests/CoreTests/ModelTests/StrokeTests.swift
git commit -m "Add Stroke model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.5: `FitiDoc` model

**Files:**
- Create: `Sources/Core/Model/FitiDoc.swift`
- Create: `Tests/CoreTests/ModelTests/FitiDocTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/ModelTests/FitiDocTests.swift
// ABOUTME: Tests for FitiDoc — the keyed-map + ordered-list document shape.

import Testing

@Suite("FitiDoc")
struct FitiDocTests {
    @Test("empty has no strokes")
    func empty() {
        let doc = FitiDoc.empty
        #expect(doc.strokes.isEmpty)
        #expect(doc.strokeOrder.isEmpty)
    }

    @Test("ordering is independent of map iteration")
    func order() {
        var doc = FitiDoc.empty
        let s1 = Stroke(id: "a", color: RGBA(r:0,g:0,b:0,a:1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let s2 = Stroke(id: "b", color: RGBA(r:0,g:0,b:0,a:1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        doc.strokes["a"] = s1
        doc.strokes["b"] = s2
        doc.strokeOrder = ["b", "a"]
        #expect(doc.strokeOrder == ["b", "a"])
    }
}
```

- [ ] **Step 2-5: Run failing, implement, run passing, commit**

```swift
// Sources/Core/Model/FitiDoc.swift
// ABOUTME: The drawing document — keyed-map of strokes plus an ordered list.
// ABOUTME: Scratch-style: map for identity, list for z-order. CRDT-friendly.

import Foundation

public struct FitiDoc: Equatable, Codable, Sendable {
    public var strokes: [StrokeId: Stroke]
    public var strokeOrder: [StrokeId]

    public init(strokes: [StrokeId: Stroke] = [:], strokeOrder: [StrokeId] = []) {
        self.strokes = strokes
        self.strokeOrder = strokeOrder
    }

    public static let empty = FitiDoc()
}
```

Commit:

```bash
git add Sources/Core/Model/FitiDoc.swift Tests/CoreTests/ModelTests/FitiDocTests.swift
git commit -m "Add FitiDoc model

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.6: `Clock` port + test doubles

**Files:**
- Create: `Sources/Core/Ports/Clock.swift`
- Create: `Tests/CoreTests/Doubles/VirtualClock.swift`
- Create: `Tests/CoreTests/Doubles/ClockTests.swift`

- [ ] **Step 1: Write failing test for `VirtualClock`**

```swift
// Tests/CoreTests/Doubles/ClockTests.swift
// ABOUTME: Tests for the VirtualClock test double used to drive deterministic
// ABOUTME: createdAt timestamps in Editor tests.

import Testing

@Suite("VirtualClock")
struct ClockTests {
    @Test("returns set time")
    func setTime() {
        let clock = VirtualClock(now: 42)
        #expect(clock.now() == 42)
    }

    @Test("advance moves the clock forward")
    func advance() {
        let clock = VirtualClock(now: 0)
        clock.advance(by: 5)
        #expect(clock.now() == 5)
        clock.advance(by: 2.5)
        #expect(clock.now() == 7.5)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement port and double**

```swift
// Sources/Core/Ports/Clock.swift
// ABOUTME: Time source port. Production wires a SystemClock (in Sources/App);
// ABOUTME: tests wire VirtualClock for determinism.

import Foundation

public protocol Clock: AnyObject, Sendable {
    func now() -> Double
}
```

```swift
// Tests/CoreTests/Doubles/VirtualClock.swift
// ABOUTME: Deterministic Clock for tests. Time advances only on explicit calls.

import Foundation

public final class VirtualClock: Clock, @unchecked Sendable {
    private var current: Double

    public init(now: Double = 0) {
        self.current = now
    }

    public func now() -> Double {
        current
    }

    public func advance(by seconds: Double) {
        current += seconds
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Ports/Clock.swift Tests/CoreTests/Doubles/
git commit -m "Add Clock port and VirtualClock test double

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.7: `IdGenerator` port + `SeededIdGenerator`

**Files:**
- Create: `Sources/Core/Ports/IdGenerator.swift`
- Create: `Tests/CoreTests/Doubles/SeededIdGenerator.swift`
- Create: `Tests/CoreTests/Doubles/IdGeneratorTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/Doubles/IdGeneratorTests.swift
// ABOUTME: Tests for the SeededIdGenerator test double.

import Testing

@Suite("SeededIdGenerator")
struct IdGeneratorTests {
    @Test("produces deterministic monotonic ids")
    func deterministic() {
        let gen = SeededIdGenerator(prefix: "s")
        #expect(gen.newStrokeId() == "s-1")
        #expect(gen.newStrokeId() == "s-2")
        #expect(gen.newStrokeId() == "s-3")
    }

    @Test("two generators with same prefix produce same sequence")
    func reproducible() {
        let a = SeededIdGenerator(prefix: "s")
        let b = SeededIdGenerator(prefix: "s")
        #expect(a.newStrokeId() == b.newStrokeId())
        #expect(a.newStrokeId() == b.newStrokeId())
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Ports/IdGenerator.swift
// ABOUTME: Stroke-id factory port. Production uses UUID-backed ids
// ABOUTME: (Sources/App); tests use SeededIdGenerator for determinism.

import Foundation

public protocol IdGenerator: AnyObject, Sendable {
    func newStrokeId() -> StrokeId
}
```

```swift
// Tests/CoreTests/Doubles/SeededIdGenerator.swift
// ABOUTME: Counter-based IdGenerator for deterministic test ids.
// ABOUTME: Returns "{prefix}-1", "{prefix}-2", ...

import Foundation

public final class SeededIdGenerator: IdGenerator, @unchecked Sendable {
    private let prefix: String
    private var counter: Int = 0

    public init(prefix: String = "stroke") {
        self.prefix = prefix
    }

    public func newStrokeId() -> StrokeId {
        counter += 1
        return "\(prefix)-\(counter)"
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Ports/IdGenerator.swift Tests/CoreTests/Doubles/SeededIdGenerator.swift Tests/CoreTests/Doubles/IdGeneratorTests.swift
git commit -m "Add IdGenerator port and SeededIdGenerator test double

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.8: `InverseOp` enum

**Files:**
- Create: `Sources/Core/Editor/InverseOp.swift`
- Create: `Tests/CoreTests/EditorTests/InverseOpTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/EditorTests/InverseOpTests.swift
// ABOUTME: Tests for InverseOp + StrokeRestoreEntry — the data records
// ABOUTME: that describe how to reverse a doc mutation.

import Testing

@Suite("InverseOp")
struct InverseOpTests {
    @Test("StrokeRestoreEntry is equatable")
    func restoreEquatable() {
        let s = Stroke(id: "a", color: RGBA(r:0,g:0,b:0,a:1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(StrokeRestoreEntry(snapshot: s, atIndex: 0) == StrokeRestoreEntry(snapshot: s, atIndex: 0))
        #expect(StrokeRestoreEntry(snapshot: s, atIndex: 0) != StrokeRestoreEntry(snapshot: s, atIndex: 1))
    }

    @Test("deleteStroke / restoreStroke / deleteStrokes / restoreStrokes are equatable")
    func opEquatable() {
        let s = Stroke(id: "a", color: RGBA(r:0,g:0,b:0,a:1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(InverseOp.deleteStroke("a") == .deleteStroke("a"))
        #expect(InverseOp.restoreStroke(snapshot: s, atIndex: 0) == .restoreStroke(snapshot: s, atIndex: 0))
        #expect(InverseOp.deleteStrokes(["a"]) == .deleteStrokes(["a"]))
        let entry = StrokeRestoreEntry(snapshot: s, atIndex: 0)
        #expect(InverseOp.restoreStrokes(entries: [entry]) == .restoreStrokes(entries: [entry]))
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Editor/InverseOp.swift
// ABOUTME: Data records describing how to reverse a mutation.
// ABOUTME: Editor.applyInverse consumes one and produces the paired inverse.

import Foundation

public struct StrokeRestoreEntry: Equatable, Sendable {
    public let snapshot: Stroke
    public let atIndex: Int

    public init(snapshot: Stroke, atIndex: Int) {
        self.snapshot = snapshot
        self.atIndex = atIndex
    }
}

public enum InverseOp: Equatable, Sendable {
    case deleteStroke(StrokeId)
    case restoreStroke(snapshot: Stroke, atIndex: Int)
    case deleteStrokes([StrokeId])
    case restoreStrokes(entries: [StrokeRestoreEntry])
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/InverseOp.swift Tests/CoreTests/EditorTests/InverseOpTests.swift
git commit -m "Add InverseOp + StrokeRestoreEntry

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.9: `Editor` skeleton + `startStroke`

**Files:**
- Create: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorStartStrokeTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/EditorTests/EditorStartStrokeTests.swift
// ABOUTME: Tests for Editor.startStroke — creates an in-progress stroke
// ABOUTME: with the supplied color/width/pointerType and an empty points array.

import Testing

@Suite("Editor.startStroke")
struct EditorStartStrokeTests {
    private func makeEditor(clockNow: Double = 100) -> (Editor, SeededIdGenerator, VirtualClock) {
        let clock = VirtualClock(now: clockNow)
        let ids = SeededIdGenerator(prefix: "s")
        let editor = Editor(clock: clock, ids: ids)
        return (editor, ids, clock)
    }

    @Test("creates a new stroke with the supplied parameters")
    func basics() {
        let (editor, _, _) = makeEditor()
        let id = editor.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        #expect(id == "s-1")
        #expect(editor.currentStrokeId == "s-1")
        let stroke = editor.doc.strokes["s-1"]
        #expect(stroke != nil)
        #expect(stroke?.color.r == 1)
        #expect(stroke?.width == 4)
        #expect(stroke?.transform == .identity)
        #expect(stroke?.points.isEmpty == true)
        #expect(stroke?.pointerType == .mouse)
        #expect(stroke?.pressureEnabled == false)
        #expect(stroke?.createdAt == 100)
    }

    @Test("appends id to strokeOrder")
    func appendsToOrder() {
        let (editor, _, _) = makeEditor()
        _ = editor.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        #expect(editor.doc.strokeOrder == ["s-1"])
    }

    @Test("pushes a deleteStroke onto the undo stack")
    func pushesUndo() {
        let (editor, _, _) = makeEditor()
        _ = editor.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        #expect(editor.undoStack == [.deleteStroke("s-1")])
        #expect(editor.redoStack.isEmpty)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement Editor with `startStroke` only**

```swift
// Sources/Core/Editor/Editor.swift
// ABOUTME: Sole mutation surface for FitiDoc. Owns undo/redo via InverseOp.
// ABOUTME: All edits go through methods on this class; no doc mutation elsewhere.

import Foundation

public enum ChangeKind: Sendable {
    case local, remote
}

public typealias Cancellable = () -> Void

public final class Editor {
    public private(set) var doc: FitiDoc = .empty
    public private(set) var undoStack: [InverseOp] = []
    public private(set) var redoStack: [InverseOp] = []
    public private(set) var currentStrokeId: StrokeId?

    private let clock: Clock
    private let ids: IdGenerator
    private var listeners: [UUID: (ChangeKind) -> Void] = [:]

    public init(clock: Clock, ids: IdGenerator) {
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Drawing

    @discardableResult
    public func startStroke(color: RGBA, width: Double, pointerType: PointerType) -> StrokeId {
        precondition(currentStrokeId == nil, "stroke already in progress; call endStroke first")
        let id = ids.newStrokeId()
        let stroke = Stroke(
            id: id,
            color: color,
            width: width,
            transform: .identity,
            points: [],
            pointerType: pointerType,
            pressureEnabled: false,
            createdAt: clock.now()
        )
        doc.strokes[id] = stroke
        doc.strokeOrder.append(id)
        currentStrokeId = id
        pushUndo(.deleteStroke(id))
        emit(.local)
        return id
    }

    // MARK: - Undo plumbing

    private func pushUndo(_ op: InverseOp) {
        undoStack.append(op)
        redoStack.removeAll()
    }

    // MARK: - Listeners

    @discardableResult
    public func subscribe(_ listener: @escaping (ChangeKind) -> Void) -> Cancellable {
        let token = UUID()
        listeners[token] = listener
        return { [weak self] in self?.listeners.removeValue(forKey: token) }
    }

    private func emit(_ kind: ChangeKind) {
        for listener in listeners.values { listener(kind) }
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorStartStrokeTests.swift
git commit -m "Add Editor skeleton with startStroke

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.10: `Editor.appendPoint` and `endStroke`

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorDrawingTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/EditorTests/EditorDrawingTests.swift
// ABOUTME: Tests for appendPoint + endStroke — the rest of the drawing path.

import Testing

@Suite("Editor draw cycle")
struct EditorDrawingTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("appendPoint appends to the in-progress stroke")
    func appendsToCurrent() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 5, y: 5))
        #expect(e.doc.strokes["s-1"]?.points.count == 2)
    }

    @Test("appendPoint is a no-op when no stroke is in progress")
    func appendNoOp() {
        let e = makeEditor()
        e.appendPoint(StrokePoint(x: 0, y: 0))
        #expect(e.doc.strokes.isEmpty)
    }

    @Test("endStroke clears currentStrokeId; doc retains the stroke")
    func endStrokeFreezes() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 1, y: 1))
        e.endStroke()
        #expect(e.currentStrokeId == nil)
        #expect(e.doc.strokes["s-1"]?.points.count == 1)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add methods to Editor**

Insert these methods in `Sources/Core/Editor/Editor.swift` after `startStroke`:

```swift
public func appendPoint(_ point: StrokePoint) {
    guard let id = currentStrokeId else { return }
    doc.strokes[id]?.points.append(point)
    emit(.local)
}

public func endStroke() {
    guard currentStrokeId != nil else { return }
    currentStrokeId = nil
    emit(.local)
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorDrawingTests.swift
git commit -m "Add Editor.appendPoint and endStroke

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.11: `Editor.undo` / `Editor.redo` for the draw-and-undo case

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorUndoRedoTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/EditorTests/EditorUndoRedoTests.swift
// ABOUTME: Tests for undo/redo of completed strokes — the round-trip.

import Testing

@Suite("Editor undo / redo")
struct EditorUndoRedoTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    private func drawOne(_ e: Editor) {
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 1, y: 1))
        e.endStroke()
    }

    @Test("undo removes the last completed stroke")
    func undoRemoves() {
        let e = makeEditor()
        drawOne(e)
        #expect(e.doc.strokes.count == 1)
        let did = e.undo()
        #expect(did)
        #expect(e.doc.strokes.isEmpty)
        #expect(e.doc.strokeOrder.isEmpty)
    }

    @Test("redo restores the undone stroke byte-identically")
    func redoRestores() {
        let e = makeEditor()
        drawOne(e)
        let before = e.doc
        _ = e.undo()
        _ = e.redo()
        #expect(e.doc == before)
    }

    @Test("undo with empty stack returns false")
    func undoEmpty() {
        let e = makeEditor()
        #expect(e.undo() == false)
    }

    @Test("a new stroke after undo clears the redo stack")
    func newStrokeClearsRedo() {
        let e = makeEditor()
        drawOne(e)
        _ = e.undo()
        #expect(e.redoStack.isEmpty == false)
        drawOne(e)
        #expect(e.redoStack.isEmpty)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add undo/redo + applyInverse**

Insert in `Sources/Core/Editor/Editor.swift`:

```swift
// MARK: - Undo / redo

@discardableResult
public func undo() -> Bool {
    guard let op = undoStack.popLast() else { return false }
    if let inverse = applyInverse(op) {
        redoStack.append(inverse)
    }
    emit(.local)
    return true
}

@discardableResult
public func redo() -> Bool {
    guard let op = redoStack.popLast() else { return false }
    if let inverse = applyInverse(op) {
        undoStack.append(inverse)
    }
    emit(.local)
    return true
}

private func applyInverse(_ op: InverseOp) -> InverseOp? {
    switch op {
    case .deleteStroke(let id):
        guard let stroke = doc.strokes[id] else { return nil }
        let atIndex = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
        doc.strokes.removeValue(forKey: id)
        doc.strokeOrder.removeAll { $0 == id }
        return .restoreStroke(snapshot: stroke, atIndex: atIndex)

    case .restoreStroke(let snapshot, let atIndex):
        doc.strokes[snapshot.id] = snapshot
        let insertAt = max(0, min(atIndex, doc.strokeOrder.count))
        doc.strokeOrder.insert(snapshot.id, at: insertAt)
        return .deleteStroke(snapshot.id)

    case .deleteStrokes(let ids):
        var entries: [StrokeRestoreEntry] = []
        for id in ids {
            guard let s = doc.strokes[id] else { continue }
            let idx = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
            entries.append(StrokeRestoreEntry(snapshot: s, atIndex: idx))
        }
        for id in ids {
            doc.strokes.removeValue(forKey: id)
            doc.strokeOrder.removeAll { $0 == id }
        }
        return .restoreStrokes(entries: entries)

    case .restoreStrokes(let entries):
        // Re-insert in original deletion order so each atIndex is meaningful relative
        // to the strokeOrder state it was captured against.
        let reversed = Array(entries.reversed())
        for e in reversed {
            doc.strokes[e.snapshot.id] = e.snapshot
            let insertAt = max(0, min(e.atIndex, doc.strokeOrder.count))
            doc.strokeOrder.insert(e.snapshot.id, at: insertAt)
        }
        return .deleteStrokes(entries.map { $0.snapshot.id })
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorUndoRedoTests.swift
git commit -m "Add Editor undo/redo with applyInverse

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.12: `Editor.eraseStroke`

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorEraseTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/EditorTests/EditorEraseTests.swift
// ABOUTME: Tests for eraseStroke — delete-by-id with undo support.

import Testing

@Suite("Editor.eraseStroke")
struct EditorEraseTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("erases an existing stroke and removes from strokeOrder")
    func erases() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        e.endStroke()
        let did = e.eraseStroke("s-1")
        #expect(did)
        #expect(e.doc.strokes.isEmpty)
        #expect(e.doc.strokeOrder.isEmpty)
    }

    @Test("returns false for unknown stroke")
    func unknown() {
        let e = makeEditor()
        #expect(e.eraseStroke("nope") == false)
    }

    @Test("undo of erase restores the stroke at its original index")
    func undoRestoresAtIndex() {
        let e = makeEditor()
        // Draw two strokes
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        #expect(e.doc.strokeOrder == ["s-1", "s-2"])
        // Erase the first
        _ = e.eraseStroke("s-1")
        #expect(e.doc.strokeOrder == ["s-2"])
        // Undo
        _ = e.undo()
        #expect(e.doc.strokeOrder == ["s-1", "s-2"])
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add `eraseStroke`**

Insert in `Sources/Core/Editor/Editor.swift` after `endStroke`:

```swift
@discardableResult
public func eraseStroke(_ id: StrokeId) -> Bool {
    guard let stroke = doc.strokes[id] else { return false }
    let atIndex = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
    doc.strokes.removeValue(forKey: id)
    doc.strokeOrder.removeAll { $0 == id }
    pushUndo(.restoreStroke(snapshot: stroke, atIndex: atIndex))
    emit(.local)
    return true
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorEraseTests.swift
git commit -m "Add Editor.eraseStroke

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.13: `Editor.clear`

**Files:**
- Modify: `Sources/Core/Editor/Editor.swift`
- Create: `Tests/CoreTests/EditorTests/EditorClearTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/EditorTests/EditorClearTests.swift
// ABOUTME: Tests for clear — empties the doc but is undo-able.

import Testing

@Suite("Editor.clear")
struct EditorClearTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("empties doc")
    func empties() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        e.clear()
        #expect(e.doc.strokes.isEmpty)
        #expect(e.doc.strokeOrder.isEmpty)
    }

    @Test("undo restores all strokes at their original strokeOrder positions")
    func undoRestoresAll() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        let before = e.doc
        e.clear()
        _ = e.undo()
        #expect(e.doc == before)
    }

    @Test("clear on an empty doc is a no-op (doesn't push undo)")
    func clearEmpty() {
        let e = makeEditor()
        e.clear()
        #expect(e.undoStack.isEmpty)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add `clear`**

Insert in `Sources/Core/Editor/Editor.swift`:

```swift
public func clear() {
    guard !doc.strokeOrder.isEmpty else { return }
    let entries: [StrokeRestoreEntry] = doc.strokeOrder.enumerated().compactMap { idx, id in
        guard let s = doc.strokes[id] else { return nil }
        return StrokeRestoreEntry(snapshot: s, atIndex: idx)
    }
    doc.strokes.removeAll()
    doc.strokeOrder.removeAll()
    if currentStrokeId != nil { currentStrokeId = nil }
    pushUndo(.restoreStrokes(entries: entries))
    emit(.local)
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/Editor.swift Tests/CoreTests/EditorTests/EditorClearTests.swift
git commit -m "Add Editor.clear

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.14: `Editor.subscribe` listener test

**Files:**
- Create: `Tests/CoreTests/EditorTests/EditorSubscribeTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/EditorTests/EditorSubscribeTests.swift
// ABOUTME: Tests for the subscribe/unsubscribe lifecycle.

import Testing

@Suite("Editor.subscribe")
struct EditorSubscribeTests {
    @Test("notifies on local change")
    func notifies() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var count = 0
        let unsubscribe = e.subscribe { kind in
            #expect(kind == .local)
            count += 1
        }
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        e.endStroke()
        #expect(count == 2)
        unsubscribe()
    }

    @Test("unsubscribe stops notifications")
    func unsubscribe() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var count = 0
        let cancel = e.subscribe { _ in count += 1 }
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse)
        cancel()
        e.endStroke()
        #expect(count == 1)
    }
}
```

- [ ] **Step 2-4: Run, verify pass (no implementation change needed — already wired)**

- [ ] **Step 5: Commit**

```bash
git add Tests/CoreTests/EditorTests/EditorSubscribeTests.swift
git commit -m "Add subscribe/unsubscribe tests for Editor

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.15: `Renderer` / `WindowControl` / `InputSource` ports + `RenderFrame`

**Files:**
- Create: `Sources/Core/Ports/RenderFrame.swift`
- Create: `Sources/Core/Ports/Renderer.swift`
- Create: `Sources/Core/Ports/WindowControl.swift`
- Create: `Sources/Core/Ports/InputSource.swift`
- Create: `Tests/CoreTests/Doubles/RecordingRenderer.swift`
- Create: `Tests/CoreTests/Doubles/RecordingWindow.swift`
- Create: `Tests/CoreTests/Doubles/PortDoublesTests.swift`

- [ ] **Step 1: Write failing test for the doubles**

```swift
// Tests/CoreTests/Doubles/PortDoublesTests.swift
// ABOUTME: Tests for the in-memory adapters used by AppController tests.

import Testing

@Suite("Port doubles")
struct PortDoublesTests {
    @Test("RecordingRenderer captures every frame")
    func recordingRenderer() {
        let r = RecordingRenderer()
        let frame = RenderFrame(strokes: [], inProgress: nil, canvasSize: Size(width: 100, height: 100))
        r.render(frame)
        r.render(frame)
        #expect(r.frames.count == 2)
    }

    @Test("RecordingWindow records click-through and focus calls")
    func recordingWindow() {
        let w = RecordingWindow()
        w.setClickThrough(true)
        w.setClickThrough(false)
        w.focus()
        #expect(w.clickThroughHistory == [true, false])
        #expect(w.focusCount == 1)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement the ports and doubles**

```swift
// Sources/Core/Ports/RenderFrame.swift
// ABOUTME: Snapshot a Renderer needs to draw the current state.
// ABOUTME: Built from Editor state by the wiring layer.

import Foundation

public struct RenderFrame: Equatable, Sendable {
    public var strokes: [Stroke]            // committed, in strokeOrder
    public var inProgress: Stroke?
    public var canvasSize: Size             // logical points

    public init(strokes: [Stroke], inProgress: Stroke?, canvasSize: Size) {
        self.strokes = strokes
        self.inProgress = inProgress
        self.canvasSize = canvasSize
    }
}
```

```swift
// Sources/Core/Ports/Renderer.swift
// ABOUTME: Render port — adapters realize this with CGContext / off-screen contexts / recording.

import Foundation

public protocol Renderer: AnyObject {
    func render(_ frame: RenderFrame)
}
```

```swift
// Sources/Core/Ports/WindowControl.swift
// ABOUTME: Window port. AppKit adapter conforms; tests use a recording double.

import Foundation

public protocol WindowControl: AnyObject {
    func setClickThrough(_ enabled: Bool)
    func focus()
}
```

```swift
// Sources/Core/Ports/InputSource.swift
// ABOUTME: Input port. NSEvent-based AppKit adapter conforms; HTTP injection
// ABOUTME: takes the same path by calling AppController directly.

import Foundation

public protocol InputSource: AnyObject {
    var onPointerDown: ((StrokePoint) -> Void)? { get set }
    var onPointerMoved: ((StrokePoint) -> Void)? { get set }
    var onPointerUp:    (() -> Void)?            { get set }
    var onActivate:     (() -> Void)?            { get set }
    var onDeactivate:   (() -> Void)?            { get set }
    var onClear:        (() -> Void)?            { get set }
}
```

```swift
// Tests/CoreTests/Doubles/RecordingRenderer.swift
// ABOUTME: In-memory Renderer for tests. Captures every frame for assertion.

import Foundation

public final class RecordingRenderer: Renderer {
    public private(set) var frames: [RenderFrame] = []
    public init() {}
    public func render(_ frame: RenderFrame) { frames.append(frame) }
}
```

```swift
// Tests/CoreTests/Doubles/RecordingWindow.swift
// ABOUTME: In-memory WindowControl for AppController tests.

import Foundation

public final class RecordingWindow: WindowControl {
    public private(set) var clickThroughHistory: [Bool] = []
    public private(set) var focusCount: Int = 0
    public init() {}
    public func setClickThrough(_ enabled: Bool) { clickThroughHistory.append(enabled) }
    public func focus() { focusCount += 1 }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Ports/ Tests/CoreTests/Doubles/RecordingRenderer.swift Tests/CoreTests/Doubles/RecordingWindow.swift Tests/CoreTests/Doubles/PortDoublesTests.swift
git commit -m "Add Renderer / WindowControl / InputSource ports plus doubles

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.16: `RenderFrame.from(editor:)` helper

**Files:**
- Create: `Sources/Core/Editor/RenderFrame+from.swift`
- Create: `Tests/CoreTests/EditorTests/RenderFrameFromTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CoreTests/EditorTests/RenderFrameFromTests.swift
// ABOUTME: Tests for the RenderFrame.from(editor:canvasSize:) helper.

import Testing

@Suite("RenderFrame.from(editor:)")
struct RenderFrameFromTests {
    @Test("orders strokes by strokeOrder, exposes in-progress separately")
    func ordersStrokes() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r:1,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        _ = e.startStroke(color: RGBA(r:0,g:1,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        _ = e.startStroke(color: RGBA(r:0,g:0,b:1,a:1), width: 1, pointerType: .mouse) // in progress, no endStroke

        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 800, height: 600))
        #expect(frame.strokes.map { $0.id } == ["s-1", "s-2", "s-3"])
        // s-3 is also in the committed list since it's already in doc.strokes — but
        // inProgress reflects it for the renderer's two-canvas split.
        #expect(frame.inProgress?.id == "s-3")
        #expect(frame.canvasSize == Size(width: 800, height: 600))
    }

    @Test("no in-progress when no current stroke")
    func noInProgress() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r:0,g:0,b:0,a:1), width: 1, pointerType: .mouse); e.endStroke()
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        #expect(frame.inProgress == nil)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Editor/RenderFrame+from.swift
// ABOUTME: Convenience builder: assemble a RenderFrame from current Editor state.
// ABOUTME: Used by the App-layer wiring on every editor change notification.

import Foundation

public extension RenderFrame {
    static func from(editor: Editor, canvasSize: Size) -> RenderFrame {
        let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
        let inProgress = editor.currentStrokeId.flatMap { editor.doc.strokes[$0] }
        return RenderFrame(strokes: strokes, inProgress: inProgress, canvasSize: canvasSize)
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Editor/RenderFrame+from.swift Tests/CoreTests/EditorTests/RenderFrameFromTests.swift
git commit -m "Add RenderFrame.from(editor:canvasSize:)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.17: `AppController` skeleton + activate / deactivate

**Files:**
- Create: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/ActivationTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/AppControllerTests/ActivationTests.swift
// ABOUTME: Tests for AppController mode transitions on activate/deactivate.

import Testing

@Suite("AppController activation")
struct ActivationTests {
    private func make() -> (AppController, RecordingWindow) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        return (controller, window)
    }

    @Test("initial mode is inactive")
    func initial() {
        let (c, _) = make()
        #expect(c.mode == .inactive)
    }

    @Test("activate flips to activeIdle and disables click-through")
    func activate() {
        let (c, w) = make()
        c.activate()
        #expect(c.mode == .activeIdle)
        #expect(w.clickThroughHistory.last == false)
        #expect(w.focusCount == 1)
    }

    @Test("deactivate flips back to inactive and enables click-through")
    func deactivate() {
        let (c, w) = make()
        c.activate()
        c.deactivate()
        #expect(c.mode == .inactive)
        #expect(w.clickThroughHistory.last == true)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/Core/Control/AppController.swift
// ABOUTME: Activation state machine. Bridges raw pointer input to Editor
// ABOUTME: calls; owns click-through toggling via WindowControl.

import Foundation

public final class AppController {
    public enum Mode: Equatable, Sendable {
        case inactive
        case activeIdle
        case activeDrawing
    }

    public private(set) var mode: Mode = .inactive
    public let editor: Editor
    private let window: WindowControl

    // Drawing parameters used while in POC. Hardcoded here; the toolbar that
    // mutates these lands in a later phase.
    public var currentColor: RGBA = RGBA(r: 0.20, g: 0.80, b: 0.94, a: 1.0)
    public var currentWidth: Double = 6

    public init(editor: Editor, window: WindowControl) {
        self.editor = editor
        self.window = window
    }

    public func activate() {
        guard mode == .inactive else { return }
        mode = .activeIdle
        window.setClickThrough(false)
        window.focus()
    }

    public func deactivate() {
        guard mode != .inactive else { return }
        if mode == .activeDrawing { editor.endStroke() }
        mode = .inactive
        window.setClickThrough(true)
    }
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift Tests/CoreTests/AppControllerTests/ActivationTests.swift
git commit -m "Add AppController with activate / deactivate

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.18: `AppController` pointer routing

**Files:**
- Modify: `Sources/Core/Control/AppController.swift`
- Create: `Tests/CoreTests/AppControllerTests/PointerRoutingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/CoreTests/AppControllerTests/PointerRoutingTests.swift
// ABOUTME: Tests for AppController.pointerDown/Moved/Up — translates raw
// ABOUTME: pointer events into Editor stroke calls based on current mode.

import Testing

@Suite("AppController pointer routing")
struct PointerRoutingTests {
    private func make() -> AppController {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        return AppController(editor: editor, window: window)
    }

    @Test("pointerDown in activeIdle starts a stroke and seeds the first point")
    func downStartsStroke() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 20))
        #expect(c.mode == .activeDrawing)
        #expect(c.editor.currentStrokeId == "s-1")
        #expect(c.editor.doc.strokes["s-1"]?.points.first?.x == 10)
    }

    @Test("pointerMoved in activeDrawing appends a point")
    func moveAppends() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 1, y: 1))
        c.pointerMoved(StrokePoint(x: 2, y: 2))
        #expect(c.editor.doc.strokes["s-1"]?.points.count == 3)
    }

    @Test("pointerUp in activeDrawing ends the stroke and returns to activeIdle")
    func upEnds() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        #expect(c.mode == .activeIdle)
        #expect(c.editor.currentStrokeId == nil)
    }

    @Test("pointer events in inactive mode are ignored")
    func ignoredWhenInactive() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(c.mode == .inactive)
        #expect(c.editor.doc.strokes.isEmpty)
    }

    @Test("deactivate mid-draw ends the in-progress stroke")
    func deactivateMidDraw() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 1, y: 1))
        c.deactivate()
        #expect(c.mode == .inactive)
        #expect(c.editor.currentStrokeId == nil)
        #expect(c.editor.doc.strokes["s-1"]?.points.count == 2)  // both points retained
    }

    @Test("clear() empties the editor doc")
    func clearPassesThrough() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        #expect(c.editor.doc.strokeOrder.count == 1)
        c.clear()
        #expect(c.editor.doc.strokeOrder.isEmpty)
    }

    @Test("clear() while drawing ends the in-progress stroke first")
    func clearWhileDrawing() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.clear()
        #expect(c.editor.currentStrokeId == nil)
        #expect(c.editor.doc.strokeOrder.isEmpty)
        // Mode goes back to activeIdle since we ended the stroke but didn't deactivate.
        #expect(c.mode == .activeIdle)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add pointer methods**

Append to `Sources/Core/Control/AppController.swift`:

```swift
public func pointerDown(_ point: StrokePoint) {
    guard mode == .activeIdle else { return }
    _ = editor.startStroke(color: currentColor, width: currentWidth, pointerType: .mouse)
    editor.appendPoint(point)
    mode = .activeDrawing
}

public func pointerMoved(_ point: StrokePoint) {
    guard mode == .activeDrawing else { return }
    editor.appendPoint(point)
}

public func pointerUp() {
    guard mode == .activeDrawing else { return }
    editor.endStroke()
    mode = .activeIdle
}

public func clear() {
    // If a stroke is in progress, end it first so its points are committed
    // before they're cleared (matches the eraseStroke / undo invariant that
    // a snapshot of the doc is consistent after every public method returns).
    if mode == .activeDrawing {
        editor.endStroke()
        mode = .activeIdle
    }
    editor.clear()
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Control/AppController.swift Tests/CoreTests/AppControllerTests/PointerRoutingTests.swift
git commit -m "Add AppController pointer routing and clear() pass-through

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2.19: Phase 2 verification

- [ ] **Step 1: Confirm full test count and runtime**

```bash
just test
```

Expected: ~30-40 tests pass, total runtime well under 5 seconds (typically 200-500 ms once linked).

- [ ] **Step 2: Confirm hexagonal discipline**

```bash
./scripts/check-core-imports.sh
```

Expected: `Sources/Core import discipline: OK`.

- [ ] **Step 3: Confirm `just check` is green end-to-end**

```bash
just check
```

Expected: test + lint + build, all green.

- [ ] **Step 4: Update ONBOARDING.md**

Change the status paragraph to:

```
**Status: Core domain complete.** Phases 1 and 2 of the implementation plan are done — `project.yml`, `justfile`, CI, Swift Testing, the `FitiCore` module (Model + Editor + AppController + ports), and ~30 tests are in place. Phases 3–5 add the AppKit shell, dev HTTP server, and end-to-end wiring.
```

Mark these Key paths entries with `(complete)` or remove `(planned)`:

- `Sources/Core/` — pure domain (complete)
- `Tests/CoreTests/` — pure-Swift tests against `Sources/Core` (complete)

- [ ] **Step 5: Commit**

```bash
git add ONBOARDING.md
git commit -m "$(cat <<'EOF'
Refresh ONBOARDING.md after Phase 2

Core domain (Model, Editor, AppController, ports) complete with
test coverage. Phase 3 (AppKit shell) next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

**End of Phase 2.** What's done:
- Model types (`RGBA`, `StrokePoint`, `Transform`, `Size`, `PointerType`, `Stroke`, `FitiDoc`)
- Ports (`Clock`, `IdGenerator`, `Renderer`, `WindowControl`, `InputSource`) + their test doubles
- `InverseOp` + `StrokeRestoreEntry`
- `Editor`: `startStroke`, `appendPoint`, `endStroke`, `eraseStroke`, `clear`, `undo`, `redo`, `subscribe`
- `AppController`: `activate`, `deactivate`, `pointerDown`, `pointerMoved`, `pointerUp`, with mid-draw deactivation handling
- `RenderFrame.from(editor:canvasSize:)`

## Phase 3 — AppKit shell

Goal: a transparent always-on-top window that can capture mouse input and draw strokes from a `RenderFrame`. By phase end, `just run` launches an app that shows a click-through transparent window; pressing `Cmd+Opt+Z` captures the cursor and drawing works; pressing `Esc` releases it. No HTTP yet — verification is manual.

These adapters live in `Sources/AppKit/`, which is **not** compiled into the test target. There are no automated tests for them in POC. Verification is by build + manual run-through.

**Coordinate convention:** `StrokePoint` x/y are in logical points with top-origin (y increases downward). AppKit uses bottom-origin by default; the AppKit adapters convert at the boundary so the rest of the app (and the HTTP API) speaks top-origin consistently.

### Task 3.1: `TransparentWindow`

**Files:**
- Create: `Sources/AppKit/TransparentWindow.swift`
- Delete: `Sources/AppKit/_AppKitBootstrap.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/AppKit/TransparentWindow.swift
// ABOUTME: Borderless transparent always-on-top NSWindow covering the main screen.
// ABOUTME: Conforms to WindowControl — click-through toggle and focus.

import AppKit

public final class TransparentWindow: NSWindow, WindowControl {
    public init() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true   // start in click-through state
        self.acceptsMouseMovedEvents = true
        self.setFrame(frame, display: true)
    }

    // Allow this borderless window to become key so it can receive keyDown events.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    // MARK: - WindowControl

    public func setClickThrough(_ enabled: Bool) {
        self.ignoresMouseEvents = enabled
    }

    public func focus() {
        self.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Drop the bootstrap stub**

```bash
git rm Sources/AppKit/_AppKitBootstrap.swift
```

- [ ] **Step 3: Verify build**

```bash
just build
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppKit/TransparentWindow.swift
git commit -m "$(cat <<'EOF'
Add TransparentWindow

Borderless transparent NSWindow at .floating level covering the
main screen. Conforms to WindowControl. Initial state is
click-through; activate() calls focus() to take key status.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.2: `CanvasView`

**Files:**
- Create: `Sources/AppKit/CanvasView.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/AppKit/CanvasView.swift
// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Conforms to Renderer; called from the wiring layer on every editor change.

import AppKit
import CoreGraphics

public final class CanvasView: NSView, Renderer {
    private var currentFrame: RenderFrame?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Renderer

    public func render(_ frame: RenderFrame) {
        currentFrame = frame
        self.needsDisplay = true
    }

    public override var isFlipped: Bool { true }   // top-origin to match StrokePoint convention

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frame = currentFrame else { return }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in frame.strokes {
            drawStroke(stroke, in: ctx)
        }
        if let inProgress = frame.inProgress, inProgress.points.count > 0 {
            drawStroke(inProgress, in: ctx)
        }
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count > 0 else { return }
        ctx.setLineWidth(CGFloat(stroke.width))
        ctx.setStrokeColor(red: CGFloat(stroke.color.r), green: CGFloat(stroke.color.g),
                           blue: CGFloat(stroke.color.b), alpha: CGFloat(stroke.color.a))

        let path = CGMutablePath()
        let first = stroke.points[0]
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in stroke.points.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        ctx.addPath(path)
        ctx.strokePath()
    }
}
```

- [ ] **Step 2: Verify build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/AppKit/CanvasView.swift
git commit -m "$(cat <<'EOF'
Add CanvasView renderer

NSView with top-origin coords (isFlipped = true) that strokes
every point list via CGContext. POC quality — no perfect-freehand
yet, just uniform-width CGPath strokes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.3: `NSEventInputSource`

**Files:**
- Create: `Sources/AppKit/NSEventInputSource.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/AppKit/NSEventInputSource.swift
// ABOUTME: AppKit InputSource — wraps an NSView's mouse callbacks and a local
// ABOUTME: NSEvent key monitor (Cmd+Opt+Z to activate, Esc to deactivate).

import AppKit

public final class NSEventInputSource: InputSource {
    public var onPointerDown: ((StrokePoint) -> Void)?
    public var onPointerMoved: ((StrokePoint) -> Void)?
    public var onPointerUp: (() -> Void)?
    public var onActivate: (() -> Void)?
    public var onDeactivate: (() -> Void)?
    public var onClear: (() -> Void)?

    private let view: CanvasInputView
    private var keyMonitor: Any?

    public init(view: CanvasInputView) {
        self.view = view
        view.delegate = self
        installKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let chars = event.charactersIgnoringModifiers
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            // Cmd+Opt+Z → activate
            if chars == "z" && cmd && opt {
                self.onActivate?()
                return nil
            }
            // Cmd+K → clear (no Option). Matches terminal muscle memory.
            if chars == "k" && cmd && !opt {
                self.onClear?()
                return nil
            }
            // Esc → deactivate
            if event.keyCode == 53 {
                self.onDeactivate?()
                return nil
            }
            return event
        }
    }
}

extension NSEventInputSource: CanvasInputDelegate {
    public func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint) {
        onPointerDown?(StrokePoint(x: Double(point.x), y: Double(point.y)))
    }
    public func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint) {
        onPointerMoved?(StrokePoint(x: Double(point.x), y: Double(point.y)))
    }
    public func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint) {
        onPointerUp?()
    }
}

// MARK: - Companion view

public protocol CanvasInputDelegate: AnyObject {
    func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint)
    func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint)
    func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint)
}

/// NSView subclass that forwards mouse events to a delegate. The renderer
/// `CanvasView` is its own subclass; we put input on a sibling layer so the
/// renderer stays purely about drawing.
public final class CanvasInputView: NSView {
    public weak var delegate: CanvasInputDelegate?

    public override var isFlipped: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseDownAt: p)
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseDraggedAt: p)
    }
    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseUpAt: p)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/AppKit/NSEventInputSource.swift
git commit -m "$(cat <<'EOF'
Add NSEventInputSource and CanvasInputView

Mouse events flow through CanvasInputView (a thin NSView) and a
local key monitor handles Cmd+Opt+Z (activate) and Esc (deactivate).
Coordinates are top-origin via isFlipped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.4: Phase 3 smoke wiring + verification

This is a **temporary** smoke wiring in `main.swift` that we'll replace in Phase 5 once argv parsing and DevHTTP land. The goal is to launch the app and see the window.

**Files:**
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Replace `main.swift` with smoke wiring**

```swift
// Sources/App/main.swift
// ABOUTME: Phase 3 smoke wiring. Phase 5 will replace this with argv parsing
// ABOUTME: and dev HTTP wiring; for now it just shows that the AppKit shell works.

import AppKit
import Foundation

final class SmokeClock: Clock { func now() -> Double { Date().timeIntervalSince1970 } }
final class SmokeIds: IdGenerator {
    private var n = 0
    func newStrokeId() -> StrokeId { n += 1; return "stroke-\(n)" }
}

final class SmokeAppDelegate: NSObject, NSApplicationDelegate {
    var window: TransparentWindow!
    var canvas: CanvasView!
    var input: NSEventInputSource!
    var controller: AppController!
    var editor: Editor!
    var inputView: CanvasInputView!
    var subscription: Cancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        editor = Editor(clock: SmokeClock(), ids: SmokeIds())
        window = TransparentWindow()
        let frame = window.contentLayoutRect

        // Build the view stack: input on top, canvas underneath. Both transparent.
        let container = NSView(frame: frame)
        canvas = CanvasView(frame: frame)
        inputView = CanvasInputView(frame: frame)
        canvas.autoresizingMask = [.width, .height]
        inputView.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        container.addSubview(inputView)
        window.contentView = container

        controller = AppController(editor: editor, window: window)
        input = NSEventInputSource(view: inputView)
        input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0) }
        input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0) }
        input.onPointerUp     = { [weak self] in self?.controller.pointerUp() }
        input.onActivate      = { [weak self] in self?.controller.activate() }
        input.onDeactivate    = { [weak self] in self?.controller.deactivate() }
        input.onClear         = { [weak self] in self?.controller.clear() }

        subscription = editor.subscribe { [weak self] _ in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor,
                canvasSize: Size(width: Double(self.canvas.frame.width),
                                 height: Double(self.canvas.frame.height))))
        }

        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = SmokeAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Verify build**

```bash
just build
```

Expected: green.

- [ ] **Step 3: Run and verify visually**

```bash
just run-bg
```

Expected:
- Process launches (no errors in console).
- The screen looks normal because the window is transparent and click-through is on by default.
- `Cmd+Opt+Z` activates: the cursor is now captured by the (still-transparent) window. Click-and-drag should draw a translucent cyan line.
- `Cmd+K` (while active) clears the canvas immediately.
- `Esc` deactivates: the window goes back to click-through; you can interact with the desktop normally. Anything you drew stays visible on screen.

If the activation shortcut doesn't fire, the window isn't key — make sure `NSApp.activate(ignoringOtherApps: true)` ran (it's in `TransparentWindow.focus()`).

- [ ] **Step 4: Stop the app**

```bash
just stop
```

- [ ] **Step 5: Update ONBOARDING.md status line**

```
**Status: AppKit shell complete; dev HTTP next.** Phases 1–3 are done. `just run` launches the transparent overlay; Cmd+Opt+Z activates drawing; Esc deactivates. Phase 4 adds the dev HTTP server on :9876; Phase 5 wires it through and validates the seven acceptance criteria.
```

Mark `Sources/AppKit/` as `(complete — POC)`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/main.swift ONBOARDING.md
git commit -m "$(cat <<'EOF'
Wire Phase 3 smoke run

Temporary main.swift that lets us see the window and verify
mouse-driven drawing works end-to-end through AppController.
Phase 5 replaces this with the real wiring + argv + DevHTTP.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

**End of Phase 3.** The transparent overlay works manually. No HTTP yet.

## Phase 4 — DevHTTP

Goal: an `NWListener`-based HTTP server on `localhost:9876` exposing the routes described in the spec. Every route is tested against a fake `AppController` via real `URLSession` calls to a server on an ephemeral port. By phase end, `just inspect-state`, `just inspect-pointer`, etc., all work against a running app.

**Architecture:** A `DevHTTPServer` owns the `NWListener` and a `Router`. Each route is a small file under `Sources/DevHTTP/Routes/`. The server is initialized with a `DevHTTPSurface` protocol the tests can fake; production wires it to the real `AppController` and `Editor`.

### Task 4.1: `HTTPRequest` / `HTTPResponse` types

**Files:**
- Create: `Sources/DevHTTP/HTTPRequest.swift`
- Create: `Sources/DevHTTP/HTTPResponse.swift`
- Create: `Tests/DevHTTPTests/HTTPTypesTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/HTTPTypesTests.swift
// ABOUTME: Tests for HTTPRequest / HTTPResponse value types and their parsing.

import Testing
import Foundation

@Suite("HTTP types")
struct HTTPTypesTests {
    @Test("parses GET request line and headers")
    func parseGet() throws {
        let raw = "GET /state HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        #expect(req.method == "GET")
        #expect(req.path == "/state")
        #expect(req.headers["host"] == "localhost")
        #expect(req.body.isEmpty)
    }

    @Test("parses POST request with JSON body")
    func parsePost() throws {
        let body = "{\"event\":\"down\",\"x\":10,\"y\":20}"
        let raw = "POST /pointer HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        #expect(req.method == "POST")
        #expect(req.path == "/pointer")
        #expect(req.headers["content-type"] == "application/json")
        #expect(String(data: req.body, encoding: .utf8) == body)
    }

    @Test("HTTPResponse.json serializes correctly")
    func responseJSON() throws {
        let resp = HTTPResponse.json(["ok": true])
        let data = resp.serialize()
        let text = String(data: data, encoding: .utf8)!
        #expect(text.hasPrefix("HTTP/1.1 200"))
        #expect(text.contains("Content-Type: application/json"))
        #expect(text.contains("\"ok\":true") || text.contains("\"ok\": true"))
    }

    @Test("HTTPResponse status codes serialize correctly")
    func responseStatus() {
        let resp = HTTPResponse.notFound("nope")
        let text = String(data: resp.serialize(), encoding: .utf8)!
        #expect(text.hasPrefix("HTTP/1.1 404"))
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/DevHTTP/HTTPRequest.swift
// ABOUTME: Minimal HTTP/1.1 request parser. Only what the dev API needs.

import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public enum ParseError: Error { case malformed }

    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { throw ParseError.malformed }
        let headerData = data[..<split.lowerBound]
        let body = data[split.upperBound...]
        guard let headerText = String(data: Data(headerData), encoding: .utf8) else { throw ParseError.malformed }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.malformed }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { throw ParseError.malformed }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: Data(body))
    }
}
```

```swift
// Sources/DevHTTP/HTTPResponse.swift
// ABOUTME: Minimal HTTP/1.1 response composer.

import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let reason: String
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, reason: String, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.reason = reason
        var h = headers
        h["content-length"] = String(body.count)
        if h["content-type"] == nil { h["content-type"] = "text/plain; charset=utf-8" }
        self.headers = h
        self.body = body
    }

    public func serialize() -> Data {
        var lines = ["HTTP/1.1 \(status) \(reason)"]
        for (k, v) in headers {
            // Canonicalize first letter of each segment for cosmetic reasons; not load-bearing.
            lines.append("\(k): \(v)")
        }
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    // MARK: - Convenience

    public static func ok(_ body: String = "OK") -> HTTPResponse {
        HTTPResponse(status: 200, reason: "OK", body: Data(body.utf8))
    }

    public static func json(_ value: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, reason: "OK",
                            headers: ["content-type": "application/json"], body: data)
    }

    public static func json<T: Encodable>(encode value: T) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, reason: "OK",
                            headers: ["content-type": "application/json"], body: data)
    }

    public static func notFound(_ body: String = "Not Found") -> HTTPResponse {
        HTTPResponse(status: 404, reason: "Not Found", body: Data(body.utf8))
    }

    public static func badRequest(_ body: String) -> HTTPResponse {
        HTTPResponse(status: 400, reason: "Bad Request", body: Data(body.utf8))
    }

    public static func png(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, reason: "OK",
                     headers: ["content-type": "image/png"], body: data)
    }
}
```

- [ ] **Step 4-5: Run, expect pass, commit**

```bash
git add Sources/DevHTTP/HTTPRequest.swift Sources/DevHTTP/HTTPResponse.swift Tests/DevHTTPTests/HTTPTypesTests.swift
git commit -m "Add HTTPRequest and HTTPResponse types

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.2: `DevHTTPSurface` protocol + `Router` + `DevHTTPServer` shell

**Files:**
- Create: `Sources/DevHTTP/DevHTTPSurface.swift`
- Create: `Sources/DevHTTP/Router.swift`
- Create: `Sources/DevHTTP/DevHTTPServer.swift`
- Delete: `Sources/DevHTTP/_DevHTTPBootstrap.swift`
- Create: `Tests/DevHTTPTests/Doubles/FakeSurface.swift`
- Create: `Tests/DevHTTPTests/DevHTTPServerTests.swift`

- [ ] **Step 1: Write failing test (end-to-end on ephemeral port)**

```swift
// Tests/DevHTTPTests/DevHTTPServerTests.swift
// ABOUTME: End-to-end test: server starts on an ephemeral port, URLSession hits it.

import Testing
import Foundation

@Suite("DevHTTPServer")
struct DevHTTPServerTests {
    @Test("responds to GET / with 200")
    func smoke() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)  // 0 = ephemeral
        defer { server.stop() }
        try server.start()
        let port = server.boundPort!

        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/")!)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "fiti dev API\n")
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement**

```swift
// Sources/DevHTTP/DevHTTPSurface.swift
// ABOUTME: Protocol the dev HTTP server talks to. Production wires AppController + Editor;
// ABOUTME: tests wire FakeSurface for deterministic assertions.

import Foundation

public protocol DevHTTPSurface: AnyObject {
    var doc: FitiDoc { get }
    var mode: AppController.Mode { get }
    var clickThrough: Bool { get }
    var canvasSize: Size { get }
    var undoDepth: Int { get }
    var redoDepth: Int { get }
    var currentStrokeId: StrokeId? { get }

    func activate()
    func deactivate()
    func pointerDown(_ point: StrokePoint)
    func pointerMoved(_ point: StrokePoint)
    func pointerUp()
    func clear()
    func undo() -> Bool
    func redo() -> Bool
    func eraseStroke(_ id: StrokeId) -> Bool
    func snapshotPNG() -> Data?
}
```

```swift
// Sources/DevHTTP/Router.swift
// ABOUTME: Maps (method, path) to a route handler. Path params resolved by simple
// ABOUTME: pattern match — no regex DSL; we only have a handful of routes.

import Foundation

public struct Router: Sendable {
    public typealias Handler = (HTTPRequest, [String: String]) -> HTTPResponse

    private var routes: [(method: String, pattern: [String], handler: Handler)] = []

    public init() {}

    public mutating func add(_ method: String, _ pattern: String, handler: @escaping Handler) {
        let parts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        routes.append((method: method, pattern: parts, handler: handler))
    }

    public func handle(_ req: HTTPRequest) -> HTTPResponse {
        let parts = req.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for route in routes where route.method == req.method && route.pattern.count == parts.count {
            var params: [String: String] = [:]
            var matched = true
            for (a, b) in zip(route.pattern, parts) {
                if a.hasPrefix(":") {
                    params[String(a.dropFirst())] = b
                } else if a != b {
                    matched = false
                    break
                }
            }
            if matched { return route.handler(req, params) }
        }
        return .notFound()
    }
}
```

```swift
// Sources/DevHTTP/DevHTTPServer.swift
// ABOUTME: NWListener-based HTTP/1.1 server. Single-threaded async — fine for
// ABOUTME: a dev introspection API that handles a few requests per minute.

import Foundation
import Network

public final class DevHTTPServer {
    private let surface: DevHTTPSurface
    private var router: Router
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fiti.devhttp")
    public private(set) var boundPort: Int?

    public init(surface: DevHTTPSurface, port: UInt16) throws {
        self.surface = surface
        self.router = Router()
        let params = NWParameters.tcp
        let endpoint: NWEndpoint.Port = port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
        self.listener = try NWListener(using: params, on: endpoint)
        installRoutes()
    }

    public func start() throws {
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener.port {
                self?.boundPort = Int(port.rawValue)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        // Wait briefly for the listener to report bound port (synchronous test ergonomics).
        let deadline = Date().addingTimeInterval(2)
        while boundPort == nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    public func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            // Crude: assume the whole request fits in one read (POC scale).
            if let req = try? HTTPRequest.parse(buf) {
                let response = self.router.handle(req).serialize()
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readRequest(on: connection, buffer: buf)
        }
    }

    private func installRoutes() {
        router.add("GET", "/") { _, _ in
            HTTPResponse(status: 200, reason: "OK", body: Data("fiti dev API\n".utf8))
        }
        // Other routes are added in Tasks 4.3 — 4.8.
    }
}
```

```swift
// Tests/DevHTTPTests/Doubles/FakeSurface.swift
// ABOUTME: In-memory DevHTTPSurface for route tests. Records every method call.

import Foundation

public final class FakeSurface: DevHTTPSurface {
    public var doc: FitiDoc = .empty
    public var mode: AppController.Mode = .inactive
    public var clickThrough: Bool = true
    public var canvasSize: Size = Size(width: 1440, height: 900)
    public var undoDepth: Int = 0
    public var redoDepth: Int = 0
    public var currentStrokeId: StrokeId?

    public var activateCalls = 0
    public var deactivateCalls = 0
    public var clearCalls = 0
    public var undoCalls = 0
    public var redoCalls = 0
    public var erasedIds: [StrokeId] = []
    public var pointerEvents: [(String, StrokePoint?)] = []
    public var snapshotPNGReturn: Data? = Data([0x89, 0x50, 0x4e, 0x47])  // PNG magic

    public init() {}

    public func activate() { activateCalls += 1 }
    public func deactivate() { deactivateCalls += 1 }
    public func pointerDown(_ p: StrokePoint) { pointerEvents.append(("down", p)) }
    public func pointerMoved(_ p: StrokePoint) { pointerEvents.append(("move", p)) }
    public func pointerUp() { pointerEvents.append(("up", nil)) }
    public func clear() { clearCalls += 1 }
    public func undo() -> Bool { undoCalls += 1; return true }
    public func redo() -> Bool { redoCalls += 1; return true }
    public func eraseStroke(_ id: StrokeId) -> Bool { erasedIds.append(id); return true }
    public func snapshotPNG() -> Data? { snapshotPNGReturn }
}
```

- [ ] **Step 4: Drop bootstrap, run, expect pass**

```bash
git rm Sources/DevHTTP/_DevHTTPBootstrap.swift
just test
```

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/ Tests/DevHTTPTests/
git commit -m "$(cat <<'EOF'
Add DevHTTPServer scaffold, Router, surface protocol, FakeSurface

NWListener-based HTTP/1.1 server bound to a configurable port
(0 = ephemeral for tests). Smoke route returns 200 OK at /.
Routes for /state, /doc, etc. land in 4.3 — 4.8.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.3: `/state` and `/doc` routes

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/StateAndDocTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/RouteTests/StateAndDocTests.swift
// ABOUTME: Tests for GET /state and GET /doc routes.

import Testing
import Foundation

@Suite("/state and /doc")
struct StateAndDocTests {
    private func startServer(_ surface: FakeSurface) throws -> DevHTTPServer {
        let server = try DevHTTPServer(surface: surface, port: 0)
        try server.start()
        return server
    }

    private func get(_ server: DevHTTPServer, _ path: String) async throws -> (Int, [String: Any]) {
        let url = URL(string: "http://localhost:\(server.boundPort!)\(path)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as! HTTPURLResponse).statusCode
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return (status, json)
    }

    @Test("/state returns mode, clickThrough, canvasSize, undo/redo depth")
    func state() async throws {
        let surface = FakeSurface()
        surface.mode = .activeIdle
        surface.clickThrough = false
        surface.undoDepth = 3
        surface.redoDepth = 1
        let server = try startServer(surface); defer { server.stop() }
        let (status, json) = try await get(server, "/state")
        #expect(status == 200)
        #expect((json["mode"] as? String) == "activeIdle")
        #expect((json["clickThrough"] as? Bool) == false)
        #expect((json["undoDepth"] as? Int) == 3)
        #expect((json["redoDepth"] as? Int) == 1)
    }

    @Test("/doc returns FitiDoc JSON")
    func doc() async throws {
        let surface = FakeSurface()
        let s = Stroke(id: "a", color: RGBA(r:1,g:0,b:0,a:1), width: 2, transform: .identity,
                       points: [StrokePoint(x: 1, y: 2)], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        surface.doc = FitiDoc(strokes: ["a": s], strokeOrder: ["a"])
        let server = try startServer(surface); defer { server.stop() }
        let (status, json) = try await get(server, "/doc")
        #expect(status == 200)
        #expect((json["strokeOrder"] as? [String]) == ["a"])
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add routes in `installRoutes()`**

In `Sources/DevHTTP/DevHTTPServer.swift`, replace `installRoutes()` with:

```swift
private func installRoutes() {
    router.add("GET", "/") { _, _ in
        HTTPResponse(status: 200, reason: "OK", body: Data("fiti dev API\n".utf8))
    }

    router.add("GET", "/state") { [weak self] _, _ in
        guard let self else { return .notFound() }
        let payload: [String: Any] = [
            "mode": String(describing: self.surface.mode),
            "clickThrough": self.surface.clickThrough,
            "canvasSize": ["width": self.surface.canvasSize.width, "height": self.surface.canvasSize.height],
            "undoDepth": self.surface.undoDepth,
            "redoDepth": self.surface.redoDepth,
            "currentStrokeId": self.surface.currentStrokeId as Any,
        ]
        return .json(payload)
    }

    router.add("GET", "/doc") { [weak self] _, _ in
        guard let self else { return .notFound() }
        return .json(encode: self.surface.doc)
    }
}
```

Note: `String(describing: self.surface.mode)` produces `"inactive"`, `"activeIdle"`, `"activeDrawing"`. Confirm during first test run; if it produces decorated output, add a manual `switch` to map to lowercased strings.

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/StateAndDocTests.swift
git commit -m "Add GET /state and GET /doc routes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.4: `/strokes/{id}` and `/strokes/{id}/erase`

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/StrokeRoutesTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/RouteTests/StrokeRoutesTests.swift
// ABOUTME: Tests for GET /strokes/{id} and POST /strokes/{id}/erase.

import Testing
import Foundation

@Suite("/strokes/:id routes")
struct StrokeRoutesTests {
    @Test("GET /strokes/{id} returns the stroke")
    func getStroke() async throws {
        let surface = FakeSurface()
        let s = Stroke(id: "abc", color: RGBA(r:0,g:1,b:0,a:1), width: 3, transform: .identity,
                       points: [StrokePoint(x: 5, y: 5)], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        surface.doc = FitiDoc(strokes: ["abc": s], strokeOrder: ["abc"])
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let url = URL(string: "http://localhost:\(server.boundPort!)/strokes/abc")!
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect((json["id"] as? String) == "abc")
    }

    @Test("GET /strokes/{id} returns 404 for unknown id")
    func get404() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let url = URL(string: "http://localhost:\(server.boundPort!)/strokes/nope")!
        let (_, response) = try await URLSession.shared.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }

    @Test("POST /strokes/{id}/erase calls eraseStroke on the surface")
    func postErase() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        var req = URLRequest(url: URL(string: "http://localhost:\(server.boundPort!)/strokes/abc/erase")!)
        req.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: req)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        #expect(surface.erasedIds == ["abc"])
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add routes**

Append in `installRoutes()`:

```swift
router.add("GET", "/strokes/:id") { [weak self] _, params in
    guard let self, let id = params["id"], let stroke = self.surface.doc.strokes[id] else { return .notFound() }
    return .json(encode: stroke)
}

router.add("POST", "/strokes/:id/erase") { [weak self] _, params in
    guard let self, let id = params["id"] else { return .badRequest("missing id") }
    let ok = self.surface.eraseStroke(id)
    return .json(["erased": ok])
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/StrokeRoutesTests.swift
git commit -m "Add GET /strokes/:id and POST /strokes/:id/erase

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.5: `/pointer`, `/activate`, `/deactivate` routes

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/InputRoutesTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/RouteTests/InputRoutesTests.swift
// ABOUTME: Tests for POST /pointer, /activate, /deactivate.

import Testing
import Foundation

@Suite("Input routes")
struct InputRoutesTests {
    private func post(_ server: DevHTTPServer, _ path: String, body: String? = nil) async throws -> Int {
        var req = URLRequest(url: URL(string: "http://localhost:\(server.boundPort!)\(path)")!)
        req.httpMethod = "POST"
        if let body { req.httpBody = Data(body.utf8); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as! HTTPURLResponse).statusCode
    }

    @Test("POST /activate / /deactivate route to the surface")
    func activation() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/activate") == 200)
        #expect(try await post(server, "/deactivate") == 200)
        #expect(surface.activateCalls == 1)
        #expect(surface.deactivateCalls == 1)
    }

    @Test("POST /pointer with down event")
    func pointerDown() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/pointer", body: "{\"event\":\"down\",\"x\":10,\"y\":20}") == 200)
        #expect(surface.pointerEvents.count == 1)
        #expect(surface.pointerEvents[0].0 == "down")
        #expect(surface.pointerEvents[0].1?.x == 10)
        #expect(surface.pointerEvents[0].1?.y == 20)
    }

    @Test("POST /pointer with malformed body returns 400")
    func pointerBadRequest() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/pointer", body: "{}") == 400)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add routes**

Append in `installRoutes()`:

```swift
router.add("POST", "/activate") { [weak self] _, _ in
    self?.surface.activate()
    return .ok()
}

router.add("POST", "/deactivate") { [weak self] _, _ in
    self?.surface.deactivate()
    return .ok()
}

router.add("POST", "/pointer") { [weak self] req, _ in
    guard let self else { return .notFound() }
    guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
          let event = json["event"] as? String else {
        return .badRequest("expected {event, x, y} body")
    }
    if event == "up" {
        self.surface.pointerUp()
        return .ok()
    }
    guard let x = (json["x"] as? Double) ?? (json["x"] as? Int).map(Double.init),
          let y = (json["y"] as? Double) ?? (json["y"] as? Int).map(Double.init) else {
        return .badRequest("missing x/y")
    }
    let pressure = (json["pressure"] as? Double) ?? 0.5
    let p = StrokePoint(x: x, y: y, pressure: pressure)
    switch event {
    case "down": self.surface.pointerDown(p)
    case "move": self.surface.pointerMoved(p)
    default: return .badRequest("unknown event \(event)")
    }
    return .ok()
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/InputRoutesTests.swift
git commit -m "Add /pointer /activate /deactivate routes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.6: `/clear`, `/undo`, `/redo` routes

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/HistoryRoutesTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/RouteTests/HistoryRoutesTests.swift
// ABOUTME: Tests for POST /clear, /undo, /redo.

import Testing
import Foundation

@Suite("History routes")
struct HistoryRoutesTests {
    @Test("clear / undo / redo route to surface")
    func all() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let post = { (path: String) -> Int in
            var req = URLRequest(url: URL(string: "http://localhost:\(server.boundPort!)\(path)")!)
            req.httpMethod = "POST"
            let group = DispatchGroup(); group.enter()
            var status = 0
            URLSession.shared.dataTask(with: req) { _, response, _ in
                status = (response as! HTTPURLResponse).statusCode
                group.leave()
            }.resume()
            group.wait()
            return status
        }
        #expect(post("/clear") == 200)
        #expect(post("/undo") == 200)
        #expect(post("/redo") == 200)
        #expect(surface.clearCalls == 1)
        #expect(surface.undoCalls == 1)
        #expect(surface.redoCalls == 1)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add routes**

```swift
router.add("POST", "/clear") { [weak self] _, _ in
    self?.surface.clear()
    return .ok()
}

router.add("POST", "/undo") { [weak self] _, _ in
    let did = self?.surface.undo() ?? false
    return .json(["undid": did])
}

router.add("POST", "/redo") { [weak self] _, _ in
    let did = self?.surface.redo() ?? false
    return .json(["redid": did])
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/HistoryRoutesTests.swift
git commit -m "Add /clear /undo /redo routes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.7: `/snapshot.png` route

**Files:**
- Modify: `Sources/DevHTTP/DevHTTPServer.swift`
- Create: `Tests/DevHTTPTests/RouteTests/SnapshotTests.swift`

The snapshot route asks the surface for a PNG. The real surface (Phase 5) builds a `CGContext` off-screen and renders the current frame to PNG bytes. The fake returns a stub PNG.

- [ ] **Step 1: Write failing test**

```swift
// Tests/DevHTTPTests/RouteTests/SnapshotTests.swift
// ABOUTME: Tests for GET /snapshot.png — returns PNG bytes from the surface.

import Testing
import Foundation

@Suite("/snapshot.png")
struct SnapshotTests {
    @Test("returns the surface's PNG bytes with image/png content type")
    func returnsPNG() async throws {
        let surface = FakeSurface()
        surface.snapshotPNGReturn = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])  // real PNG magic
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(server.boundPort!)/snapshot.png")!)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(data.prefix(8) == surface.snapshotPNGReturn)
    }

    @Test("returns 500 when surface returns nil")
    func nilReturnsError() async throws {
        let surface = FakeSurface()
        surface.snapshotPNGReturn = nil
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(server.boundPort!)/snapshot.png")!)
        #expect((response as! HTTPURLResponse).statusCode == 500)
    }
}
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add route**

```swift
router.add("GET", "/snapshot.png") { [weak self] _, _ in
    guard let data = self?.surface.snapshotPNG() else {
        return HTTPResponse(status: 500, reason: "Internal Server Error",
                            body: Data("snapshot unavailable".utf8))
    }
    return .png(data)
}
```

- [ ] **Step 4: Run, expect pass**

- [ ] **Step 5: Commit**

```bash
git add Sources/DevHTTP/DevHTTPServer.swift Tests/DevHTTPTests/RouteTests/SnapshotTests.swift
git commit -m "Add GET /snapshot.png route

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4.8: `inspect-*` justfile recipes

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Append inspect group**

```just
# ─── inspect (dev HTTP @ localhost:9876) ──────────────────────────────────

[group('inspect')]
inspect-state:
    @curl -sf localhost:{{dev_port}}/state | jq .

[group('inspect')]
inspect-doc:
    @curl -sf localhost:{{dev_port}}/doc | jq .

[group('inspect')]
inspect-stroke id:
    @curl -sf localhost:{{dev_port}}/strokes/{{id}} | jq .

[group('inspect')]
inspect-screenshot path=(".llm/inspect/screenshot-" + `date +%Y%m%d-%H%M%S` + ".png"):
    @mkdir -p .llm/inspect && curl -sf 'localhost:{{dev_port}}/snapshot.png' -o '{{path}}' && echo '{{path}}'

[group('inspect')]
inspect-pointer event x y:
    @curl -sf -X POST localhost:{{dev_port}}/pointer \
        -H 'Content-Type: application/json' \
        -d '{"event":"{{event}}","x":{{x}},"y":{{y}}}' \
        | jq -R 'try fromjson catch .'

[group('inspect')]
inspect-clear:
    @curl -sf -X POST localhost:{{dev_port}}/clear

[group('inspect')]
inspect-undo:
    @curl -sf -X POST localhost:{{dev_port}}/undo | jq .

[group('inspect')]
inspect-redo:
    @curl -sf -X POST localhost:{{dev_port}}/redo | jq .

[group('inspect')]
inspect-activate:
    @curl -sf -X POST localhost:{{dev_port}}/activate

[group('inspect')]
inspect-deactivate:
    @curl -sf -X POST localhost:{{dev_port}}/deactivate

[group('inspect')]
inspect-erase id:
    @curl -sf -X POST localhost:{{dev_port}}/strokes/{{id}}/erase | jq .
```

- [ ] **Step 2: Verify recipe listing**

```bash
just --list
```

Expected: all `inspect-*` recipes appear under the `inspect` group.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "$(cat <<'EOF'
Add inspect-* recipes for the dev HTTP API

Wraps curl + jq calls to localhost:9876. Matches the convention
used by montty and limn's inspect-* recipes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.9: Phase 4 verification

- [ ] **Step 1: Confirm test count**

```bash
just test
```

Expected: ~50-60 tests pass (Core ~35 + DevHTTP ~15-25). Under 5s total.

- [ ] **Step 2: Confirm `just check` green**

```bash
just check
```

- [ ] **Step 3: Update ONBOARDING.md status**

```
**Status: dev HTTP complete; wiring next.** Phases 1–4 are done. The NWListener-based server exposes /state, /doc, /strokes/{id}, /pointer, /activate, /deactivate, /clear, /undo, /redo, /snapshot.png. Phase 5 wires it into the real AppController + a CG-backed snapshot renderer.
```

Mark `Sources/DevHTTP/` and `Tests/DevHTTPTests/` as `(complete)`.

- [ ] **Step 4: Commit**

```bash
git add ONBOARDING.md
git commit -m "Refresh ONBOARDING.md after Phase 4

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

**End of Phase 4.** All routes are implemented and tested against a fake surface. The real surface implementation lands in Phase 5.

## Phase 5 — End-to-end wiring and acceptance

Goal: replace the Phase 3 smoke wiring with the real app. argv parsing, production `Clock`/`IdGenerator`, headless snapshot renderer, the `DevHTTPSurface` that bridges to `AppController`+`Editor`, and a full pass through the seven behavioral acceptance criteria from the spec.

### Task 5.1: Argv parser

**Files:**
- Create: `Sources/App/Args.swift`
- Create: `Tests/CoreTests/AppArgsTests.swift` (wait — App isn't in test target. Put this test in `Tests/DevHTTPTests/AppArgsTests.swift` if you want it tested. Or skip: argv parsing is tiny and verified by run-through.)

For POC, skip the test and validate by run-through. The parser is < 30 lines.

- [ ] **Step 1: Implement**

```swift
// Sources/App/Args.swift
// ABOUTME: Tiny argv parser. POC understands only --dev and --port N.

import Foundation

public struct Args {
    public var dev: Bool = false
    public var port: UInt16 = 9876

    public static func parse(_ argv: [String]) -> Args {
        var args = Args()
        var i = 1  // skip executable name
        while i < argv.count {
            switch argv[i] {
            case "--dev":
                args.dev = true
                i += 1
            case "--port":
                guard i + 1 < argv.count, let p = UInt16(argv[i + 1]) else {
                    FileHandle.standardError.write(Data("--port requires a number\n".utf8))
                    exit(2)
                }
                args.port = p
                i += 2
            case "--help", "-h":
                print("Usage: fiti [--dev] [--port N]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("unknown arg: \(argv[i])\n".utf8))
                exit(2)
            }
        }
        return args
    }
}
```

- [ ] **Step 2: Build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/Args.swift
git commit -m "Add Args argv parser

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5.2: Production `Clock` and `IdGenerator`

**Files:**
- Create: `Sources/App/SystemClock.swift`
- Create: `Sources/App/UUIDStrokeIds.swift`

**Spec deviation:** spec calls for `ULIDGenerator`. ULID's sortability is not load-bearing for POC (strokeOrder is the canonical ordering). Use `UUIDStrokeIds` (UUID.uuidString-based) — same uniqueness, zero deps, simpler. Decision-log entry added in 5.6.

- [ ] **Step 1: Implement**

```swift
// Sources/App/SystemClock.swift
// ABOUTME: Production Clock — wall-clock seconds since epoch.

import Foundation

public final class SystemClock: Clock {
    public init() {}
    public func now() -> Double { Date().timeIntervalSince1970 }
}
```

```swift
// Sources/App/UUIDStrokeIds.swift
// ABOUTME: Production IdGenerator. Spec calls for ULID, but UUID is simpler
// ABOUTME: and the spec's "sortable" property isn't load-bearing because
// ABOUTME: FitiDoc.strokeOrder is the canonical stroke ordering anyway.

import Foundation

public final class UUIDStrokeIds: IdGenerator {
    public init() {}
    public func newStrokeId() -> StrokeId { UUID().uuidString }
}
```

- [ ] **Step 2: Build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/SystemClock.swift Sources/App/UUIDStrokeIds.swift
git commit -m "$(cat <<'EOF'
Add SystemClock and UUIDStrokeIds (production impls)

Spec called for ULIDGenerator; UUID is simpler and sortability
isn't load-bearing because strokeOrder is the canonical ordering.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5.3: `SnapshotRenderer` for headless PNG

**Files:**
- Create: `Sources/AppKit/SnapshotRenderer.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/AppKit/SnapshotRenderer.swift
// ABOUTME: Render a RenderFrame to PNG bytes via off-screen CGContext.
// ABOUTME: Used by GET /snapshot.png — same drawing logic as CanvasView.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SnapshotRenderer {
    public static func png(from frame: RenderFrame, scale: CGFloat = 2.0) -> Data? {
        let width = Int(frame.canvasSize.width * Double(scale))
        let height = Int(frame.canvasSize.height * Double(scale))
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        // Top-origin to match StrokePoint convention.
        ctx.translateBy(x: 0, y: CGFloat(frame.canvasSize.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.clear(CGRect(x: 0, y: 0, width: Int(frame.canvasSize.width), height: Int(frame.canvasSize.height)))

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in frame.strokes { drawStroke(stroke, in: ctx) }
        if let inProgress = frame.inProgress { drawStroke(inProgress, in: ctx) }

        guard let cgImage = ctx.makeImage() else { return nil }
        return pngData(from: cgImage)
    }

    private static func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        guard stroke.points.count > 0 else { return }
        ctx.setLineWidth(CGFloat(stroke.width))
        ctx.setStrokeColor(red: CGFloat(stroke.color.r), green: CGFloat(stroke.color.g),
                           blue: CGFloat(stroke.color.b), alpha: CGFloat(stroke.color.a))
        let path = CGMutablePath()
        let first = stroke.points[0]
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func pngData(from image: CGImage) -> Data? {
        let buf = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buf, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buf as Data
    }
}
```

- [ ] **Step 2: Build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/AppKit/SnapshotRenderer.swift
git commit -m "$(cat <<'EOF'
Add SnapshotRenderer for headless PNG generation

Off-screen CGContext, sRGB color space, top-origin coords matching
CanvasView. Returns PNG bytes via ImageIO.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5.4: `FitiDevHTTPSurface` bridge

**Files:**
- Create: `Sources/App/FitiDevHTTPSurface.swift`

- [ ] **Step 1: Implement**

```swift
// Sources/App/FitiDevHTTPSurface.swift
// ABOUTME: Production DevHTTPSurface — bridges AppController + Editor to the
// ABOUTME: dev HTTP server. Lives in Sources/App because it imports both
// ABOUTME: Core (AppController) and AppKit (SnapshotRenderer).

import Foundation

public final class FitiDevHTTPSurface: DevHTTPSurface {
    private let controller: AppController
    private let canvasSizeProvider: () -> Size

    public init(controller: AppController, canvasSize: @escaping () -> Size) {
        self.controller = controller
        self.canvasSizeProvider = canvasSize
    }

    public var doc: FitiDoc { controller.editor.doc }
    public var mode: AppController.Mode { controller.mode }
    public var clickThrough: Bool { mode == .inactive }
    public var canvasSize: Size { canvasSizeProvider() }
    public var undoDepth: Int { controller.editor.undoStack.count }
    public var redoDepth: Int { controller.editor.redoStack.count }
    public var currentStrokeId: StrokeId? { controller.editor.currentStrokeId }

    public func activate() { controller.activate() }
    public func deactivate() { controller.deactivate() }
    public func pointerDown(_ p: StrokePoint) {
        // Auto-activate if the dev client injects pointer events while inactive.
        // Per the spec, HTTP routes bypass the activation gate.
        if controller.mode == .inactive { controller.activate() }
        controller.pointerDown(p)
    }
    public func pointerMoved(_ p: StrokePoint) {
        if controller.mode == .inactive { controller.activate() }
        if controller.mode == .activeIdle {
            // We somehow got a move without a down — treat as a down.
            controller.pointerDown(p)
        } else {
            controller.pointerMoved(p)
        }
    }
    public func pointerUp() {
        if controller.mode == .activeDrawing { controller.pointerUp() }
    }
    public func clear() { controller.editor.clear() }
    public func undo() -> Bool { controller.editor.undo() }
    public func redo() -> Bool { controller.editor.redo() }
    public func eraseStroke(_ id: StrokeId) -> Bool { controller.editor.eraseStroke(id) }
    public func snapshotPNG() -> Data? {
        let frame = RenderFrame.from(editor: controller.editor, canvasSize: canvasSize)
        return SnapshotRenderer.png(from: frame)
    }
}
```

- [ ] **Step 2: Build**

```bash
just build
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/FitiDevHTTPSurface.swift
git commit -m "$(cat <<'EOF'
Add FitiDevHTTPSurface bridge

Production DevHTTPSurface impl wiring AppController + Editor +
SnapshotRenderer. HTTP routes bypass the activation gate by
auto-activating on pointer input (per spec).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5.5: Replace smoke wiring with real `main.swift`

**Files:**
- Modify: `Sources/App/main.swift`

- [ ] **Step 1: Replace**

```swift
// Sources/App/main.swift
// ABOUTME: fiti entry point — argv → wiring → NSApplication.run().
// ABOUTME: Sole place where AppKit + DevHTTP + Core concretes are stitched together.

import AppKit
import Foundation

let args = Args.parse(CommandLine.arguments)

final class FitiAppDelegate: NSObject, NSApplicationDelegate {
    let args: Args
    var window: TransparentWindow!
    var canvas: CanvasView!
    var inputView: CanvasInputView!
    var input: NSEventInputSource!
    var controller: AppController!
    var editor: Editor!
    var devServer: DevHTTPServer?
    var subscription: Cancellable?

    init(args: Args) { self.args = args }

    func applicationDidFinishLaunching(_ notification: Notification) {
        editor = Editor(clock: SystemClock(), ids: UUIDStrokeIds())
        window = TransparentWindow()
        let frame = window.contentLayoutRect

        let container = NSView(frame: frame)
        canvas = CanvasView(frame: frame)
        inputView = CanvasInputView(frame: frame)
        canvas.autoresizingMask = [.width, .height]
        inputView.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        container.addSubview(inputView)
        window.contentView = container

        controller = AppController(editor: editor, window: window)
        input = NSEventInputSource(view: inputView)
        input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0) }
        input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0) }
        input.onPointerUp     = { [weak self] in self?.controller.pointerUp() }
        input.onActivate      = { [weak self] in self?.controller.activate() }
        input.onDeactivate    = { [weak self] in self?.controller.deactivate() }
        input.onClear         = { [weak self] in self?.controller.clear() }

        subscription = editor.subscribe { [weak self] _ in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor, canvasSize: self.canvasSize))
        }

        if args.dev {
            let surface = FitiDevHTTPSurface(controller: controller,
                                             canvasSize: { [weak self] in self?.canvasSize ?? Size(width: 0, height: 0) })
            do {
                let server = try DevHTTPServer(surface: surface, port: args.port)
                try server.start()
                devServer = server
                NSLog("fiti dev HTTP listening on localhost:\(args.port)")
            } catch {
                NSLog("fiti dev HTTP failed to start: \(error)")
            }
        }

        window.makeKeyAndOrderFront(nil)
    }

    private var canvasSize: Size {
        Size(width: Double(canvas.frame.width), height: Double(canvas.frame.height))
    }
}

let app = NSApplication.shared
let delegate = FitiAppDelegate(args: args)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Build + run**

```bash
just check
just run-bg
```

Expected: app launches, transparent window appears, no log errors. With `--dev`, see `fiti dev HTTP listening on localhost:9876` in Console.app or wherever NSLog goes.

- [ ] **Step 3: Sanity-check the HTTP surface**

```bash
just inspect-state
```

Expected: JSON with `mode: "inactive"`, `clickThrough: true`, etc.

- [ ] **Step 4: Stop and commit**

```bash
just stop
git add Sources/App/main.swift
git commit -m "$(cat <<'EOF'
Replace Phase 3 smoke wiring with full main.swift

Wires Args, SystemClock, UUIDStrokeIds, AppController, AppKit
adapters, and DevHTTPServer (when --dev is passed). Smoke wiring
from Phase 3 retired.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5.6: Acceptance criteria walkthrough

Per the spec's "Behavioral acceptance criteria" section, the POC is done when these seven hold. Walk through each manually with `just run-bg` running.

- [ ] **AC1: Activate via HTTP**

```bash
just inspect-activate
just inspect-state
```

Expected: 200 response on activate; state shows `mode: "activeIdle"`, `clickThrough: false`.

- [ ] **AC2: Scripted pointer sequence draws a stroke**

```bash
just inspect-pointer down 100 100
just inspect-pointer move 200 100
just inspect-pointer move 200 200
just inspect-pointer up 200 200
just inspect-doc
```

Expected: `/doc` reports a single stroke with 3 points (the down + two moves) at the right coordinates. Identity transform. Hardcoded color and width.

- [ ] **AC3: Snapshot PNG**

```bash
just inspect-screenshot
```

Expected: file written to `.llm/inspect/screenshot-*.png`. Open it; the stroke is visible at the right pixel coordinates.

- [ ] **AC4: Undo / redo round-trips**

Capture a baseline:

```bash
just inspect-doc > /tmp/before.json
just inspect-undo
just inspect-doc | jq '.strokes | length'  # expect 0
just inspect-redo
just inspect-doc > /tmp/after.json
diff /tmp/before.json /tmp/after.json
```

Expected: empty diff.

- [ ] **AC5: Clear + undo restores strokes**

```bash
just inspect-pointer down 50 50
just inspect-pointer up 50 50
just inspect-doc | jq '.strokeOrder'   # expect 2 ids
just inspect-clear
just inspect-doc | jq '.strokeOrder'   # expect []
just inspect-undo
just inspect-doc | jq '.strokeOrder'   # expect 2 ids again, same order
```

Bonus check (manual, requires the window to be key-focused): with the overlay active, press `Cmd+K`. The canvas should clear and `just inspect-doc` should show `strokeOrder: []`. This exercises the keyboard path for clear; the HTTP path is what tests cover automatically.

- [ ] **AC6: Deactivate reverts click-through**

```bash
just inspect-deactivate
just inspect-state | jq '.clickThrough'  # expect true
```

Move the real mouse — clicks should pass through to the desktop.

- [ ] **AC7: `just check` is green**

```bash
just stop
just check
```

Expected: all tests pass, lint clean, build clean.

---

### Task 5.7: Final ONBOARDING.md refresh + decision-log update

**Files:**
- Modify: `ONBOARDING.md`
- Modify: `docs/specs/2026-05-16-fiti-poc-design.md`

- [ ] **Step 1: Update ONBOARDING.md status**

```
**Status: POC complete.** All seven acceptance criteria from the design doc pass. The app launches via `just run-bg`, accepts pointer / state / history operations via the dev HTTP API on :9876, renders PNG snapshots, and `just check` is green. Next: shapes, fading, pen pressure, toolbar — see [Out of scope] in the design doc.
```

Mark `Sources/App/` as `(complete)`.

- [ ] **Step 2: Add a decision-log entry to the spec**

Append to the Decision log section of `docs/specs/2026-05-16-fiti-poc-design.md`:

```
- **2026-05-16 — UUID-based stroke ids instead of ULIDs.** Spec called for `ULIDGenerator` for sortable stable ids. Implementation uses `UUIDStrokeIds` (Foundation's `UUID().uuidString`) instead. Sortability isn't load-bearing because `FitiDoc.strokeOrder` is the canonical ordering; uniqueness is the only property the model relies on. Zero new dependencies, no algorithm to maintain. The id-format change is internal and can be revisited if any feature ever cares about timestamp-from-id.
```

- [ ] **Step 3: Commit**

```bash
git add ONBOARDING.md docs/specs/2026-05-16-fiti-poc-design.md
git commit -m "$(cat <<'EOF'
Mark POC complete

All seven acceptance criteria pass. Decision log captures the
UUID-over-ULID deviation from spec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

**End of Phase 5.** POC complete.

---

## Verification of completed plan

Run this at the end to confirm everything lines up:

```bash
just check                  # green
ls Sources/Core/Model/      # 7 .swift files
ls Sources/Core/Editor/     # 3 .swift files
ls Sources/Core/Control/    # 1 .swift file
ls Sources/Core/Ports/      # 5 .swift files
ls Sources/AppKit/          # 4 .swift files
ls Sources/DevHTTP/         # 4 .swift files
ls Sources/App/             # 5 .swift files
git log --oneline | wc -l   # design + plan + ~60 implementation commits
just inspect-state          # responds (with app running)
```

## Future work (out of scope for this plan)

The design doc's "Out of scope" section enumerates these. Each becomes its own spec → plan cycle when it's time to land:

- Rect / ellipse / arrow shape tools
- Eraser as a UI tool (the model already supports eraseStroke)
- Mark fading
- Perfect-freehand port for variable-width pressure-sensitive strokes
- Pen / touch input
- Toolbar, color picker, size selector
- Global activate shortcut via accessibility permission
- `.app` bundling + codesigning + notarization + homebrew cask
- Automerge / CRDT sync






