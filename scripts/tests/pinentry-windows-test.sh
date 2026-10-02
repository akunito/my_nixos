#!/usr/bin/env bash
# The native Windows pinentry, driven over Assuan the way gpg-agent drives it,
# with the box filling itself in (PB_SELFTEST). Run on DESK_W11 inside WSL:
#   scripts/tests/pinentry-windows-test.sh
# Needs interop (powershell.exe). Each box flashes on screen for under a second.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pin="$here/system/security/pinentry-windows.sh"
export PB_SCRIPT="$here/system/security/windows-password-box.ps1"
pass=0; fail=0
check() { # check <name> <got> <want>
    if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  PASS $1"; else fail=$((fail+1)); echo "  FAIL $1"; echo "       got:  $(printf '%q' "$2")"; echo "       want: $(printf '%q' "$3")"; fi
}
run() { PB_SELFTEST="$1" bash "$pin" <<< "$2" | tr -d '\r'; }

out="$(run 'correct horse' $'SETTITLE gpg\nSETDESC Please enter the passphrase%0Afor the ssh key %22x%22\nSETPROMPT Passphrase:\nGETPIN\nBYE')"
check "greeting first" "$(sed -n 1p <<< "$out")" "OK Pleased to meet you"
check "GETPIN answers with the passphrase as a data line" "$(grep '^D ' <<< "$out")" "D correct horse"
check "and closes on BYE" "$(tail -1 <<< "$out")" "OK closing connection"

out="$(run 'pä%ss €' $'GETPIN\nBYE')"
check "a percent sign is escaped, UTF-8 passes" "$(grep '^D ' <<< "$out")" "D pä%25ss €"

out="$(run 'twice' $'SETREPEAT\nGETPIN\nBYE')"
check "a repeated passphrase says so" "$(grep -c '^S PIN_REPEATED' <<< "$out")" "1"
check "and comes back" "$(grep '^D ' <<< "$out")" "D twice"

out="$(run 'x' $'SETDESC Allow this?\nCONFIRM\nBYE')"
check "CONFIRM is OK and sends no data" "$(grep -c '^D ' <<< "$out")/$(sed -n 3p <<< "$out")" "0/OK"

out="$(run 'x' $'OPTION ttyname=/dev/pts/1\nSETKEYINFO n/ABC\nGETINFO flavor\nGETINFO pid\nBYE' | sed 's/^D [0-9]*$/D <pid>/')"
check "options and key info are accepted, GETINFO answers" "$(tr '\n' '|' <<< "$out")" "OK Pleased to meet you|OK|OK|D windows|OK|D <pid>|OK|OK closing connection|"

out="$(PB_POWERSHELL=/nonexistent/powershell.exe PB_FALLBACK="$(command -v echo)" PB_SELFTEST=x bash "$pin" fell-back < /dev/null)"
check "without interop it execs the fallback pinentry" "$out" "fell-back"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
