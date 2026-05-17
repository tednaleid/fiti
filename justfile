# ABOUTME: fiti — native Swift telestrator POC
# ABOUTME: All commands route through this file. Use `just <recipe>`, never the underlying tool directly.

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

# Build the app (Debug); output in /tmp/fiti-build to avoid Dropbox/iCloud codesign issues
[group('build')]
build: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti -configuration Debug build SYMROOT={{build_dir}}

# Remove build artifacts and the generated Xcode project
[group('build')]
clean:
    rm -rf {{build_dir}} fiti.xcodeproj DerivedData
    @echo "Clean complete."

# ─── test ─────────────────────────────────────────────────────────────────

# Run the Swift Testing test bundle
[group('test')]
test: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}}

# Run one test by name. Swift Testing identifiers include `()`, e.g. 'swiftTestingIsWired()' or 'SmokeTests/myTest()'
[group('test')]
test-only NAME: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} -only-testing:'fiti-unit/{{NAME}}'

# Run the AppKit / integration test bundle (slower; includes AppKit)
[group('test')]
test-integration: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-integration -destination 'platform=macOS' test SYMROOT={{build_dir}}

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

# Open Privacy & Security → Accessibility so you can grant Fiti the global Cmd+Opt+Z hotkey
[group('run')]
grant-accessibility:
    @open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    @echo "If Fiti isn't listed, add it with the + button:"
    @echo "  {{build_dir}}/Debug/Fiti.app"
    @echo "Then toggle it on. Ad-hoc signed builds may need re-toggling after each rebuild."

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
