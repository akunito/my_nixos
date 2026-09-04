#!/usr/bin/env bash
# Gamescope wrapper that ensures all child processes (Wine, Proton, wineserver,
# winedevice, gamescopereaper) are cleaned up when the game exits, and can
# optionally drop the Sway output to scale 1 for titles that must run under
# Xwayland (see the long comment below).
#
# Usage in Steam launch options:
#   ~/.config/sway/scripts/gamescope-wrapper.sh [gamescope args] -- %command%
#
# Do NOT prefix this with `env -u WAYLAND_DISPLAY`. Unsetting WAYLAND_DISPLAY
# pushes gamescope onto its SDL/X11 backend, which puts gamescope itself inside
# Xwayland — so the frame gets squeezed into Xwayland's logical size and then
# stretched back out by Sway, i.e. two resamples instead of none. Leave
# WAYLAND_DISPLAY alone so gamescope uses its native Wayland backend.
#
# ---------------------------------------------------------------------------
# Why the scale knob exists (and why it is OFF by default)
#
# wlroots (and therefore Sway) has never implemented Xwayland output scaling.
# Xwayland always runs at scale 1, in LOGICAL pixels. On a 3840x2160 output at
# `scale 1.4` the logical size is 2742x1542 — and that is the screen size any
# Proton/Wine game sees when it runs directly under Xwayland. The game renders
# at 2742x1542 and Sway upscales that buffer by 1.4 to fill the panel. That
# upscale is the blur. KWin does not have this problem because it implements
# per-output Xwayland scaling.
#
# BUT: gamescope on its native Wayland backend does NOT suffer from this.
# Verified at the protocol level with WAYLAND_DEBUG=1 on 2026-09-04, DP-1 at
# scale 1.4:
#
#   wp_fractional_scale_v1.preferred_scale(168)        168/120 = 1.4
#   linux_buffer_params.create_immed(..., 3840, 2160)  native-resolution buffer
#   wp_viewport.set_destination(2742, 1542)            mapped to the logical area
#
# A 3840x2160 buffer presented into a 2742x1542 logical destination on a x1.4
# output is a 1:1 pixel mapping — nothing is resampled, and the rest of the
# desktop keeps its scale. So on the default path there is nothing to fix.
#
# The one thing that breaks this is `env -u WAYLAND_DISPLAY` in the Steam launch
# options: it forces gamescope onto its SDL/X11 backend, which puts gamescope
# itself inside Xwayland and reintroduces the blur it was avoiding. Do not use
# it.
#
# The scale flip below is therefore only for the case where the game does NOT go
# through gamescope's Wayland backend (GAMESCOPE_DISABLE=1, or a title that has
# to run under Xwayland). It is opt-in because it affects the WHOLE output, not
# just the game window — every workspace on that monitor goes unscaled for the
# duration.
#
# Env knobs:
#   GAMESCOPE_FORCE_SCALE1=1     drop the output to scale 1 for this session
#   GAMESCOPE_SCALE_OUTPUT=DP-1  target a specific output (default: focused one)
#   GAMESCOPE_DISABLE=1          skip gamescope, run %command% directly
#   GAMESCOPE_NO_DRAIN=1         kill the group as soon as gamescope exits
#   GAMESCOPE_NO_TRACE=1         do not record the GPU/memory trace
#   (LD_PRELOAD is always stripped from gamescope and handed to the game;
#    see the lag-bomb note further down.)
#   GAMESCOPE_WLDEBUG=1          run gamescope under WAYLAND_DEBUG=1 and save the
#                                protocol log, to catch the Wayland error that
#                                makes CWaylandInputThread::ThreadFunc abort()
# ---------------------------------------------------------------------------

set -euo pipefail

log() { echo "[gamescope-wrapper] $*" >&2; }

# --- locate swaymsg and the IPC socket ------------------------------------
# Steam's runtime rewrites PATH, so do not assume swaymsg is on it.
SWAYMSG=""
for candidate in \
    swaymsg \
    /run/current-system/sw/bin/swaymsg \
    "${HOME}/.nix-profile/bin/swaymsg"; do
    if resolved=$(command -v "$candidate" 2>/dev/null); then
        SWAYMSG="$resolved"
        break
    fi
done

