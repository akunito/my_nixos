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
pass=0; fail=0
ok() { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
ko() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

mkdir -p "$WT/tests/wm"
cp "$SRC"/lib-*.ahk "$WT/"
cp "$HERE"/*.ahk "$WT/tests/wm/"

run_ahk() { # run_ahk <script.ahk> <result-file> <timeout-s>
  local script=$1 result=$2 timeout=$3
  rm -f "$P/$result"
  powershell.exe -NoProfile -Command \
    "Start-Process '$AHK' -ArgumentList 'C:\\Users\\diego\\AppData\\Local\\Temp\\wmtest\\tests\\wm\\$script'" >/dev/null 2>&1
  for _ in $(seq "$timeout"); do [ -f "$P/$result" ] && break; sleep 1; done
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
  all)       suites="toggle sticky tiling rules";;
  *)         suites="$*";;
esac

for s in $suites; do
  case "$s" in
    toggle) collect apptoggle-test.ahk apptoggle-test.txt 180 "Hyper+<letter>: Sway's app-toggle decision table";;
    sticky) collect sticky-test.ahk    sticky-test.txt    180 "Sticky windows: shown on every workspace of their monitor";;
    tiling) collect tiling-test.ahk    tiling-test.txt    240 "Tiling: sway's layout, gaps and keymap";;
    rules)  collect rules-test.ahk     rules-test.txt     120 "Window rules ported from sway";;
    *)      echo "unknown suite: $s" >&2; exit 2;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
