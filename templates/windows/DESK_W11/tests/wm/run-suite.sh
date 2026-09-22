#!/usr/bin/env bash
# Window-manager behaviour suite for DESK_W11: Hyper+<letter> (app-toggle
# parity), sticky windows and tiling. Needs %TEMP%\perf populated by
# tests/fullscreen (fliptest.exe, cloaktest.exe -- see that README).
#
# Runs the AHK cases against THIS checkout: the libraries are copied to
# %TEMP%\wmtest\ keeping the layout the #Include paths expect, so nothing has
# to be committed or pulled into the Windows clone first.
#
# Takes the pointer and two empty workspaces of the primary monitor for a
# couple of minutes: do not touch mouse or keyboard while it runs.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"                      # templates/windows/DESK_W11
WT=/mnt/c/Users/diego/AppData/Local/Temp/wmtest
P=/mnt/c/Users/diego/AppData/Local/Temp/perf
AHK='C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
# The window manager's CLI, seen from WSL. reset_desk needs it and had no
# definition at all: with `set -u` that aborted the function on its first line,
# silently, so the reset this suite relies on between cases never ran (added
# 2026-09-21 and broken the same day). Read the same way tests/fullscreen does,
# BOM and all.
G="/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe"
marker=/mnt/c/Users/diego/AppData/Local/akuwm/wm-cli.txt
if [ -f "$marker" ]; then
  wmcli=$(sed '1s/^\xEF\xBB\xBF//' "$marker" | tr -d '\r\n' |
          sed 's|\\|/|g; s|^C:|/mnt/c|; s|^c:|/mnt/c|')
  [ -n "$wmcli" ] && [ -x "$wmcli" ] && G="$wmcli"
fi
pass=0; fail=0
ok() { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
ko() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

# The user's own sticky windows (Telegram, the terminals) follow every
# workspace of their monitor and would sit in the middle of the cases that
# measure the screen: park them, except for the suite that checks the rules
# themselves -- that one needs them exactly as the config left them.
sticky() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
  'C:\Users\diego\AppData\Local\Temp\perf\sticky-park.ps1' "$1" 2>/dev/null | tr -d '\r' | sed 's/^/  /'; }
trap 'sticky on >/dev/null 2>&1' EXIT

