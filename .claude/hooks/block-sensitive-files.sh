#!/bin/bash
# block-sensitive-files.sh — PreToolUse hook
# Blocks Claude Code from reading sensitive files (SSH keys, credentials, etc.)
#
# Intercepts: Read, Grep, Glob, Bash tools
# Returns permissionDecision: "deny" JSON when a sensitive file access is detected.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Exit early if no tool name
[ -z "$TOOL_NAME" ] && exit 0

# Sensitive path patterns (extended glob-like matching via grep -E)
SENSITIVE_PATHS=(
  '/\.ssh/id_'
  '/\.ssh/.*\.pem'
  '/\.ssh/.*\.key'
  '/\.ssh/authorized_keys'
  '/\.gnupg/'
  '/\.aws/credentials'
  '/\.kube/config'
  '/\.docker/config\.json'
  '/\.git-crypt/'
  '/\.claude/\.credentials\.json'
  '/etc/shadow'
  '/etc/gshadow'
)

# Build a single regex from all patterns
SENSITIVE_REGEX=$(IFS='|'; echo "${SENSITIVE_PATHS[*]}")

deny_access() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

check_path() {
  local path="$1"
  if echo "$path" | grep -qE "$SENSITIVE_REGEX"; then
    deny_access "BLOCKED: Access to sensitive file denied: $path\n\nThis file contains credentials or secrets that should never be read by Claude Code.\nIf you need information from this file, ask the user to provide the relevant details."
  fi
}

case "$TOOL_NAME" in
  Read|Edit|Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -n "$FILE_PATH" ] && check_path "$FILE_PATH"
    ;;
  Grep)
    SEARCH_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    [ -n "$SEARCH_PATH" ] && check_path "$SEARCH_PATH"
    ;;
  Glob)
    GLOB_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    GLOB_PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
    [ -n "$GLOB_PATH" ] && check_path "$GLOB_PATH"
    [ -n "$GLOB_PATTERN" ] && check_path "$GLOB_PATTERN"
    ;;
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$COMMAND" ] && exit 0

    # Check if command accesses sensitive files
    if echo "$COMMAND" | grep -qE "$SENSITIVE_REGEX"; then
      deny_access "BLOCKED: Command attempts to access sensitive file.\n\nDetected sensitive file pattern in: $COMMAND\n\nNever read SSH keys, credentials, or secrets directly. Ask the user for needed values."
    fi

    # Check for exfiltration patterns (base64/xxd encoding of key files)
    if echo "$COMMAND" | grep -qE '(base64|xxd|od\s).*(/\.ssh/|/\.gnupg/|/etc/shadow|credentials)'; then
      deny_access "BLOCKED: Potential credential exfiltration detected.\n\nCommand appears to encode sensitive file contents: $COMMAND"
    fi
    if echo "$COMMAND" | grep -qE '(/\.ssh/|/\.gnupg/|/etc/shadow|credentials).*(base64|xxd|od\s)'; then
      deny_access "BLOCKED: Potential credential exfiltration detected.\n\nCommand appears to encode sensitive file contents: $COMMAND"
    fi
    ;;
esac

# Allow everything else
exit 0
