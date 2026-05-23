# ABOUTME: fiti — native Swift telestrator POC
# ABOUTME: All commands route through this file. Use `just <recipe>`, never the underlying tool directly.

set dotenv-load := true

build_dir     := "/tmp/fiti-build"
install_dir   := env_var('HOME') / "Applications"
dev_port      := "9876"
# Code-signing identity (override via FITI_CODE_SIGN_IDENTITY in .env or shell).
# "-" means ad-hoc. Set a stable identity for distribution builds — see .env.example.
sign_identity := env_var_or_default("FITI_CODE_SIGN_IDENTITY", "-")
# Manual signing avoids Xcode demanding a DEVELOPMENT_TEAM for SPM-resource bundles
# (e.g. KeyboardShortcuts ships localized .strings that build a signed bundle target).
xcb_sign      := 'CODE_SIGN_IDENTITY="' + sign_identity + '" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""'

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
    xcodebuild -project fiti.xcodeproj -scheme fiti -configuration Debug build SYMROOT={{build_dir}} {{xcb_sign}}

# Copy the built .app to ~/Applications/Fiti.app
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
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} {{xcb_sign}}
    swift test --package-path Packages/PerfectFreehand

# Run one test by name. Swift Testing identifiers include `()`, e.g. 'swiftTestingIsWired()' or 'SmokeTests/myTest()'
[group('test')]
test-only NAME: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-unit -destination 'platform=macOS' test SYMROOT={{build_dir}} {{xcb_sign}} -only-testing:'fiti-unit/{{NAME}}'

# Run the AppKit / integration test bundle (slower; includes AppKit)
[group('test')]
test-integration: generate
    xcodebuild -project fiti.xcodeproj -scheme fiti-integration -destination 'platform=macOS' test SYMROOT={{build_dir}} {{xcb_sign}}
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

# Build, install to ~/Applications, and launch in foreground (--dev enables HTTP introspection)
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

# ─── release ──────────────────────────────────────────────────────────────

# Bump version, generate release notes, tag (annotated), and push. Pass a
# bare version (e.g. `just bump 0.1.0`); if omitted, the patch component is
# auto-incremented from the latest tag.
[group('release')]
bump version="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{version}}" ]; then
        version="{{version}}"
    else
        prev=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
        IFS='.' read -r major minor patch <<< "$prev"
        version="${major}.${minor}.$((patch + 1))"
    fi

    echo "Bumping to version $version"

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" Resources/Info.plist
    git add Resources/Info.plist
    git commit -m "Bump version to $version"

    prev_tag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
    if [ -n "$prev_tag" ]; then
        commit_log=$(git log "${prev_tag}..HEAD" --oneline --no-merges)
    else
        commit_log=$(git log --oneline --no-merges -20)
    fi

    notes_file=$(mktemp)
    trap 'rm -f "$notes_file"' EXIT

    if command -v claude &>/dev/null; then
        prompt="Generate concise release notes for version $version of fiti (a native macOS Swift drawing/annotation overlay).
    Here are the commits since ${prev_tag:-the beginning}:

    ${commit_log}

    Guidelines:
    - Group related commits into a single bullet point
    - Focus on user-facing changes, not implementation details
    - Skip version bumps, CI changes, and purely internal refactors
    - Keep each bullet to one line, use past tense
    - Output only a bullet list (- item), nothing else"

        echo "Generating release notes with Claude..."
        if claude -p "$prompt" > "$notes_file" 2>/dev/null; then
            echo "Release notes (generated by Claude):"
        else
            echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
            echo "Release notes (from commit log, Claude failed):"
        fi
    else
        echo "$commit_log" | sed 's/^[0-9a-f]* /- /' > "$notes_file"
        echo "Release notes (from commit log):"
    fi
    cat "$notes_file"

    git tag -a "$version" -F "$notes_file"
    git push && git push --tags

# Delete a GitHub release and re-tag the current commit to re-trigger release
# workflow. Preserves the existing tag annotation.
[group('release')]
retag tag:
    #!/usr/bin/env bash
    set -euo pipefail
    notes=$(git tag -l --format='%(contents)' "{{tag}}" 2>/dev/null || echo "{{tag}}")
    notes_file=$(mktemp)
    trap 'rm -f "$notes_file"' EXIT
    echo "$notes" > "$notes_file"

    gh release delete "{{tag}}" --yes || true
    git push origin ":refs/tags/{{tag}}" || true
    git tag -d "{{tag}}" || true
    git tag -a "{{tag}}" -F "$notes_file"
    git push && git push --tags

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

# ─── assets / icons ─────────────────────────────────────────────────────

# Render an SF Symbol as a black-on-white square PNG (icon starting point; inset 0.0 = edge-to-edge)
[group('assets')]
render-symbol name output="" size="1024" inset="0.10":
    #!/usr/bin/env bash
    set -euo pipefail
    out="{{output}}"
    [ -z "$out" ] && out="{{name}}.png"
    ./scripts/render-symbol.swift "{{name}}" "$out" "{{size}}" "{{inset}}"

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
