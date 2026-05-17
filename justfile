# ABOUTME: fiti — native Swift telestrator POC
# ABOUTME: All commands route through this file. Use `just <recipe>`, never the underlying tool directly.

set dotenv-load := true

build_dir     := "/tmp/fiti-build"
install_dir   := env_var('HOME') / "Applications"
dev_port      := "9876"
# Code-signing identity (override via FITI_CODE_SIGN_IDENTITY in .env or shell).
# "-" means ad-hoc; the cdhash changes per build and Accessibility grants get
# invalidated after each rebuild. Set a stable identity to fix that — see
# .env.example.
sign_identity := env_var_or_default("FITI_CODE_SIGN_IDENTITY", "-")

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

# Build the app (Debug); output in /tmp/fiti-build to avoid Dropbox/iCloud codesign issues
[group('build')]
build: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti -configuration Debug build SYMROOT={{build_dir}} CODE_SIGN_IDENTITY="{{sign_identity}}"

# Copy the built .app to ~/Applications/Fiti.app (stable path for Accessibility grants)
[group('build')]
install: build
    @rm -rf "{{install_dir}}/Fiti.app"
    @mkdir -p "{{install_dir}}"
    @cp -R {{build_dir}}/Debug/Fiti.app "{{install_dir}}/Fiti.app"
    @echo "Installed: {{install_dir}}/Fiti.app"

# Remove build artifacts and the generated Xcode project
[group('build')]
clean:
    rm -rf {{build_dir}} fiti.xcodeproj DerivedData
    @echo "Clean complete. (~/Applications/Fiti.app left in place — remove manually if desired.)"

# ─── test ─────────────────────────────────────────────────────────────────

# Run the Swift Testing test bundle
[group('test')]
test: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} CODE_SIGN_IDENTITY="{{sign_identity}}"
    swift test --package-path Packages/PerfectFreehand

# Run one test by name. Swift Testing identifiers include `()`, e.g. 'swiftTestingIsWired()' or 'SmokeTests/myTest()'
[group('test')]
test-only NAME: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} CODE_SIGN_IDENTITY="{{sign_identity}}" -only-testing:'fiti-unit/{{NAME}}'

# Run the AppKit / integration test bundle (slower; includes AppKit)
[group('test')]
test-integration: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-integration -destination 'platform=macOS' test SYMROOT={{build_dir}} CODE_SIGN_IDENTITY="{{sign_identity}}"
    swift test --package-path Packages/PerfectFreehand

# ─── check ────────────────────────────────────────────────────────────────

# Run SwiftLint plus the Sources/Core import-discipline check
[group('check')]
lint:
    swiftlint lint --strict
    ./scripts/check-core-imports.sh

# Full CI gate: unit tests + integration tests + lint + build. Run this before every commit.
[group('check')]
check: test test-integration lint build

# ─── run ──────────────────────────────────────────────────────────────────

# Build, install to ~/Applications, and launch in foreground (--dev enables HTTP introspection).
# `open -W` launches via Launch Services (not as a shell child) so macOS attributes
# Accessibility requests to Fiti.app itself, not to the terminal that ran `just`.
[group('run')]
run: install
    open -W "{{install_dir}}/Fiti.app" --args --dev --port {{dev_port}}

# Build, install, and launch in the background, for scripted testing
[group('run')]
run-bg: install
    @open "{{install_dir}}/Fiti.app" --args --dev --port {{dev_port}}
    @sleep 1
    @echo "fiti running in background. Use 'just stop' to quit."

# Graceful quit (osascript); falls back to pkill if Apple Events fail
[group('run')]
stop:
    @osascript -e 'tell application "Fiti" to quit' 2>/dev/null \
        || pkill -f 'Fiti.app/Contents/MacOS/Fiti' 2>/dev/null \
        || echo "fiti not running"

# Wipe Fiti's Accessibility TCC entry so the next launch re-prompts cleanly
[group('run')]
reset-accessibility:
    @tccutil reset Accessibility com.fiti.app
    @echo "TCC entry reset. Next 'just run-bg' will trigger a fresh permission dialog."

# Install + open Privacy & Security → Accessibility so you can grant Fiti the global Ctrl+G hotkey
[group('run')]
grant-accessibility: install
    @open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    @open -R "{{install_dir}}/Fiti.app"
    @echo ""
    @echo "Drag Fiti.app from the revealed Finder window into the Accessibility list,"
    @echo "or use the + button and Cmd+Shift+G with this path:"
    @echo "  {{install_dir}}/Fiti.app"
    @echo ""
    @echo "Then toggle Fiti on. With a stable FITI_CODE_SIGN_IDENTITY in .env the grant"
    @echo "persists across rebuilds. With ad-hoc signing it will need re-toggling after"
    @echo "each rebuild — see ONBOARDING.md > Code signing."

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

[group('inspect')]
inspect-set-color r g b a:
    @curl -sf -X POST localhost:{{dev_port}}/color \
        -H 'Content-Type: application/json' \
        -d '{"r":{{r}},"g":{{g}},"b":{{b}},"a":{{a}}}'

[group('inspect')]
inspect-set-width w:
    @curl -sf -X POST localhost:{{dev_port}}/width \
        -H 'Content-Type: application/json' \
        -d '{"width":{{w}}}'

[group('inspect')]
inspect-show:
    @curl -sf -X POST localhost:{{dev_port}}/drawings/show

[group('inspect')]
inspect-hide:
    @curl -sf -X POST localhost:{{dev_port}}/drawings/hide

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
