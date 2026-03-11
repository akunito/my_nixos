#!/usr/bin/env bash
# Idempotent installer for git hooks.
# Symlinks repo-tracked hooks from scripts/git-hooks/ into .git/hooks/.
# Called by install.sh during system deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_SRC="$SCRIPT_DIR/git-hooks"
HOOKS_DST="$REPO_DIR/.git/hooks"

# Ensure .git/hooks exists (should always exist in a git repo)
if [ ! -d "$HOOKS_DST" ]; then
    echo "Warning: $HOOKS_DST does not exist. Not a git repository?"
    exit 0
fi

# Install each hook from scripts/git-hooks/
for hook in "$HOOKS_SRC"/*; do
    [ -f "$hook" ] || continue
    hook_name=$(basename "$hook")
    target="$HOOKS_DST/$hook_name"
    relative_src="../../scripts/git-hooks/$hook_name"

    # Skip if already correctly symlinked
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$relative_src" ]; then
        echo "  Hook '$hook_name' already installed."
        continue
    fi

    # Back up existing hook if it's a regular file (not our symlink)
    if [ -f "$target" ] && [ ! -L "$target" ]; then
        echo "  Backing up existing '$hook_name' to '${hook_name}.bak'"
        mv "$target" "${target}.bak"
    fi

    # Create symlink
    ln -sf "$relative_src" "$target"
    chmod +x "$hook"
    echo "  Installed hook: $hook_name -> $relative_src"
done

echo "  Git hooks setup complete."
