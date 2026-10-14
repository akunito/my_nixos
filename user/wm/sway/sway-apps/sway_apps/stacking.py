"""Window stacking, sway-apps side (plan §3, SWAY-6/7). Owner: workstream A.

The compositor half is patches/sway-window-stacking.patch (lift_tiled_on_press,
pin, z raise|lower, floating move/resize IPC events). This module renders the
peek setting into the include, offers the pin rule action ("always pin this
app") and the per-window/rule above_fullscreen switch.
"""
from __future__ import annotations

SETTINGS_KEY = "stacking"
SETTINGS_DEFAULTS: dict = {}

GUI_PANELS = [("stacking", "Stacking", "Peek · pin · z-order", "view-dual-symbolic", "panels_stacking:StackingPanel")]


def register_cli(sub) -> None:
    pass


def setup_watch(reg) -> None:
    pass
