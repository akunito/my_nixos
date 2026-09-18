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
# Every case measures real frames, so the previous window must be gone first:
# PresentMon filters by process name and would add the leftover's frames too.
settle() {
  powershell.exe -NoProfile -Command 'Get-Process fliptest, charmap -EA SilentlyContinue | Stop-Process -Force' 2>/dev/null
  for _ in $(seq 20); do
    powershell.exe -NoProfile -Command 'if (Get-Process fliptest -EA SilentlyContinue) { "yes" }' 2>/dev/null | grep -q yes || break
    sleep 1
  done
  sleep 2
}
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

settle
echo "== 1. fullscreen window reaches the screen directly (no overlay above)"
m=$(flip s1-fullscreen 6 0)
case "$m" in *"Independent Flip") ok "present mode: $m";; *) ko "present mode" "$m (an overlay is above the window; check the Zebar pill)";; esac

settle
echo "== 2. the Zebar pill is back after the fullscreen window closes"
sleep 1
p=$($W 'C:\Users\diego\AppData\Local\Temp\perf\pill-state.ps1')
case "$p" in *"visible=True"*) ok "$p";; *) ko "pill state" "$p";; esac

settle
echo "== 3. workspace switch hides a normal window and the taskbar drops back"
out=$($W 'C:\Users\diego\AppData\Local\Temp\perf\ws-hide-test.ps1')
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "2 switched away .*cloaked=[1-9]" && ok "hidden while away" || ko "hidden while away" "not cloaked"
echo "$out" | grep -q "3 back home .*cloaked=0" && ok "shown on return" || ko "shown on return" "still cloaked"
echo "$out" | grep -q "5 present modes after return: Hardware Composed: Independent Flip\|5 present modes after return: Hardware: Independent Flip" && ok "taskbar not above after return" || ko "taskbar after return" "$(echo "$out" | grep '5 present')"

# A game is elevated (anti-cheat) AND in GlazeWM's fullscreen state; only then
# does GlazeWM mark it fullscreen for the taskbar. An elevated FLOATING window
# cannot be raised above the taskbar at all (SetWindowPos is denied).
settle
echo "== 4. same, with an ELEVATED fullscreen window (what a game looks like)"
# wsgame.ps1, not wsfs.ps1: the window must be classified fullscreen by GlazeWM
# ITSELF. Forcing the state with set-fullscreen gives the window a previous
# state, and that hid the bug where the taskbar stayed over the game after
# coming back from another workspace (Aion 2, 2026-09-18).
rm -f "$P/suite-elev.out"; echo "wsgame.ps1" > "$P/suite-elev.elev"
for _ in $(seq 90); do [ -f "$P/suite-elev.out" ] && break; sleep 1; done
out=$(cat "$P/suite-elev.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "2 switched away .*cloaked=[1-9]" && ok "elevated window hidden while away" || ko "elevated window hidden" "not cloaked (reposition_window aborts on access denied?)"
echo "$out" | grep -q "3 back home .*cloaked=0" && ok "elevated window shown on return" || ko "elevated window shown" "still cloaked"
echo "$out" | grep -q "5 present modes after return: Hardware Composed: Independent Flip\|5 present modes after return: Hardware: Independent Flip" && ok "taskbar not above after return (elevated)" || ko "taskbar after return (elevated)" "$(echo "$out" | grep '5 present')"

settle
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
settle
echo "== 6. a window that settles from oversized to exactly the monitor stays fullscreen"
rm -f "$P/fsgame.out"; echo "fsgame.ps1" > "$P/fsgame.elev"
for _ in $(seq 90); do [ -f "$P/fsgame.out" ] && break; sleep 1; done
out=$(cat "$P/fsgame.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "state=fullscreen" && ok "stays fullscreen" || ko "state" "$(echo "$out" | head -1)"

# Age of Empires II DE opens maximized. GlazeWM used to initialize such a window
# as floating, which un-maximizes it and clamps it 10px inside the workspace; the
# game then took 3828x2072 as its fullscreen resolution and kept its title bar
# and the taskbar on screen.
settle
echo "== 7. a window that opens MAXIMIZED stays maximized"
rm -f "$P/fsmax.out"; echo "fsmax.ps1" > "$P/fsmax.elev"
for _ in $(seq 60); do [ -f "$P/fsmax.out" ] && break; sleep 1; done
out=$(cat "$P/fsmax.out")
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "isZoomed=True" && ok "still maximized" || ko "maximized" "$(echo "$out" | head -1)"
echo "$out" | grep -qE "state=(fullscreen|tiling)" && ok "state kept ($(echo "$out" | grep -o 'state=[a-z]*'))" || ko "state" "$(echo "$out" | head -1)"

# Life of a game window: minimize/restore, Alt+drag (un-maximize) and maximize
# again, and another window opening over it. After each step it must be back in
# the fullscreen state and reaching the screen directly.
for mode in startmax gamelike; do
  settle
  echo "== 8-$mode. minimize / windowed / window on top, then back to normal"
  rm -f "$P/cycle-$mode.out"; echo "win-cycle.ps1 $mode" > "$P/cycle-$mode.elev"
  for _ in $(seq 150); do [ -f "$P/cycle-$mode.out" ] && break; sleep 2; done
  out=$(sed $'1s/^\xEF\xBB\xBF//' "$P/cycle-$mode.out" | tr -d '\r')   # BOM + CRLF
  echo "$out" | sed 's/^/    /'
  for step in "1 start" "2 minimize+restore" "3 windowed+max" "5 on top closed"; do
    line=$(echo "$out" | grep "^$step")
    case "$line" in
      *"state=fullscreen"*) ok "$mode/$step: fullscreen again";;
      *) ko "$mode/$step state" "$line";;
    esac
    # Only a window that covers the whole monitor can reach the screen directly.
    # `startmax` stays maximized (the taskbar strip is left uncovered), so the
    # present mode is only asserted for the borderless `gamelike` window.
    if [ "$mode" = gamelike ]; then
      pct=$(echo "$line" | grep -o '[0-9]*% direct' | tr -d '%% direct')
      if [ -n "$pct" ] && [ "$pct" -ge 90 ]; then ok "$mode/$step: $pct% direct to screen"; else ko "$mode/$step present mode" "$line"; fi
    fi
  done
