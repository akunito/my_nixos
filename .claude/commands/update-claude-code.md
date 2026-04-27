Update Claude Code to the latest version.

Run the update script at `scripts/update-claude-code.sh` to check for a newer version of Claude Code and update the overlay in `lib/flake-base.nix`.

## Steps

1. Run `scripts/update-claude-code.sh --apply` from the dotfiles root
2. If the script reports "Already up to date", tell the user and stop
3. If the rebuild succeeds, report the old and new version
4. If anything fails, show the error and suggest running manually
