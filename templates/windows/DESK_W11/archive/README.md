# Archive

Files from the GlazeWM era of DESK_W11 (2026-09-13 to 2026-09-21), kept for the
record. Nothing reads them.

- `glazewm-config.yaml`: the floating-only GlazeWM config (workspaces 10-19 and
  20-29 bound by monitor, window rules). AkuWM imported the rules into
  `../akuwm/common.json` (each carries `"notes": "imported from glazewm/config.yaml"`).
- `vd-merge.ahk`: folded stray native virtual desktops back into the first one,
  because GlazeWM only managed windows on the current native desktop. AkuWM
  manages every window it sees regardless of native desktop, and
  `hyper-desktops.ahk` still swallows Ctrl+Win+D / Ctrl+Win+arrows.
