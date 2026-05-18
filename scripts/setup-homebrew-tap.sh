#!/usr/bin/env bash
# ABOUTME: Creates the tednaleid/homebrew-fiti tap repo on GitHub and seeds it
# ABOUTME: with an initial cask file from the latest fiti release.
set -euo pipefail

OWNER="tednaleid"
TAP_REPO="homebrew-fiti"
MAIN_REPO="fiti"

# -- Preflight checks --

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required. Install with: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: not authenticated with gh. Run: gh auth login"
    exit 1
fi

# -- Get latest release version and DMG sha256 --

echo "Fetching latest release info..."
VERSION=$(gh release view --repo "${OWNER}/${MAIN_REPO}" --json tagName -q .tagName)
DMG_URL="https://github.com/${OWNER}/${MAIN_REPO}/releases/download/${VERSION}/fiti-${VERSION}.dmg"

echo "Downloading fiti-${VERSION}.dmg to compute SHA-256..."
SHA256=$(curl -sL "$DMG_URL" | shasum -a 256 | awk '{print $1}')
echo "  Version: ${VERSION}"
echo "  SHA-256: ${SHA256}"

# -- Create the tap repo --

if gh repo view "${OWNER}/${TAP_REPO}" &>/dev/null; then
    echo "Repo ${OWNER}/${TAP_REPO} already exists, skipping creation."
else
    echo "Creating ${OWNER}/${TAP_REPO}..."
    gh repo create "${OWNER}/${TAP_REPO}" --public \
        --description "Homebrew tap for fiti, a native macOS transparent drawing overlay"
fi

# -- Clone, populate, and push --

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

gh repo clone "${OWNER}/${TAP_REPO}" "$WORKDIR"
cd "$WORKDIR"

mkdir -p Casks

cat > Casks/fiti.rb << CASK
cask "fiti" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${OWNER}/${MAIN_REPO}/releases/download/#{version}/fiti-#{version}.dmg"
  name "fiti"
  desc "Native macOS transparent drawing overlay (telestrator-style)"
  homepage "https://github.com/${OWNER}/${MAIN_REPO}"

  depends_on macos: ">= :sonoma"

  app "Fiti.app"

  zap trash: [
    "~/Library/Preferences/com.fiti.app.plist",
    "~/Library/Caches/com.fiti.app",
  ]
end
CASK

cat > README.md << 'README'
# homebrew-fiti

Homebrew tap for [fiti](https://github.com/tednaleid/fiti), a native macOS transparent drawing overlay.

## Install

```bash
brew install --cask tednaleid/fiti/fiti
```

Or:

```bash
brew tap tednaleid/fiti
brew install --cask fiti
```

## Update

```bash
brew upgrade --cask fiti
```
README

git add Casks/fiti.rb README.md
git commit -m "Initial cask for fiti ${VERSION}"
git push

echo ""
echo "Tap repo created and populated at: https://github.com/${OWNER}/${TAP_REPO}"
echo ""
echo "-- Next step: create a fine-grained Personal Access Token --"
echo ""
echo "1. Go to: https://github.com/settings/personal-access-tokens/new"
echo "2. Token name: fiti-homebrew-tap"
echo "3. Repository access: Only select repositories -> ${OWNER}/${TAP_REPO}"
echo "4. Permissions: Contents -> Read and write"
echo "5. Generate the token and copy it"
echo ""
echo "Then set it as a secret on the fiti repo:"
echo ""
echo "  gh secret set HOMEBREW_TAP_TOKEN --repo ${OWNER}/${MAIN_REPO}"
echo ""
echo "(Paste the token when prompted.)"
