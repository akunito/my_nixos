# DESK_W11 AHK measurement scripts

Run with `AutoHotkey64.exe /ErrorStdOut <script>`; each writes a report to `%TEMP%\<name>.txt`.
They drive a real window (Discord by default), so run them with nothing important going on.

| Script | What it measures | Result 2026-09-15 |
|---|---|---|
| `ahk-space.ahk` | AHK's coordinate space (system-DPI aware, 150 %): monitor 1 = 0..3840, monitor 2 virtualised = 4608..6336 × −490..2582 | targets left of 4608 are "between monitors" and get pushed to 4608 |
| `drag-cycle.ahk` | the cross-monitor part of `AltDrag`: one WinMove, poll the app's rescale (125–156 ms), one size restore | 250–280 ms per crossing, size exact ×6 |
| `live-cross-storm.ahk` | why the window is NOT moved live across the boundary: every position-only WinMove on the other monitor rescales a per-monitor-DPI app again, cumulatively | Discord 1656×1216 → 3199×28131 in 60 steps |
