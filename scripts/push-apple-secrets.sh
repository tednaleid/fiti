#!/usr/bin/env bash
# ABOUTME: Pushes Apple signing secrets from the apple-developer-signing keychain
# ABOUTME: service to this repo's GitHub Actions secrets. Idempotent.
set -euo pipefail

SERVICE="apple-developer-signing"
OWNER="tednaleid"
REPO="fiti"

DRY_RUN=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        -h|--help) echo "Usage: $0 [--dry-run] [--force]"; exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# -- Preflight --

command -v gh >/dev/null || { echo "Error: gh CLI required. Install with: brew install gh" >&2; exit 1; }
gh auth status &>/dev/null || { echo "Error: not authenticated with gh. Run: gh auth login" >&2; exit 1; }

# -- Check existing secrets on GitHub --

existing=$(gh secret list --repo "$OWNER/$REPO" --json name -q '.[].name' 2>/dev/null || true)

want=(APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD)
missing=()
for name in "${want[@]}"; do
    if [[ "$FORCE" == 1 ]] || ! grep -Fxq "$name" <<<"$existing"; then
        missing+=("$name")
    fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All Apple secrets already set on $OWNER/$REPO. Use --force to overwrite."
    exit 0
fi

echo "Will set on $OWNER/$REPO: ${missing[*]}"

if [[ "$DRY_RUN" == 1 ]]; then
    echo "(dry run -- not reading keychain, not calling gh secret set or security export)"
    exit 0
fi

# -- Read keychain --

apple_id=$(security find-generic-password -s "$SERVICE" -a APPLE_ID -w 2>/dev/null) \
    || { echo "APPLE_ID not in keychain. Run ./scripts/seed-apple-keychain.sh first" >&2; exit 1; }
asp=$(security find-generic-password -s "$SERVICE" -a APPLE_APP_SPECIFIC_PASSWORD -w 2>/dev/null) \
    || { echo "APPLE_APP_SPECIFIC_PASSWORD not in keychain. Run ./scripts/seed-apple-keychain.sh first" >&2; exit 1; }

# -- Derive team ID from cert --

team_line=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1)
[[ -z "$team_line" ]] && { echo "No Developer ID Application identity in keychain" >&2; exit 1; }
team_id=$(echo "$team_line" | sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/')

echo "Using team ID: $team_id"

# -- Export cert if needed --

need_cert=0
for name in "${missing[@]}"; do
    [[ "$name" == APPLE_CERTIFICATE || "$name" == APPLE_CERTIFICATE_PASSWORD ]] && need_cert=1
done

if [[ "$need_cert" == 1 ]]; then
    export_pass=$(openssl rand -base64 32)
    tmp_p12=$(mktemp -t apple-cert-XXXXXX).p12
    trap 'rm -f "$tmp_p12"' EXIT

    echo "Exporting Developer ID Application identity to temporary p12..."
    echo "(You may see a keychain access prompt -- click 'Always Allow'.)"
    security export \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -t identities \
        -f pkcs12 \
        -P "$export_pass" \
        -o "$tmp_p12"
    cert_b64=$(base64 < "$tmp_p12")
fi

# -- Push secrets --

for name in "${missing[@]}"; do
    case "$name" in
        APPLE_ID)                    val="$apple_id" ;;
        APPLE_TEAM_ID)               val="$team_id" ;;
        APPLE_APP_SPECIFIC_PASSWORD) val="$asp" ;;
        APPLE_CERTIFICATE)           val="$cert_b64" ;;
        APPLE_CERTIFICATE_PASSWORD)  val="$export_pass" ;;
    esac
    echo "  Setting $name..."
    printf '%s' "$val" | gh secret set "$name" --repo "$OWNER/$REPO"
done

echo
echo "Done. $OWNER/$REPO has ${#missing[@]} Apple signing secret(s) set."
