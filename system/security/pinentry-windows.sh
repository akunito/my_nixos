#!/usr/bin/env bash
# A pinentry for NixOS-WSL whose window is a native Windows box
# (windows-password-box.ps1 through interop). gpg-agent talks Assuan on
# stdin/stdout; this answers it and opens the box for GETPIN / CONFIRM /
# MESSAGE.
#
# Why: pinentry-qt through WSLg is an empty surface from the second Linux
# window of a boot on DESK_W11 (see windows-password-box.ps1), and the ssh
# passphrase is asked by gpg-agent, a user service with no terminal at all.
#
# Environment (set by the nix wrapper; overridable for the tests):
#   PB_POWERSHELL  powershell.exe            PB_SCRIPT   the .ps1 (Linux path)
#   PB_FALLBACK    pinentry to exec when interop is down
#   PB_SELFTEST    test only: the text the box "types" by itself
set -u
ps="${PB_POWERSHELL:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"
script="${PB_SCRIPT:?PB_SCRIPT is not set}"

# gpg-agent is a systemd user service: it has no WSL_INTEROP, and without it
# /init cannot reach the Windows side ("UtilConnectUnix" errors). Any live
# interop socket of this distro works.
if [ -z "${WSL_INTEROP:-}" ]; then
    for s in /run/WSL/*_interop; do [ -S "$s" ] && WSL_INTEROP="$s"; done
    export WSL_INTEROP
fi
if [ ! -e /proc/sys/fs/binfmt_misc/WSLInterop ] || [ ! -x "$ps" ] || [ -z "${WSL_INTEROP:-}" ]; then
    [ -n "${PB_FALLBACK:-}" ] && exec "$PB_FALLBACK" "$@"
    echo "ERR 83886254 no interop and no fallback pinentry <Pinentry>"; exit 1
fi

unc() { printf '\\\\wsl.localhost\\%s%s' "${WSL_DISTRO_NAME:-NixOS}" "$(printf '%s' "$1" | tr '/' '\\')"; }
# Assuan percent-decoding of what gpg sends (%0A, %22, %25 ...).
unescape() { local s="${1//\\/\\\\}"; printf '%b' "${s//%/\\x}"; }
# JSON string escaping for the parameter file.
json() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}
title="pinentry"; desc=""; prompt="Passphrase:"; error=""; ok="OK"; cancel="Cancel"; repeat=false

box() { # box <confirm:true|false>  -> prints the password; returns the box's exit code
    local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" f rc
    f="$(mktemp "$dir/akupb.XXXXXX.json")" || return 2
    {
        printf '{"title":%s,"description":%s,"prompt":%s,"error":%s,"ok":%s,"cancel":%s,"confirm":%s,"repeat":%s}' \
            "$(json "$title")" "$(json "$desc")" "$(json "$prompt")" "$(json "$error")" \
            "$(json "$ok")" "$(json "$cancel")" "$1" "$repeat"
    } > "$f"
    # stdin from /dev/null: powershell.exe inherits the Assuan pipe otherwise
    # and eats the commands that follow GETPIN (the BYE never arrived).
    if [ -n "${PB_SELFTEST:-}" ]; then
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(unc "$script")" -ParamFile "$(unc "$f")" -SelfTest "$PB_SELFTEST" 2>/dev/null < /dev/null
    else
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(unc "$script")" -ParamFile "$(unc "$f")" 2>/dev/null < /dev/null
    fi
    rc=$?
    rm -f "$f"
    return $rc
}

echo "OK Pleased to meet you"
while IFS= read -r line; do
    line="${line%$'\r'}"
    cmd="${line%% *}"; arg=""
    [ "$cmd" != "$line" ] && arg="${line#* }"
    case "${cmd^^}" in
        SETTITLE)  title="$(unescape "$arg")"; echo OK ;;
        SETDESC)   desc="$(unescape "$arg")"; echo OK ;;
        SETPROMPT) prompt="$(unescape "$arg")"; echo OK ;;
        SETERROR)  error="$(unescape "$arg")"; echo OK ;;
        SETOK)     ok="$(unescape "$arg")"; ok="${ok//_/}"; echo OK ;;
        SETCANCEL|SETNOTOK) cancel="$(unescape "$arg")"; cancel="${cancel//_/}"; echo OK ;;
        SETREPEAT) repeat=true; echo OK ;;
        GETPIN)
            if pin="$(box false)"; then
                [ "$repeat" = true ] && echo "S PIN_REPEATED"
                # Percent-escape what Assuan cannot carry in a data line.
                pin="${pin//%/%25}"; pin="${pin//$'\r'/%0D}"; pin="${pin//$'\n'/%0A}"
                [ -n "$pin" ] && echo "D $pin"
                echo OK
            else
                echo "ERR 83886179 Operation cancelled <Pinentry>"
            fi
            error=""; repeat=false ;;
        CONFIRM)
            if box true >/dev/null; then echo OK; else echo "ERR 83886179 Operation cancelled <Pinentry>"; fi
            error="" ;;
        MESSAGE)
            box true >/dev/null; echo OK ;;
        GETINFO)
            case "$arg" in
                pid)     echo "D $$"; echo OK ;;
                version) echo "D 1.3.1"; echo OK ;;
                flavor)  echo "D windows"; echo OK ;;
                ttyinfo) echo "D - - -"; echo OK ;;
                *)       echo "ERR 83886355 Unknown IPC inquire <Pinentry>" ;;
            esac ;;
        BYE) echo "OK closing connection"; exit 0 ;;
        # OPTION, SETKEYINFO, SETQUALITYBAR, SETTIMEOUT, SETGENPIN, RESET, NOP ...
        *) echo OK ;;
    esac
done
