#!/bin/bash
# block-nixos-rebuild.sh — PreToolUse hook
# Blocks bare nixos-rebuild switch commands and redirects to install.sh
#
# This prevents Claude Code from EVER running nixos-rebuild switch directly,
# whether locally or via SSH. Using nixos-rebuild without install.sh causes
# hardware-configuration.nix mismatches and boot failures.

COMMAND=$(jq -r '.tool_input.command // empty')

# Exit early if no command
[ -z "$COMMAND" ] && exit 0

# Check for dangerous patterns: nixos-rebuild switch (with or without sudo, via ssh, etc.)
if echo "$COMMAND" | grep -qiE 'nixos-rebuild\s+switch'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: bare nixos-rebuild switch is FORBIDDEN on ALL machines. It uses the WRONG hardware-configuration.nix and causes boot failures.\n\nUse install.sh instead (flags: -s always; -d on docker hosts VPS/NAS/LXC/DESK_W11; -h on LXC only; -u ONLY when a flake.lock update is the task):\n  - Local deploy:  ./deploy.sh --profile <PROFILE>\n  - LXC containers: ssh -A admin@<IP> \"cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles <PROFILE> -s -d -h\"\n  - VPS_PROD:      ssh -A -p 56777 akunito@100.64.0.6 \"cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./install.sh ~/.dotfiles VPS_PROD -s -d\"\n  - Desktops/Laptops: same chain over ssh -A with -s (Claude may run it; sudo -n true saying \"password required\" is a false negative)\n\nChanges MUST be committed AND pushed FIRST (the chain resets to origin/main). Details: .claude/rules/deployment.md"
    }
  }'
  exit 0
fi

# Allow everything else
exit 0
