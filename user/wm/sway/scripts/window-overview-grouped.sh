#!/usr/bin/env bash
set -euo pipefail

# Grouped window overview for Sway using rofi (two-step):
# 1) Select app (app_id or XWayland class) grouped with counts
# 2) Select specific window (workspace + title)
#
# Focuses the selected container via con_id.

# Make PATH reliable for Sway/systemd-user contexts
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

ROFI_BIN="$(command -v rofi 2>/dev/null || true)"
SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"

[ -n "$ROFI_BIN" ] || exit 0
[ -n "$SWAYMSG_BIN" ] || exit 0
[ -n "$JQ_BIN" ] || exit 0

TREE="$("$SWAYMSG_BIN" -t get_tree)"

# Collect windows with workspace context.
# We iterate workspaces and recurse within each, so we can attach workspace name.
WINDOWS_JSON="$(
  printf '%s' "$TREE" | "$JQ_BIN" -c '
    def win($ws):
      recurse(.nodes[]?, .floating_nodes[]?)
      | select(.type == "con" or .type == "floating_con")
      | select(((.app_id // "") != "") or (((.window_properties.class // "") != "")))
      | {
          id: .id,
          app_id: (.app_id // ""),
          class: (.window_properties.class // ""),
          app: (if ((.app_id // "") != "") then .app_id else (.window_properties.class // "unknown") end),
          title: (.name // ""),
          ws: $ws,
          focused: (.focused // false)
        };

    [
      .nodes[]?                                   # outputs
      | .nodes[]?                                  # workspaces (and possibly other nodes)
      | select(.type == "workspace")
      | . as $wsnode
      | ($wsnode.name // "") as $ws
      | ($wsnode | win($ws))
    ]
  '
)"

[ "$WINDOWS_JSON" != "[]" ] || exit 0

# Build grouped app list (sorted) + aligned metadata (counts/icons).
# NOTE: We must NOT store NUL bytes in bash variables (bash strings can't contain NUL).
# We keep metadata as TSV in bash arrays, and stream NUL-separated icon hints directly to rofi.
GROUPS_JSON="$(
  printf '%s\n' "$WINDOWS_JSON" \
    | "$JQ_BIN" -c '
        def icon_guess($s):
          ($s
            | ascii_downcase
            | sub("-flatpak$"; "")
            | sub("-browser$"; "")
          );

        sort_by(.app)
        | group_by(.app)
        | map({
            app: .[0].app,
            count: length,
            icon: (
              if ((.[0].app_id // "") != "") then icon_guess(.[0].app_id)
              elif ((.[0].class // "") != "") then icon_guess(.[0].class)
              else icon_guess(.[0].app)
              end
            )
          })
      '
)"

declare -a APPS=()
declare -a COUNTS=()
declare -a ICONS=()

while IFS=$'\t' read -r app count icon; do
  [ -n "${app:-}" ] || continue
  APPS+=("$app")
  COUNTS+=("${count:-0}")
  ICONS+=("${icon:-}")
done < <(
  printf '%s\n' "$GROUPS_JSON" \
    | "$JQ_BIN" -r '.[] | [ .app, (.count|tostring), (.icon // "") ] | @tsv'
)

[ "${#APPS[@]}" -gt 0 ] || exit 0

APP_IDX="$(
  for i in "${!APPS[@]}"; do
    label="${APPS[$i]}"
    if [ "${COUNTS[$i]}" -gt 1 ] 2>/dev/null; then
      label="${label} (${COUNTS[$i]})"
    fi
    # rofi icon hint: <label>\0icon\x1f<icon-name>
    printf '%s\0icon\x1f%s\n' "$label" "${ICONS[$i]}"
  done | "$ROFI_BIN" -dmenu -i -p "Apps" -format i -show-icons \
           -theme-str "listview { columns: 2; lines: 8; } element { padding: 10px; }"
)" || exit 0

# If user entered custom text, rofi can return -1; treat as cancel.
if [ -z "$APP_IDX" ] || [ "$APP_IDX" = "-1" ]; then
  exit 0
fi

APP_NAME="${APPS[$APP_IDX]:-}"
APP_COUNT="${COUNTS[$APP_IDX]:-0}"
APP_ICON="${ICONS[$APP_IDX]:-}"
[ -n "$APP_NAME" ] || exit 0

# If there is only one window for this app, jump directly to it (no submenu).
if [ "${APP_COUNT:-0}" = "1" ]; then
  TARGET_ID="$(
    printf '%s\n' "$WINDOWS_JSON" \
      | "$JQ_BIN" -r --arg app "$APP_NAME" '
          [ .[] | select(.app == $app) ][0].id // empty
        '
  )"
  [ -n "$TARGET_ID" ] || exit 0
  "$SWAYMSG_BIN" "[con_id=$TARGET_ID] focus" >/dev/null
  exit 0
fi

declare -a WIN_LABELS=()
declare -a WIN_IDS=()

while IFS=$'\t' read -r id label; do
  [ -n "${id:-}" ] || continue
  WIN_IDS+=("$id")
  WIN_LABELS+=("$label")
done < <(
  printf '%s\n' "$WINDOWS_JSON" \
    | "$JQ_BIN" -r --arg app "$APP_NAME" '
        [ .[] | select(.app == $app) ]
        | sort_by([(.focused | not), .ws, .title])
        | .[]
        | [ (.id|tostring),
            (if (.title // "") != "" then "[\(.ws)]  \(.title)" else "[\(.ws)]  (untitled)" end)
          ]
        | @tsv
      '
)

[ "${#WIN_IDS[@]}" -gt 0 ] || exit 0

WIN_IDX="$(
  for i in "${!WIN_IDS[@]}"; do
    printf '%s\0icon\x1f%s\n' "${WIN_LABELS[$i]}" "$APP_ICON"
  done | "$ROFI_BIN" -dmenu -i -p "$APP_NAME" -format i -show-icons \
           -theme-str "listview { columns: 1; lines: 10; }"
)" || exit 0

if [ -z "$WIN_IDX" ] || [ "$WIN_IDX" = "-1" ]; then
  exit 0
fi

TARGET_ID="${WIN_IDS[$WIN_IDX]:-}"
[ -n "$TARGET_ID" ] || exit 0

"$SWAYMSG_BIN" "[con_id=$TARGET_ID] focus" >/dev/null

