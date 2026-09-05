#!/usr/bin/env bash
# Wrapper around gamescope for Steam launch options:
#
#   ~/.config/sway/scripts/gamescope-wrapper.sh [gamescope args] -- %command%
#
# Its one job that matters is defusing the "gamescope lag bomb" (see below).
# Everything else here is opt-in diagnostics.
#
# Do NOT prefix this with `env -u WAYLAND_DISPLAY`. That pushes gamescope onto
# its SDL/X11 backend, which puts gamescope inside Xwayland — and since wlroots
# never implemented Xwayland output scaling, the frame is then rendered at the
# output's *logical* size and stretched back up, which is where the blur comes
# from. Left alone, gamescope uses its Wayland backend and presents a
# native-resolution buffer through a viewport, pixel for pixel, with the rest of
# the desktop keeping its scale.
#
# Env knobs:
#   GAMESCOPE_TRACE=1     record a GPU/memory/process CSV for the session
#   GAMESCOPE_DISABLE=1   skip gamescope, run %command% directly (A/B testing)
#   GAMESCOPE_WLDEBUG=1   run gamescope under WAYLAND_DEBUG=1 into a log file
#                         (keeps the last 64MB; GAMESCOPE_WLDEBUG_MAX_MB overrides)
#
set -euo pipefail

log() { echo "[gamescope-wrapper] $*" >&2; }

TRACE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gamescope-traces"
TRACE_PID=""
TRACE_FILE=""

start_trace() {
    [[ "${GAMESCOPE_TRACE:-0}" == "1" ]] || return 0
    local tracer="$HOME/.config/sway/scripts/gpu-session-trace.sh"
    [[ -x "$tracer" ]] || return 0
    mkdir -p "$TRACE_DIR" 2>/dev/null || return 0
    TRACE_FILE="$TRACE_DIR/$(date +%Y%m%d-%H%M%S).csv"
    "$tracer" "$TRACE_FILE" 2 >/dev/null 2>&1 &
    TRACE_PID=$!
    log "tracing GPU/memory to $TRACE_FILE"
    # An empty directory makes `ls` exit non-zero, and under `set -o pipefail`
    # that would abort the wrapper before the game is ever launched.
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
    return 0
}

# Set when the wrapper is torn down by a signal (Steam's Stop button, a logout)
# rather than by gamescope exiting on its own. Only the former justifies killing
# anything: Proton puts the game in its own session, so a process-group kill on
# a normal exit cannot reach the game anyway and only risks catching something
# that is still starting up. Steam and gamescope's reaper handle the Wine side.
KILLED_BY_SIGNAL=0

cleanup() {
    stop_trace
    log "teardown: signal=${KILLED_BY_SIGNAL} gamescope_rc=${GAMESCOPE_RC:-?}"
    if [[ -n "${GAMESCOPE_PGID:-}" && "$KILLED_BY_SIGNAL" == "1" ]]; then
        log "signalled — reaping process group ${GAMESCOPE_PGID}"
        kill -TERM -"$GAMESCOPE_PGID" 2>/dev/null || true
        sleep 1
        kill -9 -"$GAMESCOPE_PGID" 2>/dev/null || true
    fi
    rm -f /run/user/"$(id -u)"/gamescope-*.lock 2>/dev/null || true
    return 0
}

on_signal() { KILLED_BY_SIGNAL=1; exit 143; }

trap cleanup EXIT
trap on_signal INT TERM HUP

start_trace

