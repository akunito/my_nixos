#!/bin/sh
# Smart screenshot workflow for SwayFX
# Usage: screenshot.sh [full|area|clipboard]
#
# full: Captures the currently focused monitor (auto-detects)
# area: Allows selecting a region with slurp
# clipboard: Loads current clipboard image (image/png) for editing

set -e  # Exit on error

MODE="${1:-area}"

TMP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
TMP_FILE="$(mktemp "$TMP_DIR/screenshot-XXXXXX.png")"

cleanup() {
  rm -f "$TMP_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

capture() {
  if [ "$MODE" = "full" ]; then
      # Detect currently focused output
      FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .name')

      if [ -z "$FOCUSED_OUTPUT" ] || [ "$FOCUSED_OUTPUT" = "null" ]; then
          # Fallback: use first output if no focused output found
          FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[0].name')
      fi

      grim -o "$FOCUSED_OUTPUT" "$TMP_FILE"
  elif [ "$MODE" = "area" ]; then
      grim -g "$(slurp)" "$TMP_FILE"
  elif [ "$MODE" = "clipboard" ]; then
      if ! wl-paste --type image/png > "$TMP_FILE" 2>/dev/null; then
        echo "No image/png in clipboard"
        exit 1
      fi
  else
      echo "Usage: screenshot.sh [full|area|clipboard]"
      exit 1
  fi
}

copy_on_exit() {
  # Hybrid approach:
  # - Load from file (-f) so Swappy behaves normally (Ctrl+C works inside Swappy)
  # - If supported, emit final edited image to stdout on exit (-o -) and copy it
  if swappy --help 2>&1 | grep -qE '(^|[[:space:]])-o([[:space:]]|,|$)|--output'; then
    swappy -f "$TMP_FILE" -o - | wl-copy --type image/png
  else
    swappy -f "$TMP_FILE"
    # Best-effort fallback: copy the last saved/captured file
    wl-copy --type image/png < "$TMP_FILE"
  fi

  # Save the path of the most recently saved screenshot for Ctrl+Alt+C keybinding
  # This allows copying the file path to clipboard (useful for Claude Code)
  SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
  LATEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -n 1)
  if [ -n "$LATEST_SCREENSHOT" ]; then
    echo "$LATEST_SCREENSHOT" > /tmp/last-screenshot-path
  fi
}

capture
copy_on_exit

