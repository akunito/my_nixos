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
  before_reload(state)              generate.apply: write files the coming sway reload must see
  after_apply(state, reloaded)      generate.apply: after the reload (or none); signal other processes
Owning files per feature keeps parallel work out of cli.py/state.py/watch.py/gui/app.py.
"""
from __future__ import annotations

import importlib
from types import ModuleType
from typing import Any, Iterator

from . import log

FEATURES = ("tray", "waybar", "stacking", "displays", "placement", "spacing", "overview", "input")

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


def _hook(name: str, *args) -> None:
    for m in modules():
        fn = getattr(m, name, None)
        if fn:
            try:
                fn(*args)
            except Exception as exc:  # a feature must never break the rules include
                log.get("features").exception("%s.%s failed: %s", m.__name__, name, exc)


def before_reload(state) -> None:
    _hook("before_reload", state)


def after_apply(state, reloaded: bool) -> None:
    _hook("after_apply", state, reloaded)


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
