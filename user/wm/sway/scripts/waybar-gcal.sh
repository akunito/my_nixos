#!/usr/bin/env bash
# Waybar module: shows the next upcoming event from evolution-data-server's
# locally cached ICS files (populated by GNOME Online Accounts).
# Click handler (waybar-gcal-open.sh) opens calendar.google.com in the default browser.

set -euo pipefail

PY="${1:-python3}"
icon="📅"

# EDS ICS cache locations (try both modern and legacy paths)
CACHE_DIRS=(
  "$HOME/.cache/evolution/calendar"
  "$HOME/.local/share/evolution/calendar"
)

ics_files=()
for d in "${CACHE_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r -d '' f; do
    ics_files+=("$f")
  done < <(find "$d" -name 'calendar.ics' -type f -print0 2>/dev/null)
done

if [[ ${#ics_files[@]} -eq 0 ]]; then
  printf '{"text":"%s ?","tooltip":"No calendars synced yet — open GNOME Control Center → Online Accounts","class":"error"}\n' "$icon"
  exit 0
fi

"$PY" - "$icon" "${ics_files[@]}" <<'PYEOF'
import sys, json, datetime
from datetime import timezone

try:
    from icalendar import Calendar
except ImportError:
    print(json.dumps({"text": "📅 !", "tooltip": "python icalendar missing", "class": "error"}))
    sys.exit(0)

icon = sys.argv[1]
paths = sys.argv[2:]
now = datetime.datetime.now(timezone.utc)
horizon = now + datetime.timedelta(days=7)

events = []
for p in paths:
    try:
        with open(p, 'rb') as fh:
            cal = Calendar.from_ical(fh.read())
        for comp in cal.walk('VEVENT'):
            dtstart = comp.get('DTSTART')
            if dtstart is None:
                continue
            start = dtstart.dt
            # All-day events come as date; normalize to midnight UTC
            if isinstance(start, datetime.date) and not isinstance(start, datetime.datetime):
                start = datetime.datetime.combine(start, datetime.time.min, tzinfo=timezone.utc)
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone.utc)
            if now <= start <= horizon:
                title = str(comp.get('SUMMARY') or '(no title)')
                events.append((start, title))
    except Exception:
        # Tolerate a broken/partial ICS — others may still parse
        continue

events.sort(key=lambda x: x[0])

if not events:
    print(json.dumps({"text": icon, "tooltip": "No upcoming events (next 7d)", "class": "empty"}))
    sys.exit(0)

local_tz = datetime.datetime.now().astimezone().tzinfo
today = datetime.datetime.now(local_tz).date()

def format_label(s, t):
    sl = s.astimezone(local_tz)
    if sl.date() == today:
        time_str = sl.strftime("%H:%M")
    else:
        time_str = sl.strftime("%a %d %H:%M")
    return f"{time_str} {t}"

nxt_start, nxt_title = events[0]
nxt_local = nxt_start.astimezone(local_tz)
short = (nxt_title[:40] + "…") if len(nxt_title) > 40 else nxt_title
bar_time = nxt_local.strftime("%H:%M") if nxt_local.date() == today else nxt_local.strftime("%b %d %H:%M")
bar_text = f"{icon} {bar_time} {short}"

tooltip_lines = [format_label(s, t) for s, t in events[:8]]
tooltip = "\n".join(tooltip_lines)

print(json.dumps({"text": bar_text, "tooltip": tooltip, "class": "ok"}))
PYEOF
