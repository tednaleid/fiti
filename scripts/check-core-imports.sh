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
