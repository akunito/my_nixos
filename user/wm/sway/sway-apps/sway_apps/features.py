"""Feature modules plug into the CLI, the watch daemon, the settings and the GUI here.

Each module in FEATURES may define:
  SETTINGS_KEY / SETTINGS_DEFAULTS  its namespace in state settings (deep-merged:
                                    defaults < common.json < <PROFILE>.json)
  register_cli(sub)                 add argparse sub-commands
  setup_watch(reg)                  register handlers on the watch daemon (watch.Registry)
  render_include(state) -> str      text appended to ~/.config/sway/sway-apps.conf (validated
                                    with the session's sway; gate patch-only commands on
                                    paths.SWAY_FEATURES)
  GUI_PANELS                        [(key, title, subtitle, icon, "gui.module:Class")]
Owning files per feature keeps parallel work out of cli.py/state.py/watch.py/gui/app.py.
"""
from __future__ import annotations

import importlib
from types import ModuleType
from typing import Any, Iterator

FEATURES = ("tray", "waybar", "stacking", "displays", "placement")

_loaded: list[ModuleType] | None = None


def modules() -> list[ModuleType]:
    global _loaded
    if _loaded is None:
        _loaded = [importlib.import_module(f"{__package__}.{name}") for name in FEATURES]
    return _loaded


def settings_defaults() -> dict[str, Any]:
    return {m.SETTINGS_KEY: m.SETTINGS_DEFAULTS for m in modules() if getattr(m, "SETTINGS_KEY", None)}


def register_cli(sub) -> None:
    for m in modules():
        fn = getattr(m, "register_cli", None)
        if fn:
            fn(sub)


def setup_watch(reg) -> None:
    for m in modules():
        fn = getattr(m, "setup_watch", None)
        if fn:
            fn(reg)


def include_fragments(state) -> Iterator[str]:
    for m in modules():
        fn = getattr(m, "render_include", None)
        if fn:
            text = fn(state)
            if text:
                yield text


def gui_panels() -> Iterator[tuple[str, str, str, str, str]]:
    for m in modules():
        yield from getattr(m, "GUI_PANELS", ())


def deep_merge(base: dict[str, Any], over: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out
