"""Spacing: sway gaps (between tiles, tiles to the monitor edge) and the space
around each Waybar bar, per profile (settings "spacing" + "waybar.margins").

sway's model: `gaps inner` is the space between adjacent tiles; the space from
a tile to the monitor edge is inner + outer (outer may be negative). The user
sets the EDGE distance and outer is derived. The space between a bar and the
tiles below it is the bar's bottom margin + the edge distance — at the Nix
defaults (Waybar margin 8, gaps inner 8) that was 16 px on DESK (2026-10-14).

Applied live (`gaps … all set`, Waybar restart for its CSS) and written to the
include so new workspaces and reloads keep it; saved to the profile JSON
(committed like every other sway-apps setting).
"""
from __future__ import annotations

import os
from typing import Any

from . import log

_log = log.get("spacing")

SETTINGS_KEY = "spacing"
SETTINGS_DEFAULTS: dict = {}
GUI_PANELS = [("spacing", "Spacing", "Gaps · bar margins", "view-paged-symbolic", "panels_spacing:SpacingPanel")]

# Nix's `gaps.inner` (swayfx-config.nix), passed by the wrapper; outer is 0 there.
NIX_INNER = int(os.environ.get("SWAY_APPS_GAPS_INNER", "8") or 8)
GAP_MAX = 64


def _clamp(v: Any, lo: int = 0, hi: int = GAP_MAX) -> int:
    return max(lo, min(hi, int(v)))


def values(state) -> dict[str, int]:
    """Effective values: inner, edge, and the bar margins (top, sides, bottom)."""
    from . import waybar
    s = state.feature(SETTINGS_KEY)
    inner = _clamp(s["inner"]) if isinstance(s.get("inner"), (int, float)) else NIX_INNER
    edge = _clamp(s["edge"]) if isinstance(s.get("edge"), (int, float)) else inner
    m = waybar.bar_margins(state.feature(waybar.SETTINGS_KEY))
    return {"inner": inner, "edge": edge, "bar_top": m["top"], "bar_sides": m["sides"], "bar_bottom": m["bottom"],
            "bar_to_tiles": m["bottom"] + edge}


def render_include(state) -> str:
    s = state.feature(SETTINGS_KEY)
    if not any(isinstance(s.get(k), (int, float)) for k in ("inner", "edge")):
        return ""  # untouched: the Nix gaps stand
    v = values(state)
    return f"\n# ---- spacing (sway-apps spacing)\ngaps inner {v['inner']}\ngaps outer {v['edge'] - v['inner']}\n"


def live_command(v: dict[str, int]) -> str:
    return f"gaps inner all set {v['inner']}; gaps outer all set {v['edge'] - v['inner']}"


def update(state, inner: int | None = None, edge: int | None = None, bar_top: int | None = None,
           bar_sides: int | None = None, bar_bottom: int | None = None, reset: bool = False) -> dict[str, Any]:
    """Change the profile values in memory; returns {"gaps_changed", "margins_changed"}."""
    from . import waybar
    sp = dict(((state.profile.get("settings") or {}).get(SETTINGS_KEY)) or {})
    wb = dict(((state.profile.get("settings") or {}).get(waybar.SETTINGS_KEY)) or {})
    margins = dict(wb.get("margins") or {})
    before = values(state)
    if reset:
        sp = {}
        margins = {}
    for key, val in (("inner", inner), ("edge", edge)):
        if val is not None:
            sp[key] = _clamp(val)
    for key, val in (("top", bar_top), ("sides", bar_sides), ("bottom", bar_bottom)):
        if val is not None:
            margins[key] = _clamp(val, 0, waybar.MARGIN_MAX)
    state.set_feature(SETTINGS_KEY, sp, "profile")
    if margins:
        wb["margins"] = margins
    else:
        wb.pop("margins", None)
    state.set_feature(waybar.SETTINGS_KEY, wb, "profile")
    after = values(state)
    return {"gaps_changed": (before["inner"], before["edge"]) != (after["inner"], after["edge"]),
            "margins_changed": any(before[k] != after[k] for k in ("bar_top", "bar_sides", "bar_bottom")),
            "values": after}


def apply(state, changed: dict[str, Any], message: str, commit: bool = True) -> dict[str, Any]:
    """Persist + apply live: include (no reload), `gaps … all set`, Waybar CSS."""
    from . import generate, gitsync, swayipc, waybar
    res: dict[str, Any] = {"values": changed["values"]}
    state.write()
    res["include"] = generate.apply(state, reload=False)["path"]
    if changed["gaps_changed"] and swayipc.available():
        swayipc.command(live_command(changed["values"]))
        res["gaps_live"] = True
    if changed["margins_changed"]:
        sway = waybar.SwayLink.connect()
        try:
            res["waybar"] = waybar.Runtime(state).sync(sway, reload=True)
        finally:
            if sway:
                sway.close()
    if commit:
        try:
            sha = gitsync.commit(state.files(), message)
            res["commit"] = sha
            if sha and gitsync.auto_sync_enabled():
                gitsync.sync()
        except Exception as exc:  # git/network down: the files are written
            _log.warning("commit/sync failed: %s", exc)
            res["commit_error"] = str(exc)
    return res


# --------------------------------------------------------------------------
# CLI

def register_cli(sub) -> None:
    p = sub.add_parser("spacing", help="gaps between tiles / to the monitor edge, space around the bars")
    sp = p.add_subparsers(dest="sub", required=True)
    sp.add_parser("show").set_defaults(func=_cmd_show)
    x = sp.add_parser("set")
    x.add_argument("--inner", type=int, help="px between adjacent tiles")
    x.add_argument("--edge", type=int, help="px from tiles to the monitor edge")
    x.add_argument("--bar-top", type=int, help="px above each bar")
    x.add_argument("--bar-sides", type=int, help="px left/right of each bar")
    x.add_argument("--bar-bottom", type=int, help="px under each bar (bar-to-tiles = this + edge)")
    x.add_argument("--no-git", action="store_true")
    x.set_defaults(func=_cmd_set)
    x = sp.add_parser("reset", help="back to the Nix defaults")
    x.add_argument("--no-git", action="store_true")
    x.set_defaults(func=_cmd_reset)


def _print(v: dict[str, int]) -> None:
    print(f"between tiles {v['inner']} px · tiles to edge {v['edge']} px · bar margins top {v['bar_top']} / "
          f"sides {v['bar_sides']} / bottom {v['bar_bottom']} px → bar to tiles {v['bar_to_tiles']} px")


def _cmd_show(a) -> int:
    from . import cli
    from .state import State
    v = values(State())
    cli._out(a, v, lambda: _print(v))
    return 0


def _run(a, **kw) -> int:
    from . import cli
    from .state import State
    st = State()
    ch = update(st, **kw)
    res = apply(st, ch, "spacing: " + ", ".join(f"{k}={v}" for k, v in ch["values"].items()), commit=not a.no_git)
    cli._out(a, res, lambda: _print(res["values"]))
    return 0


def _cmd_set(a) -> int:
    return _run(a, inner=a.inner, edge=a.edge, bar_top=a.bar_top, bar_sides=a.bar_sides, bar_bottom=a.bar_bottom)


def _cmd_reset(a) -> int:
    return _run(a, reset=True)