if [[ -z "${SWAYSOCK:-}" || ! -S "${SWAYSOCK:-}" ]]; then
    # Newest socket wins: a stale one from a previous session may still exist.
    SWAYSOCK=$(ls -1t /run/user/"$(id -u)"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)
    export SWAYSOCK
fi

# --- work out which output to un-scale ------------------------------------
SCALE_OUTPUT=""
ORIG_SCALE=""

if [[ "${GAMESCOPE_FORCE_SCALE1:-0}" == "1" && -n "$SWAYMSG" && -S "${SWAYSOCK:-}" ]]; then
    # `swaymsg -p` is parsed instead of the JSON because jq is not reliably on
    # PATH inside Steam's runtime. Blocks look like:
    #   Output DP-1 'Samsung ... H1AK500000' (focused)
    #     Current mode: 3840x2160 @ 120.000 Hz
    #     Scale factor: 1.400000
    read -r SCALE_OUTPUT ORIG_SCALE < <(
        "$SWAYMSG" -p -t get_outputs 2>/dev/null | awk -v want="${GAMESCOPE_SCALE_OUTPUT:-}" '
            /^Output /      { name = $2; focused = ($0 ~ /\(focused\)/) }
            /Scale factor:/ {
                if (want == "" ? focused : name == want) { print name, $3; exit }
            }
        '
    ) || true
fi

restore_scale() {
    [[ -n "$SCALE_OUTPUT" && -n "$ORIG_SCALE" ]] || return 0
    log "restoring $SCALE_OUTPUT to scale $ORIG_SCALE"
    "$SWAYMSG" output "$SCALE_OUTPUT" scale "$ORIG_SCALE" >/dev/null 2>&1 || true
}

# --- process-group drain ---------------------------------------------------
# Some launchers (Black Desert's BlackDesertLauncher.exe is the reference case)
# exec the real client and then quit. gamescope is left with no windows and
# shuts down while the game is only just starting. The naive reading of that —
# "gamescope exited, so the session is over" — made this wrapper SIGKILL the
# whole process group about a second after the real game appeared, which looked
# exactly like "the game does not start". Observed 2026-09-04: gamescope died at
# 07:14:13, the game's processes were added at 07:14:13/14, and all 28 were
# removed at 07:14:15 — the one-second gap being the `sleep 1` in cleanup().
#
# So after gamescope exits we do not kill anything until the only things left in
# the group are the Wine helpers that always linger.
LINGERERS='wineserver|winedevice.exe|services.exe|explorer.exe|plugplay.exe|svchost.exe|rpcss.exe|tabtip.exe|conhost.exe|start.exe|winemenubuilder|gamescopereaper'

group_has_live_game() {
    local pgid="$1" pid comm
    for pid in $(pgrep -g "$pgid" 2>/dev/null || true); do
        [[ "$pid" == "$$" ]] && continue
        comm=$(cat /proc/"$pid"/comm 2>/dev/null || true)
        [[ -z "$comm" ]] && continue
        [[ "$comm" =~ ^($LINGERERS)$ ]] && continue
        return 0
    done
    return 1
}

drain_group() {
    local pgid="${1:-}"
    [[ -n "$pgid" && "${GAMESCOPE_NO_DRAIN:-0}" != "1" ]] || return 0
    group_has_live_game "$pgid" || return 0
    log "gamescope exited but the game is still running — waiting for it"
    while group_has_live_game "$pgid"; do
        sleep 2
    done
    log "game finished, cleaning up"
}

# --- session trace ---------------------------------------------------------
# Progressive stutter (fine for 30 minutes, unplayable after) cannot be
# diagnosed after the fact, so every session records GPU/memory samples to a
# CSV. Costs one sample every 2s (~350 KB/hour) and keeps only the last 10
# sessions. Disable with GAMESCOPE_NO_TRACE=1.
TRACE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gamescope-traces"
TRACE_PID=""
TRACE_FILE=""

