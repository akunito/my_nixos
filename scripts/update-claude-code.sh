#!/usr/bin/env bash
# Update claude-code-bin overlay in flake-base.nix to the latest version
# Usage: ./scripts/update-claude-code.sh [--apply]
#   --apply    Also run darwin-rebuild switch after updating

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLAKE_BASE="$DOTFILES_DIR/lib/flake-base.nix"
BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Get current and latest versions
CURRENT_VERSION=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
LATEST_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null)

if [[ -z "$LATEST_VERSION" ]]; then
  echo "ERROR: Could not fetch latest version from npm"
  exit 1
fi

echo "Current: $CURRENT_VERSION"
echo "Latest:  $LATEST_VERSION"

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating claude-code-bin: $CURRENT_VERSION → $LATEST_VERSION"

# Prefetch binary hash for darwin-arm64
echo "Fetching hash for darwin-arm64..."
HASH_DARWIN_ARM64=$(nix-prefetch-url --type sha256 "$BASE_URL/$LATEST_VERSION/darwin-arm64/claude" 2>/dev/null)
SRI_DARWIN_ARM64=$(nix hash convert --hash-algo sha256 --to sri "$HASH_DARWIN_ARM64" 2>/dev/null)

echo "  darwin-arm64: $SRI_DARWIN_ARM64"

# Check if overlay block already exists
if grep -q 'claude-code-bin = prev.claude-code-bin.overrideAttrs' "$FLAKE_BASE"; then
  # Update existing overlay — replace version and hash
  sed "s|version = \"[0-9.]*\";  # claude-code-pin|version = \"$LATEST_VERSION\";  # claude-code-pin|" "$FLAKE_BASE" > "$FLAKE_BASE.tmp"
  mv "$FLAKE_BASE.tmp" "$FLAKE_BASE"
  sed "s|\"darwin-arm64\" = \"sha256-[^\"]*\";|\"darwin-arm64\" = \"$SRI_DARWIN_ARM64\";|" "$FLAKE_BASE" > "$FLAKE_BASE.tmp"
  mv "$FLAKE_BASE.tmp" "$FLAKE_BASE"
  echo "Updated existing overlay in flake-base.nix"
else
  echo "ERROR: claude-code-bin overlay block not found in $FLAKE_BASE"
  echo "Please add the overlay manually first, then this script can maintain it."
  exit 1
fi

# Verify the edit
echo ""
echo "Overlay now reads:"
grep -A 5 'claude-code-bin = prev.claude-code-bin' "$FLAKE_BASE"

if [[ "${1:-}" == "--apply" ]]; then
  echo ""
  echo "Rebuilding darwin..."
  sudo darwin-rebuild switch --flake "$DOTFILES_DIR#MACBOOK-KOMI"
  echo ""
  echo "Done! $(claude --version)"
else
  echo ""
  echo "Run with --apply to also rebuild, or manually:"
  echo "  sudo darwin-rebuild switch --flake $DOTFILES_DIR#MACBOOK-KOMI"
fi
