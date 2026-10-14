"""Per-monitor Waybar (plan §2, SWAY-2..5). Owner: workstream B.

Generates ~/.config/waybar/config, ~/.config/waybar/style.css (from the Nix
base), ~/.config/waybar/sway-apps.css and ~/.config/sway/sway-apps-bars.conf
from the Nix module catalog (~/.config/sway-apps/waybar-modules.json), the
profile settings below and the machine-local visibility state
(~/.local/state/sway-apps/waybar.json). Verb `waybar` on the watch daemon
(Hyper+Shift+H = `nop sway-apps waybar toggle`).
"""
from __future__ import annotations

SETTINGS_KEY = "waybar"
SETTINGS_DEFAULTS: dict = {}

GUI_PANELS = [("waybar", "Waybar", "Bars per monitor · widgets", "view-continuous-symbolic", "panels_waybar:WaybarPanel")]


def register_cli(sub) -> None:
    pass


def setup_watch(reg) -> None:
    pass