mkdir -p "$WT/tests/wm"
cp "$SRC"/lib-*.ahk "$WT/"
cp "$HERE"/*.ahk "$WT/tests/wm/"

run_ahk() { # run_ahk <script.ahk> <result-file> <timeout-s>
  local script=$1 result=$2 timeout=$3
  # Syntax first: a bad script opens an error dialog and would otherwise sit
  # there until the timeout, with no output at all.
  if ! powershell.exe -NoProfile -Command \
      "& '$AHK' /validate 'C:\\Users\\diego\\AppData\\Local\\Temp\\wmtest\\tests\\wm\\$script'; exit \$LASTEXITCODE" >/dev/null 2>&1; then
    echo "    (syntax error in $script -- run AutoHotkey64.exe /validate on it)"
    return 1
  fi
  rm -f "$P/$result"
  # Waited for, not fired and forgotten. Launched from WSL the parent
  # powershell.exe is in an interop job: when it exits, the AutoHotkey it
  # started goes with it, and the case dies silently a moment after it begins
  # (measured 2026-09-21 -- every suite reported "no result after Ns").
  powershell.exe -NoProfile -Command \
    "\$p = Start-Process '$AHK' -ArgumentList 'C:\\Users\\diego\\AppData\\Local\\Temp\\wmtest\\tests\\wm\\$script' -PassThru; \
     if (-not \$p.WaitForExit($(( (timeout + 10) * 1000 )))) { \$p.Kill() }" >/dev/null 2>&1
  for _ in $(seq 5); do [ -f "$P/$result" ] && break; sleep 1; done
  [ -f "$P/$result" ] || { echo "    (no result after ${timeout}s)"; return 1; }
  tr -d '\r' < "$P/$result"
}

collect() { # collect <script> <result> <timeout> <title>
  echo "== $4"
  local out
  out=$(run_ahk "$1" "$2" "$3")
  echo "$out" | sed 's/^/    /'
  while IFS= read -r line; do
    case "$line" in
      PASS*) ok "${line#PASS }";;
      FAIL*) ko "${line#FAIL }";;
    esac
  done <<< "$out"
  echo
}

case "${1:-all}" in
  all)       suites="toggle wskeys sticky stacking tiling tiledrag rules repair display";;
  *)         suites="$*";;
esac

# Each suite starts from the same desk. Without this a suite inherits whatever
# workspace the last one finished on, its `home` is computed from a stale
# answer, and every workspace assertion is off by one -- which is what happened
# running them back to back on 2026-09-21, and it made two suites look like
# regressions they were not.
# Back to the EMPTY workspaces this suite works in, never to 11/21 -- those are
# the ones the person actually uses. Sending the desk there put the cases'
# windows in among his, so the tiling checks measured a layout shared with
# Zen and NordVPN and read "they fill the monitor" as false five times
# (2026-09-21). The function did nothing at all before that, which hid it.
# AkuWM's own CLI (the pipe), for what the GlazeWM-shaped shim cannot say.
A=""
for c in /mnt/c/Users/diego/AppData/Local/Programs/AkuWM/akuwm.exe /mnt/c/Users/diego/AppData/Local/Temp/akuwm-m2/akuwm-cli.exe; do
  [ -x "$c" ] && { A="$c"; break; }
done

reset_desk() {
  # AkuWM remembers how the last window of an application was closed and
  # opens the next one the same way (plan 10.26). A case that floats fliptest
  # and closes it would hand the next case a floating fliptest: the memory of
  # the windows the suite drives is cleared before every case, so each one
  # meets them as sway would, as strangers.
  if [ -n "$A" ]; then
    for app in fliptest notepad charmap calc; do
      "$A" forget-app "$app" >/dev/null 2>&1
    done
  fi
  for ws in 12 22; do
    powershell.exe -NoProfile -Command \
      "\$p = Start-Process '$(printf %s "$G" | sed 's|^/mnt/c|C:|; s|/|\\|g')' \
        -ArgumentList 'command','focus','--workspace','$ws' -PassThru -WindowStyle Hidden; \
       [void]\$p.WaitForExit(8000)" >/dev/null 2>&1
    sleep 1
  done
}

for s in $suites; do
  reset_desk
  case "$s" in
    rules) sticky on;;
    *)     sticky off;;
  esac
  case "$s" in
    toggle) collect apptoggle-test.ahk apptoggle-test.txt 180 "Hyper+<letter>: Sway's app-toggle decision table";;
    wskeys) collect wskeys-test.ahk    wskeys-test.txt    150 "Workspace keys act on the monitor under the pointer";;
    sticky) collect sticky-test.ahk    sticky-test.txt    180 "Sticky windows: shown on every workspace of their monitor";;
    stacking) collect stacking-test.ahk stacking-test.txt 200 "Floating windows stay above the tiled ones (sway's layers)";;
    tiling) collect tiling-test.ahk    tiling-test.txt    240 "Tiling: sway's layout, gaps and keymap";;
    tiledrag) collect tiledrag-test.ahk tiledrag-test.txt 150 "Alt+drag keeps a tiled window tiled";;
    repair) collect repair-test.ahk    repair-test.txt    240 "The layout journal and the repair after a monitor nap";;
    display)
      # The fork fix for the workspaces mixed between monitors, against a real
      # display-settings change. Switches the SECOND monitor to another
      # resolution for eight seconds and puts it back; the main one is left
      # alone. Re-applying the same mode does not work: Windows broadcasts
      # nothing at all when the mode does not change.
      echo "== Workspaces go back to their monitor on a display change (fork)"
      cp display-change-test.ps1 "$P/" 2>/dev/null
      out=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
        'C:\Users\diego\AppData\Local\Temp\perf\display-change-test.ps1' 2>/dev/null |
        tr -d '\r' | grep -vE '^\s*\+|CategoryInfo|FullyQualified|^\s*$')
      echo "$out" | sed 's/^/    /'
      if echo "$out" | grep -q "^RESULT ok"; then ok "a misplaced workspace is reclaimed by its monitor"
      elif echo "$out" | grep -q "no other mode available"; then echo "    (skipped: the second monitor has a single mode)"
      else ko "misplaced workspace after a display change"; fi
      echo
      ;;
    rules)  collect rules-test.ahk     rules-test.txt     120 "Window rules ported from sway";;
    *)      echo "unknown suite: $s" >&2; exit 2;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
