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
