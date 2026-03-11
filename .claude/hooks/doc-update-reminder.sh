#!/bin/bash
# doc-update-reminder.sh — PostToolUse hook
# Fires after Write/Edit on doc-relevant files and emits a one-line reminder.
# Non-blocking: outputs a reminder that Claude sees in its context window.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only process Write/Edit
case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# Get the file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Pattern → reminder mapping
case "$FILE_PATH" in
  */system/app/*.nix)
    echo "REMINDER: You modified a system service module. Check if a related doc exists in docs/akunito/infrastructure/services/ or docs/system-modules/ and update it."
    ;;
  */system/hardware/*.nix)
    echo "REMINDER: You modified a hardware module. Check docs/system-modules/hardware-modules.md and update if needed."
    ;;
  */user/app/*/*.nix)
    echo "REMINDER: You modified a user app module. Check if a related doc exists in docs/user-modules/ and update it."
    ;;
  */profiles/*-config.nix)
    echo "REMINDER: You modified a profile config. If you changed feature flags, check profile/infrastructure docs."
    ;;
  */lib/defaults.nix)
    echo "REMINDER: You modified feature flag defaults. Update docs/profile-feature-flags.md to reflect the changes."
    ;;
  */templates/openclaw/*)
    echo "REMINDER: You modified OpenClaw templates. Check docs/akunito/infrastructure/services/openclaw/ and update if needed."
    ;;
  */docs/*.md|*/docs/**/*.md)
    echo "REMINDER: You modified documentation. Run 'python3 scripts/generate_docs_index.py' before committing to regenerate Router/Catalog."
    ;;
esac

exit 0
