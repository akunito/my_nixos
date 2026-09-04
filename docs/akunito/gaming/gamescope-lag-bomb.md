# The gamescope lag bomb (DESK, resolved 2026-09-04)

Every game launched through gamescope from Steam became unplayable after roughly
25 minutes. It affected Black Desert, Skyrim and Crimson Desert alike, on both
gamescope backends, and it had been happening for months.

**Cause:** Steam exports `LD_PRELOAD` across the whole launch command, so the
Steam overlay (`gameoverlayrenderer.so`) is preloaded into **gamescope itself**,
not only into the game. Around the 24-minute mark that wrecks gamescope's frame
pacing.

**Fix:** `user/wm/sway/scripts/gamescope-wrapper.sh` now unsets `LD_PRELOAD`
before exec'ing gamescope and re-injects it with `env` in front of the game
command. The compositor runs clean; the game keeps the overlay, game recording
and the rest of Steam's features.

Nothing in the Steam launch options changes — the fix lives in the wrapper.

## How it looked

Every resource explanation came back negative. During the collapse:

| | measured | limit |
|---|---|---|
| VRAM | 12.9 GiB, flat | 16.3 GiB |
| GTT | 237 MiB, flat | 10240 MiB |
| junction temp | **falling**, 81 → 63 °C | crit 110 °C |
| IO pressure | 0.00 | — |
| CPU pressure | 0.53 | — |
| game threads | 73 of 89 **asleep** | — |
| amdgpu events | none — no reset, timeout or fault | — |

The tell was the GPU oscillating between 100% / 3050 MHz / 338 W and
72% / 2172 MHz / 163 W with its temperature dropping. The card was not
overloaded, it was **starved**: everything waiting, nothing busy.

## Before and after, same 5-minute buckets

```
                 before                          after
min 20-25   gpu 100%  338W  81C          gpu  99%  334W  81C
min 24-26   gpu  98%  323W  80C          -
min 26-28   gpu  72%  163W  63C   <--    -
min 25-30   -                            gpu 100%  338W  81C
min 30-35   -                            gpu 100%  328W  80C
```

30 minutes, flat, no stutter reported.

## Verifying it is active

```
# gamescope must have no LD_PRELOAD, the game must have it
tr '\0' '\n' < /proc/$(pgrep -x gamescope-wl)/environ | grep -c '^LD_PRELOAD='   # 0
tr '\0' '\n' < /proc/$(pgrep -x <game>.e)/environ    | grep -c '^LD_PRELOAD='    # 1
```

The wrapper also logs it to Steam's console log on every launch:

```
[gamescope-wrapper] stripped LD_PRELOAD from gamescope (lag bomb); re-injecting it for the game
```

## What this was NOT

Recorded so these are not re-investigated:

- **Not VRAM or GTT exhaustion.** Peak 12.9 of 16.3 GiB, GTT never above 452 MiB.
- **Not thermal.** Junction peaked at 81 °C against a 110 °C limit, and *fell*
  during the stall.
- **Not the local LLM.** Ollama logged zero model loads in ten days.
- **Not a process leak.** Steam logs ~400 "Adding process" per minute against the
  game, but the system's process count stays flat and `/proc` scanning finds no
  game processes being spawned. It is Steam bookkeeping, not forks.
- **Not `--force-grab-cursor`.** Upstream #1851 blames it for freezes on 3.16.x,
  and it fits Skyrim and Crimson Desert, but Black Desert lagged without it.

## Side finding: mc-netwatch was a fork bomb

`mc-netwatch.service` (a hand-made probe in `~/.config/systemd/user/`, not in
this repo) ran with `PATH` set to systemd's bin directory alone, so `sleep`,
`ping` and `date` all failed to exec. Its `while :; do ping; sleep 1; done` loop
spun at full speed: **~3500 fork/exec per second, burning a core since
2026-09-02**, and the probe never detected anything because `ping` never ran.
Fixed with `Environment=PATH=/run/current-system/sw/bin:...`; the machine went
from 3544 to 74 forks/s. Unrelated to the lag, which predated it, but worth
keeping fixed.

## Still open

- **Black Desert aborts on the gamescope Wayland backend.** SIGABRT in
  `CWaylandInputThread::ThreadFunc`, ~10s into a launch, intermittent (one
  28-minute session survived out of six attempts). Set `GAMESCOPE_WLDEBUG=1` in
  the launch options to capture the protocol log that would name the rejected
  request.
- **`--rt` does nothing.** gamescope logs `No CAP_SYS_NICE, falling back to
  regular-priority`. Do NOT fix with `programs.gamescope.capSysNice` — see the
  warnings in `system/app/steam.nix`. The remaining route is `RLIMIT_RTPRIO` via
  `security.pam.loginLimits`.
