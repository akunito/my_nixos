"""Output layout owner (plan §0 + §4, SWAY-8/9). Owner: workstream C.

Renders `output "<hw id>" {…}` (mode, pos, scale, transform, adaptive_sync,
enable/disable) and the xwayland_* lines into the sway-apps include; exact-scale
math; one-time import of nwg-displays' ~/.config/sway/outputs; live apply with a
revert timer. The GUI lives in gui/panels_monitors.py (reworked, same section).
"""
from __future__ import annotations

SETTINGS_KEY = "displays"
SETTINGS_DEFAULTS: dict = {}

GUI_PANELS: list = []


def register_cli(sub) -> None:
    pass


def setup_watch(reg) -> None:
    pass