start_trace() {
    [[ "${GAMESCOPE_NO_TRACE:-0}" != "1" ]] || return 0
    local tracer="$HOME/.config/sway/scripts/gpu-session-trace.sh"
    [[ -x "$tracer" ]] || return 0
    mkdir -p "$TRACE_DIR" 2>/dev/null || return 0
    TRACE_FILE="$TRACE_DIR/$(date +%Y%m%d-%H%M%S).csv"
    "$tracer" "$TRACE_FILE" 2 >/dev/null 2>&1 &
    TRACE_PID=$!
    log "tracing GPU/memory to $TRACE_FILE"
    # Keep the directory bounded; oldest first. Guarded because an empty
    # directory makes `ls` exit non-zero, and under `set -o pipefail` that would
    # abort the whole wrapper before the game is ever launched.
    local stale
    stale=$(ls -1t "$TRACE_DIR"/*.csv 2>/dev/null | tail -n +11 || true)
    if [[ -n "$stale" ]]; then
        while read -r old; do
            [[ -n "$old" ]] && rm -f "$old" 2>/dev/null || true
        done <<< "$stale"
    fi
    return 0
}

stop_trace() {
    [[ -n "$TRACE_PID" ]] || return 0
    kill "$TRACE_PID" 2>/dev/null || true
    TRACE_PID=""
    [[ -n "$TRACE_FILE" ]] && log "trace written: $TRACE_FILE"
}

# Set when the wrapper is torn down by a signal (Steam's Stop button, a session
# logout) as opposed to gamescope exiting by itself. Only the former justifies
# killing anything.
KILLED_BY_SIGNAL=0

# What is still alive in gamescope's process group, as "pid:comm" — recorded at
# teardown so a failed session says who was there instead of leaving us guessing.
group_snapshot() {
    local pgid="${1:-}" pid comm out=""
    [[ -n "$pgid" ]] || { echo "(no pgid)"; return 0; }
    for pid in $(pgrep -g "$pgid" 2>/dev/null || true); do
        [[ "$pid" == "$$" ]] && continue
        comm=$(cat /proc/"$pid"/comm 2>/dev/null || true)
        out+="${pid}:${comm:-?} "
    done
    echo "${out:-(empty)}"
}

cleanup() {
    stop_trace

    local pgid="${GAMESCOPE_PGID:-}"
    log "teardown: signal=${KILLED_BY_SIGNAL} gamescope_rc=${GAMESCOPE_RC:-?} group=[$(group_snapshot "$pgid")]"

    # Only reap the process group when WE are being killed. When gamescope exits
    # on its own the game may still be starting up — Black Desert's launcher
    # execs the real client and quits, and Proton puts that client in its own
    # session anyway, so a group kill here is both useless against the game and
    # dangerous to whatever is left. Steam and gamescope's own reaper clean up
    # the Wine side; leaving a stray wineserver is far cheaper than killing a
    # live game.
    if [[ -n "$pgid" && "$KILLED_BY_SIGNAL" == "1" ]]; then
        log "signalled — reaping process group $pgid"
        kill -TERM -"$pgid" 2>/dev/null || true
        sleep 1
        kill -9 -"$pgid" 2>/dev/null || true
    fi

    # Clean up stale gamescope lock files
    rm -f /run/user/"$(id -u)"/gamescope-*.lock 2>/dev/null || true

    restore_scale
}

on_signal() {
    KILLED_BY_SIGNAL=1
    exit 143
}

trap cleanup EXIT
trap on_signal INT TERM HUP

if [[ -n "$SCALE_OUTPUT" && -n "$ORIG_SCALE" ]]; then
    if [[ "$ORIG_SCALE" == "1" || "$ORIG_SCALE" == "1.000000" ]]; then
        log "$SCALE_OUTPUT already at scale 1, nothing to do"
        SCALE_OUTPUT=""   # disarm the restore
        ORIG_SCALE=""
    else
        log "dropping $SCALE_OUTPUT from scale $ORIG_SCALE to 1 for this session"
        if "$SWAYMSG" output "$SCALE_OUTPUT" scale 1 >/dev/null 2>&1; then
            # Let Sway reflow and Xwayland resize its root window before the
            # game queries the screen size, or it can latch the old geometry.
            sleep 0.5
        else
            log "WARNING: could not set scale, leaving it alone"
            SCALE_OUTPUT=""
            ORIG_SCALE=""
        fi
    fi
else
    log "leaving output scale alone (GAMESCOPE_FORCE_SCALE1=${GAMESCOPE_FORCE_SCALE1:-0})"
fi

# --- launch ----------------------------------------------------------------
start_trace

# Split our own argv at the first `--`: gamescope's flags before it, the game
# command after it.
GS_ARGS=()
GAME_CMD=()
seen_sep=0
for arg in "$@"; do
    if [[ $seen_sep -eq 1 ]]; then
        GAME_CMD+=("$arg")
    elif [[ "$arg" == "--" ]]; then
        seen_sep=1
    else
        GS_ARGS+=("$arg")
    fi
done

# ---------------------------------------------------------------------------
# The "gamescope lag bomb"
#
# Steam exports LD_PRELOAD for the whole launch command, so the Steam overlay
# (gameoverlayrenderer.so) is preloaded into GAMESCOPE ITSELF, not just into the
# game. Roughly 24 minutes in, that makes gamescope's frame pacing collapse: the
# GPU starts flipping between idle and full clocks and the game becomes
# unplayable. It is documented upstream and matched this machine exactly —
# measured 2026-09-04 on Crimson Desert, lag at minute 24-26 with the GPU
# oscillating between 100%/338W and 72%/163W while nothing was saturated (IO
# pressure 0.00, CPU pressure 0.53, 73 of 89 game threads asleep, no amdgpu
# events, VRAM 12.9 of 16.3 GiB with GTT flat).
#
# The fix is to run gamescope without LD_PRELOAD and hand it back to the game, so
# the overlay, game recording and the rest of Steam's features keep working.
# Blanking LD_PRELOAD outright also stops the stutter but loses all of that.
STEAM_PRELOAD="${LD_PRELOAD:-}"
if [[ -n "$STEAM_PRELOAD" ]]; then
    unset LD_PRELOAD
    log "stripped LD_PRELOAD from gamescope (lag bomb); re-injecting it for the game"
fi

# Rebuild the game command with LD_PRELOAD restored in front of it.
run_game=("${GAME_CMD[@]}")
if [[ -n "$STEAM_PRELOAD" && ${#GAME_CMD[@]} -gt 0 ]]; then
    run_game=(env "LD_PRELOAD=$STEAM_PRELOAD" "${GAME_CMD[@]}")
fi

if [[ "${GAMESCOPE_DISABLE:-0}" == "1" ]]; then
    if [[ ${#GAME_CMD[@]} -eq 0 ]]; then
        log "GAMESCOPE_DISABLE=1 but no '--' in args; running gamescope after all"
    else
        log "GAMESCOPE_DISABLE=1, running without gamescope: ${GAME_CMD[*]}"
        setsid "${run_game[@]}" &
        GAMESCOPE_PID=$!
        GAMESCOPE_PGID=$GAMESCOPE_PID
        GAMESCOPE_RC=0
        wait "$GAMESCOPE_PID" 2>/dev/null || GAMESCOPE_RC=$?
        drain_group "$GAMESCOPE_PGID"
        exit 0
    fi
fi

# Launch gamescope in a new session/process group.
#
# GAMESCOPE_WLDEBUG captures the Wayland protocol conversation. gamescope 3.16.17
# aborts (SIGABRT, rc=134) inside CWaylandInputThread::ThreadFunc when its
# display connection errors, which is what killed every Black Desert launch on
# 2026-09-04 about 10s in. The abort itself says nothing; the protocol tail says
# which request sway rejected. The log is large (~35k lines per 10s), so it is
# written to a file rather than Steam's console log, and only on request.
if [[ ${#GAME_CMD[@]} -gt 0 ]]; then
    GS_INVOKE=("${GS_ARGS[@]}" -- "${run_game[@]}")
else
    GS_INVOKE=("$@")
fi

if [[ "${GAMESCOPE_WLDEBUG:-0}" == "1" ]]; then
    WLDEBUG_LOG="${TRACE_DIR}/wldebug-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$TRACE_DIR" 2>/dev/null || true
    log "WAYLAND_DEBUG capture -> $WLDEBUG_LOG"
    WAYLAND_DEBUG=1 setsid gamescope "${GS_INVOKE[@]}" >"$WLDEBUG_LOG" 2>&1 &
else
    setsid gamescope "${GS_INVOKE[@]}" &
fi
GAMESCOPE_PID=$!
GAMESCOPE_PGID=$GAMESCOPE_PID

# Wait for gamescope to exit, then for the actual game (see drain_group).
GAMESCOPE_RC=0
wait "$GAMESCOPE_PID" 2>/dev/null || GAMESCOPE_RC=$?
log "gamescope exited rc=$GAMESCOPE_RC after ${SECONDS}s"
drain_group "$GAMESCOPE_PGID"
