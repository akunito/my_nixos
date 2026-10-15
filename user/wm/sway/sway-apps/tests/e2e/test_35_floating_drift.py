"""Floating windows must not drift when a bar goes away and comes back
(patches/sway-floating-gaps-drift.patch). Every deploy restarts waybar; sway's arrange_workspace
then rescales floaters from the GAPPED previous box to the bare new one, so hide+show is not
an identity: measured on DESK 2026-10-15, -4 px (x and y) per waybar restart on a 4K@1.5 output
with gaps, cumulative. swaybar `mode invisible`/`dock` changes the usable area the same way."""
from __future__ import annotations

import time
from pathlib import Path

from harness import E2EFailure, Nested, SWAY

BAR = """gaps inner 8
gaps outer 4
bar {{
    id top
    position top
    swaybar_command {swaybar}
    status_command echo drift
    tray_output none
    mode dock
}}
"""


def _rects(s: Nested, cids: list[int]) -> dict[int, tuple[int, int, int, int]]:
    out = {}
    stack = [s.tree()]
    while stack:
        n = stack.pop()
        if n.get("id") in cids:
            r = n["rect"]
            out[n["id"]] = (r["x"], r["y"], r["width"], r["height"])
        stack += (n.get("nodes") or []) + (n.get("floating_nodes") or [])
    return out


def _ws_y(s: Nested) -> list[int]:
    return sorted(w["rect"]["y"] for w in s.workspaces() if w["visible"])


def case_floaters_survive_bar_round_trips():
    swaybar = str(Path(SWAY).with_name("swaybar"))
    with Nested(outputs=[(1920, 1080), (2560, 1440)], scales=[1.0, 1.5], config=BAR.format(swaybar=swaybar)) as s:
        s.wait(lambda: min(_ws_y(s)) > 4, "bar docked (usable area below it)")
        docked = _ws_y(s)
        s.cmd("focus output HEADLESS-1")
        a = s.client("drift.a", "400x240", floating=True)
        a.cmd("move absolute position 700 600")
        s.cmd("focus output HEADLESS-2")
        b = s.client("drift.b", "500x300", floating=True)
        b.cmd("move absolute position 2300 650")
        cids = [a.node()["id"], b.node()["id"]]
        before = _rects(s, cids)
        moved_while_hidden = False
        for i in range(5):
            s.cmd("bar top mode invisible")
            s.wait(lambda: _ws_y(s) != docked, f"round {i}: bar gone")
            time.sleep(0.3)
            moved_while_hidden |= _rects(s, cids) != before
            s.cmd("bar top mode dock")
            s.wait(lambda: _ws_y(s) == docked, f"round {i}: bar back")
            time.sleep(0.3)   # swaybar is still configuring its new surface; a mode change now is lost
        after = _rects(s, cids)
        if not moved_while_hidden:
            raise E2EFailure("the bar change never moved the floaters: the test does not exercise arrange_workspace")
        if after != before:
            raise E2EFailure(f"floaters drifted after 5 bar round trips: {before} -> {after}")
