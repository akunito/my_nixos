#!/usr/bin/env bash
# Waybar module: shows the next upcoming event from evolution-data-server's
# SQLite cache (populated by GNOME Online Accounts).
# Click handler (waybar-gcal-open.sh) opens calendar.google.com in the default browser.

set -euo pipefail

PY="${1:-python3}"
icon="📅"

# EDS calendar caches: one SQLite db per calendar source.
mapfile -d '' -t cache_dbs < <(
  find "$HOME/.cache/evolution/calendar" -maxdepth 2 -name 'cache.db' -type f -print0 2>/dev/null
)

if [[ ${#cache_dbs[@]} -eq 0 ]]; then
  printf '{"text":"%s ?","tooltip":"No calendars synced yet — open GNOME Control Center → Online Accounts, then launch GNOME Calendar once","class":"error"}\n' "$icon"
  exit 0
fi

"$PY" - "$icon" "${cache_dbs[@]}" <<'PYEOF'
import sys, json, sqlite3, datetime
from datetime import timezone

try:
    from icalendar import Calendar
    import recurring_ical_events
except ImportError as e:
    print(json.dumps({"text": "📅 !", "tooltip": f"python deps missing: {e}", "class": "error"}))
    sys.exit(0)

icon = sys.argv[1]
dbs = sys.argv[2:]
now = datetime.datetime.now(timezone.utc)
horizon = now + datetime.timedelta(days=7)

# Wrap each ECacheOBJ (bare VEVENT) in a VCALENDAR header so icalendar can parse.
# Parse per-row to tolerate individual malformed events (Google sometimes emits
# properties with X-LIC-ERROR notes that strict parsers reject).
events = []
for db in dbs:
    try:
        # Read-only open so we don't fight with EDS factory writes.
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        # Only fetch rows whose occurrence window overlaps [now, horizon].
        # For recurring rows, occur_end is the LAST recurrence end (often far future),
        # so they pass this filter and get expanded below.
        # EDS stores occur_start/occur_end as "YYYYMMDDhhmmss" (no T separator,
        # no Z suffix). String comparison only works if both sides match that
        # format exactly — using strftime("%Y%m%dT%H%M%S") here caused the 'T'
        # at position 8 to sort *higher* than the digits in DB rows, silently
        # filtering out most timed events.
        rows = conn.execute(
            "SELECT ECacheOBJ FROM ECacheObjects "
            "WHERE (occur_start IS NULL OR occur_start <= ?) "
            "  AND (occur_end IS NULL OR occur_end >= ?) "
            "  AND (status IS NULL OR status != 'CANCELLED')",
            (horizon.strftime("%Y%m%d%H%M%S"), now.strftime("%Y%m%d%H%M%S")),
        ).fetchall()
        conn.close()
    except Exception:
        continue

    for (obj,) in rows:
        if not obj:
            continue
        ical_text = (
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//waybar//EN\r\n"
            + obj.strip()
            + "\r\nEND:VCALENDAR\r\n"
        )
        try:
            cal = Calendar.from_ical(ical_text)
            occurrences = recurring_ical_events.of(cal).between(now, horizon)
        except Exception:
            continue
        for ev in occurrences:
            start = ev.get("DTSTART")
            if start is None:
                continue
            s = start.dt
            # All-day events: date → midnight in local TZ
            if isinstance(s, datetime.date) and not isinstance(s, datetime.datetime):
                local_tz = datetime.datetime.now().astimezone().tzinfo
                s = datetime.datetime.combine(s, datetime.time.min, tzinfo=local_tz)
            elif s.tzinfo is None:
                s = s.replace(tzinfo=timezone.utc)
            if not (now <= s <= horizon):
                continue
            title = str(ev.get("SUMMARY") or "(no title)")
            events.append((s, title))

events.sort(key=lambda x: x[0])

if not events:
    print(json.dumps({"text": icon, "tooltip": "No upcoming events (next 7d)", "class": "empty"}))
    sys.exit(0)

local_tz = datetime.datetime.now().astimezone().tzinfo
today = datetime.datetime.now(local_tz).date()

def format_line(s, t):
    sl = s.astimezone(local_tz)
    time_part = sl.strftime("%H:%M") if sl.date() == today else sl.strftime("%a %d %H:%M")
    return f"{time_part} {t}"

nxt_start, nxt_title = events[0]
nxt_local = nxt_start.astimezone(local_tz)
short = (nxt_title[:40] + "…") if len(nxt_title) > 40 else nxt_title
bar_time = nxt_local.strftime("%H:%M") if nxt_local.date() == today else nxt_local.strftime("%b %d %H:%M")
bar_text = f"{icon} {bar_time} {short}"

tooltip = "\n".join(format_line(s, t) for s, t in events[:8])

print(json.dumps({"text": bar_text, "tooltip": tooltip, "class": "ok"}))
PYEOF
