#!/usr/bin/env bash
# Fullscreen-window suite for DESK_W11 (GlazeWM + Zebar + taskbar).
# Needs: %TEMP%\perf populated (see README) and the capture daemon running
# (start-cap-daemon.ps1, one UAC prompt). Takes ~2 min and steals the primary
# monitor while each case runs.
set -u
P=/mnt/c/Users/diego/AppData/Local/Temp/perf
W='powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
pass=0; fail=0
ok()  { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
ko()  { printf '  FAIL %s -- %s\n' "$1" "$2"; fail=$((fail+1)); }

flip() { # flip <name> <fliptest args...>  -> prints dominant present mode
  local n=$1; shift
  rm -f "$P/$n.done"; echo 9 > "$P/$n.req"; sleep 2.5
  $W 'C:\Users\diego\AppData\Local\Temp\perf\run-flip.ps1' "$*" >/dev/null
  for _ in $(seq 40); do [ -f "$P/$n.done" ] && break; sleep 0.5; done
  python3 - "$P/$n.csv" <<'PY'
import csv, collections, sys
rows=[r for r in csv.DictReader(open(sys.argv[1], encoding='utf-8-sig')) if r['Application'].lower()=='fliptest.exe']
c=collections.Counter(r['PresentMode'] for r in rows)
print(c.most_common(1)[0][0] if c else 'no-frames')
PY
}

echo "== 1. fullscreen window reaches the screen directly (no overlay above)"
m=$(flip s1-fullscreen 6 0)
case "$m" in *"Independent Flip") ok "present mode: $m";; *) ko "present mode" "$m (an overlay is above the window; check the Zebar pill)";; esac

echo "== 2. the Zebar pill is back after the fullscreen window closes"
sleep 1
p=$($W 'C:\Users\diego\AppData\Local\Temp\perf\pill-state.ps1')
case "$p" in *"visible=True"*) ok "$p";; *) ko "pill state" "$p";; esac

echo "== 3. workspace switch hides a normal window and the taskbar drops back"
out=$($W 'C:\Users\diego\AppData\Local\Temp\perf\ws-hide-test.ps1')
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "2 switched away .*cloaked=[1-9]" && ok "hidden while away" || ko "hidden while away" "not cloaked"
echo "$out" | grep -q "3 back home .*cloaked=0" && ok "shown on return" || ko "shown on return" "still cloaked"
echo "$out" | grep -q "5 present modes after return: Hardware Composed: Independent Flip\|5 present modes after return: Hardware: Independent Flip" && ok "taskbar not above after return" || ko "taskbar after return" "$(echo "$out" | grep '5 present')"

# A game is elevated (anti-cheat) AND in GlazeWM's fullscreen state; only then
# does GlazeWM mark it fullscreen for the taskbar. An elevated FLOATING window
# cannot be raised above the taskbar at all (SetWindowPos is denied).
echo "== 4. same, with an ELEVATED fullscreen window (what a game looks like)"
rm -f "$P/suite-elev.out"; echo "wsfs.ps1" > "$P/suite-elev.elev"   # fullscreen state, like a game
for _ in $(seq 90); do [ -f "$P/suite-elev.out" ] && break; sleep 1; done
out=$(cat "$P/suite-elev.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "2 switched away .*cloaked=[1-9]" && ok "elevated window hidden while away" || ko "elevated window hidden" "not cloaked (reposition_window aborts on access denied?)"
echo "$out" | grep -q "3 back home .*cloaked=0" && ok "elevated window shown on return" || ko "elevated window shown" "still cloaked"
echo "$out" | grep -q "5 present modes after return: Hardware Composed: Independent Flip\|5 present modes after return: Hardware: Independent Flip" && ok "taskbar not above after return (elevated)" || ko "taskbar after return (elevated)" "$(echo "$out" | grep '5 present')"

echo "== 5. GlazeWM sees a monitor-sized ELEVATED window as fullscreen on its own"
rm -f "$P/fsauto.out"; echo "fsauto.ps1" > "$P/fsauto.elev"
for _ in $(seq 90); do [ -f "$P/fsauto.out" ] && break; sleep 1; done
out=$(cat "$P/fsauto.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "state=fullscreen" && ok "classified fullscreen (taskbar gets marked)" || ko "classification" "$(echo "$out" | head -1)"
echo "$out" | grep -q "Independent Flip" && ok "reaches the screen directly" || ko "present mode" "$(echo "$out" | tail -1)"

# The Aion 2 case: Unreal creates the window a couple of pixels larger than the
# monitor and settles to the monitor rect. GlazeWM read that as the app leaving
# OS fullscreen and dropped it to floating -> no MarkFullscreenWindow -> taskbar
# above the game -> Composed: Flip.
echo "== 6. a window that settles from oversized to exactly the monitor stays fullscreen"
rm -f "$P/fsgame.out"; echo "fsgame.ps1" > "$P/fsgame.elev"
for _ in $(seq 90); do [ -f "$P/fsgame.out" ] && break; sleep 1; done
out=$(cat "$P/fsgame.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "state=fullscreen" && ok "stays fullscreen" || ko "state" "$(echo "$out" | head -1)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
