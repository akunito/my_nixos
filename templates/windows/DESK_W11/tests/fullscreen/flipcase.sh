#!/usr/bin/env bash
# flipcase.sh <name> <fliptest args...>: timed PresentMon capture around one fliptest run, prints present modes
P=/mnt/c/Users/diego/AppData/Local/Temp/perf; n=$1; shift
rm -f $P/$n.done; echo 9 > $P/$n.req
sleep 2.5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\diego\AppData\Local\Temp\perf\run-flip.ps1' "$*" >/dev/null
for i in $(seq 40); do [ -f $P/$n.done ] && break; sleep 0.5; done
python3 - "$P/$n.csv" "$n" <<'PY'
import csv, collections, sys
rows=[r for r in csv.DictReader(open(sys.argv[1], encoding='utf-8-sig')) if r['Application'].lower()=='fliptest.exe']
c=collections.Counter(r['PresentMode'] for r in rows)
print(f"{sys.argv[2]}: {len(rows)} frames", c.most_common())
PY