done

# The Zebar pills: hidden over a fullscreen window, and still hidden when the
# focus moves to the other monitor (clicking a window there used to bring the
# pill back over the game); visible again once the game is gone, on BOTH monitors
# (a cloaked window of a hidden workspace must not count as covering a monitor).
settle
echo "== 9. Zebar pills vs a fullscreen window and the other monitor"
out=$($W 'C:\Users\diego\AppData\Local\Temp\perf\pill-crossmon.ps1')
echo "$out" | sed 's/^/    /'
# The game runs on the primary monitor, whose pill sits at x=6.
echo "$out" | grep "^with the game focused" | grep -q "mon@6,0=hidden" && ok "hidden over the game" || ko "pill over the game" "$(echo "$out" | grep '^with')"
echo "$out" | grep "^focus on other monitor" | grep -q "mon@6,0=hidden" && ok "stays hidden with focus elsewhere" || ko "pill after focusing the other monitor" "$(echo "$out" | grep '^focus')"
[ "$(echo "$out" | grep "^after the game closes" | grep -o hidden | wc -l)" = "0" ] && ok "both pills back" || ko "pills after the game closes" "$(echo "$out" | grep '^after')"

# Launching an app while a fullscreen game has the foreground (Hyper+L): the new
# window stays on the same workspace, behind the game, and is still there after
# leaving the workspace and coming back, and once the game is minimized.
settle
echo "== 10. an app launched behind a fullscreen game stays reachable"
rm -f "$P/behind.out"; echo "behind-game.ps1" > "$P/behind.elev"
for _ in $(seq 120); do [ -f "$P/behind.out" ] && break; sleep 2; done
out=$(sed $'1s/^\xEF\xBB\xBF//' "$P/behind.out" | tr -d '\r')   # BOM + CRLF
echo "$out" | sed 's/^/    /'
ws=$(echo "$out" | grep "^game on workspace" | awk '{print $4}')
echo "$out" | grep "^1 app launched" | grep -q "app\[ws=${ws}/" && ok "opens on the game's workspace" || ko "app workspace" "$(echo "$out" | grep '^1 app')"
echo "$out" | grep "^2 other workspace" | grep -q "app\[ws=${ws}/floating/hidden cloaked=2" && ok "hidden with the workspace" || ko "app while away" "$(echo "$out" | grep '^2 other')"
echo "$out" | grep "^3 back home" | grep -q "cloaked=0 visible=True" && ok "back with the workspace" || ko "app on return" "$(echo "$out" | grep '^3 back')"
echo "$out" | grep "^4 game minimized" | grep -q "app\[ws=${ws}/floating/shown cloaked=0 visible=True" && ok "usable once the game is minimized" || ko "app with the game minimized" "$(echo "$out" | grep '^4 game')"

# A window parked on a hidden workspace must be reachable again: Hyper+<letter>
# asks GlazeWM to focus it (a cloaked window cannot be activated by Windows).
settle
echo "== 11. reaching a window parked on a hidden workspace"
rm -f "$P/reach.out"; echo "reach-hidden.ps1" > "$P/reach.elev"
for _ in $(seq 90); do [ -f "$P/reach.out" ] && break; sleep 1; done
out=$(sed $'1s/^\xEF\xBB\xBF//' "$P/reach.out" | tr -d '\r')
echo "$out" | sed 's/^/    /'
home=$(echo "$out" | grep "^window on" | awk '{print $3}' | tr -d ,)
echo "$out" | grep "^hidden:" | grep -q "cloaked=2" && ok "cloaked while away" || ko "cloak" "$(echo "$out" | grep '^hidden')"
echo "$out" | grep "^after glaze focus" | grep -q "displayed=$home.*cloaked=0" && ok "GlazeWM brings you to it" || ko "focus by id" "$(echo "$out" | grep '^after glaze')"

# The helpers behind Hyper+<letter>: a window you cannot see must never be
# minimised (that sent Telegram to the tray, where its window is unrecoverable).
settle
echo "== 12. window-state helpers (AutoHotkey)"
rm -f "$P/window-state-test.txt"
powershell.exe -NoProfile -Command 'Start-Process "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" -ArgumentList "C:\Users\diego\.dotfiles\templates\windows\DESK_W11\tests\fullscreen\window-state-test.ahk"' >/dev/null 2>&1
for _ in $(seq 40); do [ -f "$P/window-state-test.txt" ] && break; sleep 1; done
out=$(tr -d '\r' < "$P/window-state-test.txt" 2>/dev/null)
echo "$out" | sed 's/^/    /'
echo "$out" | grep -q "^all passed" && ok "helpers behave" || ko "window-state helpers" "$(echo "$out" | grep FAIL | head -1)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