# Split argv at the first `--`: gamescope's flags before it, the game after.
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
# The "gamescope lag bomb" — the reason this wrapper exists
#
# Steam exports LD_PRELOAD across the whole launch command, so the Steam overlay
# (gameoverlayrenderer.so) is preloaded into GAMESCOPE ITSELF, not just into the
# game. Around 24 minutes in, that wrecks gamescope's frame pacing: the GPU
# starts flipping between idle and full clocks and the game becomes unplayable.
#
# Measured on DESK 2026-09-04. Two Crimson Desert sessions collapsed at minute
# 24-26 with the GPU oscillating between 100%/338W and 72%/163W while its
# junction temperature FELL from 81C to 63C — starved, not overloaded. Every
# resource explanation came back negative: IO pressure 0.00, CPU pressure 0.53,
# 73 of the game's 89 threads asleep, no amdgpu events, VRAM 12.9 of 16.3 GiB
# with GTT flat. With this fix in place the same game ran 30 minutes flat at
# 100% / 338W with no stutter.
#
# Running gamescope clean and handing LD_PRELOAD to the game keeps the overlay,
# game recording and the rest of Steam's features. Blanking LD_PRELOAD outright
# also stops the stutter but loses all of that.
#
# Full write-up: docs/akunito/gaming/gamescope-lag-bomb.md
STEAM_PRELOAD="${LD_PRELOAD:-}"
if [[ -n "$STEAM_PRELOAD" ]]; then
    unset LD_PRELOAD
    log "stripped LD_PRELOAD from gamescope (lag bomb); re-injecting it for the game"
fi

run_game=("${GAME_CMD[@]}")
if [[ -n "$STEAM_PRELOAD" && ${#GAME_CMD[@]} -gt 0 ]]; then
    run_game=(env "LD_PRELOAD=$STEAM_PRELOAD" "${GAME_CMD[@]}")
fi

if [[ "${GAMESCOPE_DISABLE:-0}" == "1" && ${#GAME_CMD[@]} -gt 0 ]]; then
    log "GAMESCOPE_DISABLE=1, running without gamescope: ${GAME_CMD[*]}"
    setsid "${run_game[@]}" &
    GAMESCOPE_PID=$!
    GAMESCOPE_PGID=$GAMESCOPE_PID
    GAMESCOPE_RC=0
    wait "$GAMESCOPE_PID" 2>/dev/null || GAMESCOPE_RC=$?
    exit 0
fi

if [[ ${#GAME_CMD[@]} -gt 0 ]]; then
    GS_INVOKE=("${GS_ARGS[@]}" -- "${run_game[@]}")
else
    GS_INVOKE=("$@")
fi

# GAMESCOPE_WLDEBUG captures the Wayland protocol conversation. gamescope 3.16.x
# can abort (SIGABRT, rc=134) inside CWaylandInputThread::ThreadFunc when its
# display connection errors — that is what kills Black Desert about 10s into a
# launch, intermittently. The abort itself says nothing; the protocol tail names
# the request the compositor rejected. The log is large (~35k lines per 10s), so
# it goes to a file and only on request.
if [[ "${GAMESCOPE_WLDEBUG:-0}" == "1" ]]; then
    WLDEBUG_LOG="${TRACE_DIR}/wldebug-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$TRACE_DIR" 2>/dev/null || true
    # WAYLAND_DEBUG writes about 600 KB/s, i.e. ~2 GB per hour. An uncapped
    # capture of one long session produced a 2.9 GB file on 2026-09-04.
    #
    # Cap it with `tail -c`, not `head -c`: the evidence for a crash is at the
    # END. The protocol error that identified this bug —
    #   wl_display#1.error(xdg_surface#50, 3, "xdg_surface has never been
    #   configured")
    # — was in the last 30 lines, and the whole crash log was only 1.3 MB. `tail`
    # holds the cap in memory and flushes at EOF, which a crashing gamescope
    # always reaches.
    #
    # Process substitution keeps $! pointing at gamescope rather than at the
    # tail, which a plain pipeline would break.
    WLDEBUG_MAX=$(( ${GAMESCOPE_WLDEBUG_MAX_MB:-64} * 1048576 ))
    log "WAYLAND_DEBUG capture (last $(( WLDEBUG_MAX / 1048576 ))MB) -> $WLDEBUG_LOG"
    WAYLAND_DEBUG=1 setsid gamescope "${GS_INVOKE[@]}" \
        > >(tail -c "$WLDEBUG_MAX" > "$WLDEBUG_LOG") 2>&1 &
else
    setsid gamescope "${GS_INVOKE[@]}" &
fi
GAMESCOPE_PID=$!
GAMESCOPE_PGID=$GAMESCOPE_PID

GAMESCOPE_RC=0
wait "$GAMESCOPE_PID" 2>/dev/null || GAMESCOPE_RC=$?
log "gamescope exited rc=$GAMESCOPE_RC after ${SECONDS}s"
