#!/usr/bin/env bash
set -euo pipefail

# Waybar module: shows the next upcoming Google Calendar event.
# Click handler (waybar-gcal-open.sh) opens calendar.google.com in the default browser.
# Auth is one-shot via `gcalcli init` (uses creds from secrets/domains.nix).

GCALCLI_BIN="${1:-gcalcli}"

icon="📅"

emit() {
  # $1=text $2=tooltip $3=class
  local text tooltip class
  text="$1"
  tooltip="$2"
  class="$3"
  # Minimal JSON escaping
  text="${text//\\/\\\\}"; text="${text//\"/\\\"}"
  tooltip="${tooltip//\\/\\\\}"; tooltip="${tooltip//\"/\\\"}"
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
}

if ! command -v "$GCALCLI_BIN" >/dev/null 2>&1; then
  emit "$icon ?" "gcalcli not found in PATH" "error"
  exit 0
fi

# Detect un-authenticated state cheaply: oauth_creds file location varies by gcalcli version.
if [[ ! -f "${HOME}/.gcalcli_oauth" && ! -f "${HOME}/.config/gcalcli/oauth_creds" ]]; then
  emit "$icon ?" "gcalcli not authenticated — run: gcalcli init" "error"
  exit 0
fi

# Fetch agenda from now through end of tomorrow. --tsv gives stable parse-able output.
# Columns: start_date \t start_time \t end_date \t end_time \t link \t title
if ! agenda="$("$GCALCLI_BIN" agenda --nostarted --tsv --military 2>/dev/null)"; then
  emit "$icon !" "gcalcli agenda failed" "error"
  exit 0
fi

if [[ -z "${agenda//[[:space:]]/}" ]]; then
  emit "$icon" "No upcoming events" "empty"
  exit 0
fi

# First non-empty line = next event.
first_line=""
while IFS= read -r line; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  first_line="$line"
  break
done <<<"$agenda"

if [[ -z "$first_line" ]]; then
  emit "$icon" "No upcoming events" "empty"
  exit 0
fi

# Parse TSV
IFS=$'\t' read -r start_date start_time _end_date _end_time _link title <<<"$first_line"

# Compact "HH:MM Title" (truncate long titles for the bar)
short_title="${title:0:40}"
[[ ${#title} -gt 40 ]] && short_title="${short_title}…"

# If start_date is today, drop the date; otherwise show "Mon DD HH:MM"
today="$(date +%Y-%m-%d)"
if [[ "$start_date" == "$today" ]]; then
  bar_text="$icon ${start_time} ${short_title}"
else
  # %b = abbreviated month
  day_label="$(date -d "$start_date" +'%b %d' 2>/dev/null || echo "$start_date")"
  bar_text="$icon ${day_label} ${start_time} ${short_title}"
fi

# Tooltip: today + tomorrow agenda (up to 8 lines)
tooltip_lines=""
count=0
while IFS= read -r line; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  IFS=$'\t' read -r sd st _ed _et _ln ttl <<<"$line"
  if [[ "$sd" == "$today" ]]; then
    label="${st} ${ttl}"
  else
    label="$(date -d "$sd" +'%a %d' 2>/dev/null || echo "$sd") ${st} ${ttl}"
  fi
  if [[ -z "$tooltip_lines" ]]; then
    tooltip_lines="$label"
  else
    tooltip_lines="${tooltip_lines}\n${label}"
  fi
  count=$((count + 1))
  [[ $count -ge 8 ]] && break
done <<<"$agenda"

emit "$bar_text" "$tooltip_lines" "ok"
