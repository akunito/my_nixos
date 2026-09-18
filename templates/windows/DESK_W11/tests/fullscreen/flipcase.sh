#!/usr/bin/env bash
# flipcase.sh <name> <fliptest args...>: timed PresentMon capture around one fliptest run, prints present modes
P=/mnt/c/Users/diego/AppData/Local/Temp/perf; n=$1; shift
W_EXE="C:\\Users\\diego\\AppData\\Local\\Temp\\perf\\fliptest.exe"
G="/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe"
# Focus the primary monitor's workspace first: GlazeWM puts a new window on the
# FOCUSED workspace and would otherwise drag it to the other monitor.
ws=$("$G" query monitors | python3 -c 'import json,sys
m=[x for x in json.load(sys.stdin)["data"]["monitors"] if x["x"]==0 and x["y"]==0][0]
print([c["name"] for c in m["children"] if c["isDisplayed"]][0])')
"$G" command focus --workspace "$ws" >/dev/null; sleep 1
# Start the window first and let it settle (it grows to fullscreen and the pill
# has to be hidden), then measure: a capture that overlaps the launch is mostly
# startup frames.
powershell.exe -NoProfile -Command 'Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force' 2>/dev/null   # leftovers would be measured too
sleep 1
rm -f "$P/$n.done" "$P/$n.csv"
powershell.exe -NoProfile -Command "Start-Process '"'"'$W_EXE'"'"' -ArgumentList '"'"'$*'"'"'" >/dev/null 2>&1
sleep 2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\diego\AppData\Local\Temp\perf\park-primary.ps1' >/dev/null 2>&1
sleep 1.5
echo 6 > "$P/$n.req"
for i in $(seq 40); do [ -f "$P/$n.done" ] && break; sleep 0.5; done
python3 - "$P/$n.csv" "$n" <<'PY'
import csv, collections, sys
rows=[r for r in csv.DictReader(open(sys.argv[1], encoding='utf-8-sig')) if r['Application'].lower()=='fliptest.exe']
c=collections.Counter(r['PresentMode'] for r in rows)
print(f"{sys.argv[2]}: {len(rows)} frames", c.most_common())
PY
