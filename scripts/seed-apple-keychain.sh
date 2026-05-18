#!/usr/bin/env bash
# ABOUTME: One-time interactive seeder for the apple-developer-signing keychain
# ABOUTME: service. Run once per machine; future macOS apps reuse the cached values.
set -euo pipefail

SERVICE="apple-developer-signing"

probe() { security find-generic-password -s "$SERVICE" -a "$1" -w &>/dev/null; }
store() { security add-generic-password -U -s "$SERVICE" -a "$1" -w "$2"; }

echo "Checking Apple signing prerequisites..."
echo

# -- Developer ID Application identity --

cert_line=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 || true)

if [[ -z "$cert_line" ]]; then
    cat <<'EOF'
No Developer ID Application certificate found in your login keychain.

To get one:
  1. Visit https://developer.apple.com/account/resources/certificates/list
  2. Create or download a "Developer ID Application" certificate
  3. Double-click the .cer to import it into Keychain Access
  4. Verify the matching private key is in your login keychain
     (expand the cert in "My Certificates" -- the private key should appear beneath it)
  5. Re-run this script
EOF
    exit 1
fi

team_id=$(echo "$cert_line" | sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/')
echo "OK  Developer ID Application cert found (team $team_id)"

# -- APPLE_ID --

if probe APPLE_ID; then
    echo "OK  APPLE_ID already cached"
else
    default_email="$(git config user.email 2>/dev/null || true)"
    read -r -p "Apple ID email${default_email:+ [$default_email]}: " apple_id
    apple_id="${apple_id:-$default_email}"
    [[ -z "$apple_id" ]] && { echo "Apple ID is required" >&2; exit 1; }
    store APPLE_ID "$apple_id"
    echo "OK  APPLE_ID stored"
fi

# -- APPLE_APP_SPECIFIC_PASSWORD --

if probe APPLE_APP_SPECIFIC_PASSWORD; then
    echo "OK  APPLE_APP_SPECIFIC_PASSWORD already cached"
else
    cat <<'EOF'

Generate an app-specific password (notarytool needs one):
  1. Visit https://appleid.apple.com/account/manage
  2. Sign in with your Apple ID
  3. Sign-In and Security -> App-Specific Passwords -> Generate Password
  4. Label it something like "notarytool" or "github-actions"
  5. Copy the password -- Apple only shows it ONCE

One app-specific password works for all your apps. You do not need a
separate one per project.
EOF
    echo
    read -r -s -p "Paste app-specific password: " asp
    echo
    [[ -z "$asp" ]] && { echo "Password is required" >&2; exit 1; }
    store APPLE_APP_SPECIFIC_PASSWORD "$asp"
    echo "OK  APPLE_APP_SPECIFIC_PASSWORD stored"
fi

echo
echo "Keychain seeded. Next: ./scripts/push-apple-secrets.sh"
