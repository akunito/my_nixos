"""Window placement (plan §5-7, SWAY-10/11/12). Owner: workstream D.

Live window journal + restore on map, bring off-screen / bring-all toggle
(loans), monitor power-off policy (ignore | move windows, 5 s grace, restore on
return). All state machine-local under ~/.local/state/sway-apps/.
"""
from __future__ import annotations

SETTINGS_KEY = "placement"
SETTINGS_DEFAULTS: dict = {}

GUI_PANELS = [("placement", "Placement", "Remember · bring · power-off", "window-restore-symbolic", "panels_placement:PlacementPanel")]


def register_cli(sub) -> None:
    pass


def setup_watch(reg) -> None:
    pass
