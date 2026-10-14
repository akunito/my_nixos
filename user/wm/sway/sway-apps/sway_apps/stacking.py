"""Window stacking, sway-apps side (plan §3, SWAY-6/7). Owner: workstream A.

The compositor half is patches/sway-window-stacking.patch (`lift_tiled_on_press`,
`pin`, `z raise|lower`, window:move on floating drag/resize) and
patches/sway-above-fullscreen.patch (`above_fullscreen`). This module renders the
peek setting into the include, lists floating windows with their pin /
above-fullscreen state, and writes "always pin this app" rules. Every
patch-only command is gated on paths.SWAY_FEATURES.
"""
from __future__ import annotations

import re
from typing import Any

from . import paths

SETTINGS_KEY = "stacking"
SETTINGS_DEFAULTS: dict = {"peek": True}

GUI_PANELS = [("stacking", "Stacking", "Peek · pin · z-order", "view-dual-symbolic", "panels_stacking:StackingPanel")]

MODES = ("enable", "disable", "toggle")
FULLSCREEN_COST = ("A window drawn over a fullscreen game makes sway composite every frame instead of scanning "
                   "the game out directly: AkuWM measured 45 fps and +60 ms on Aion 2 with an overlay on top. "
                   "Use it for small overlays you need in-game, not as a default.")
_RULE_HEADS = ("floating", "pin", "above_fullscreen")


def supported(feature: str = "stacking", features: frozenset[str] | None = None) -> bool:
    return feature in (paths.SWAY_FEATURES if features is None else features)


def peek_enabled(state) -> bool:
    return bool(state.feature(SETTINGS_KEY).get("peek", True))


def render_include(state, features: frozenset[str] | None = None) -> str:
    if not supported("stacking", features):
        return ""
    return ("\n# ---- Stacking (peek: a covered tile is drawn above the floats while a button is held on it)\n"
            f"lift_tiled_on_press {'enable' if peek_enabled(state) else 'disable'}\n")


def set_peek(state, on: bool, scope: str = "profile") -> None:
    layer = state.profile if scope == "profile" else state.common
    ns = dict((layer.get("settings") or {}).get(SETTINGS_KEY) or {})
    ns["peek"] = bool(on)
    state.set_feature(SETTINGS_KEY, ns, scope)


# ---- live windows -----------------------------------------------------------------------
def _first_view(node: dict[str, Any]) -> dict[str, Any] | None:
    if node.get("app_id") or node.get("window_properties"):
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        v = _first_view(child)
        if v is not None:
            return v
    return None


def floating_windows(tree: dict[str, Any]) -> list[dict[str, Any]]:
    """Top-level floaters of every workspace, bottom to top per workspace (sway's list order)."""
    out: list[dict[str, Any]] = []
    for output in tree.get("nodes", []):
        if output.get("name") == "__i3":
            continue
        for ws in output.get("nodes", []):
            floats = ws.get("floating_nodes", [])
            for i, f in enumerate(floats):
                v = _first_view(f) or f
                props = v.get("window_properties") or {}
                out.append({
                    "id": f["id"], "app_id": v.get("app_id") or "", "class": props.get("class") or "",
                    "title": v.get("name") or "", "workspace": ws.get("name"), "output": output.get("name"),
                    "pinned": bool(f.get("pinned")), "above_fullscreen": bool(f.get("above_fullscreen")),
                    "sticky": bool(f.get("sticky")), "focused": bool(f.get("focused") or v.get("focused")),
                    "visible": bool(v.get("visible")), "z": i, "top": i == len(floats) - 1,
                })
    return out


def label(w: dict[str, Any]) -> str:
    return w.get("app_id") or w.get("class") or w.get("title") or f"con {w['id']}"


def window_command(con_id: int, verb: str, mode: str) -> str:
    if verb not in ("pin", "above_fullscreen") or mode not in MODES:
        raise ValueError(f"bad stacking command {verb} {mode}")
    return f"[con_id={int(con_id)}] {verb} {mode}"


# ---- rules ------------------------------------------------------------------------------
def identity_criteria(w: dict[str, Any]) -> dict[str, str]:
    if w.get("app_id"):
        return {"app_id": f"^{re.escape(w['app_id'])}$"}
    if w.get("class"):
        return {"class": f"^{re.escape(w['class'])}$"}
    raise ValueError("window has neither app_id nor class")


def pin_rule(state, criteria: dict[str, str], above_fullscreen: bool = False, scope: str = "common"):
    """The for_window rule that always pins these windows. An existing rule with the same
    criteria is reused and keeps its other actions (and an above_fullscreen it already has).
    Not saved."""
    from .rules import Rule
    probe = Rule.new("for_window", criteria, [])
    existing = next((r for r in state.rules() if r.criteria_key() == probe.criteria_key()), None)
    other: list[str] = []
    if existing is not None:
        other = [a for a in existing.actions if a.split()[0] not in _RULE_HEADS]
        above_fullscreen = above_fullscreen or "above_fullscreen enable" in (a.strip() for a in existing.actions)
    actions = ["floating enable"] + other + ["pin enable"] + (["above_fullscreen enable"] if above_fullscreen else [])
    if existing is not None:
        existing.actions = actions
        return existing
    rule = Rule.new("for_window", criteria, actions, notes="stacking: always pinned")
    rule.scope = scope
    return rule


# ---- CLI --------------------------------------------------------------------------------
def register_cli(sub) -> None:
    p = sub.add_parser("stacking", help="peek / pin / above-fullscreen (patched sway)")
    s = p.add_subparsers(dest="stacking_cmd", required=True)
    s.add_parser("status", help="peek setting, compositor support, floating windows").set_defaults(func=_cli_status)
    pk = s.add_parser("peek", help="lift a covered tile while a button is held on it")
    pk.add_argument("state", choices=("on", "off"))
    pk.add_argument("--no-git", action="store_true", help="do not auto-commit")
    pk.set_defaults(func=_cli_peek)
    for verb in ("pin", "above-fullscreen"):
        x = s.add_parser(verb, help=f"{verb} a floating window (default: the focused one)")
        x.add_argument("mode", nargs="?", default="toggle", choices=MODES)
        x.add_argument("--con-id", type=int)
        x.set_defaults(func=_cli_window, verb=verb.replace("-", "_"))
    ap = s.add_parser("always-pin", help="rule: windows of APP open floating and pinned")
    ap.add_argument("app", help="app_id (or the X11 class with --class)")
    ap.add_argument("--class", dest="is_class", action="store_true", help="match the X11 class")
    ap.add_argument("--above-fullscreen", action="store_true", help="also draw it over fullscreen views")
    ap.add_argument("--scope", default="common", choices=("common", "profile"))
    ap.add_argument("--no-git", action="store_true", help="do not auto-commit")
    ap.set_defaults(func=_cli_always_pin)


def _cli_status(args) -> int:
    from . import swayipc
    from .cli import _out
    from .state import State
    wins = floating_windows(swayipc.get("get_tree")) if swayipc.available() else []
    data = {"peek": peek_enabled(State()), "stacking": supported("stacking"),
            "above_fullscreen": supported("above_fullscreen"), "floating": wins}

    def human() -> None:
        print(f"peek {'on' if data['peek'] else 'off'} · stacking patch {'yes' if data['stacking'] else 'NO'}"
              f" · above_fullscreen patch {'yes' if data['above_fullscreen'] else 'NO'}")
        for w in wins:
            flags = " ".join(f for f in ("pinned", "above_fullscreen", "sticky", "focused") if w[f])
            print(f"  {w['id']:>5}  ws {w['workspace']:<4} z{w['z']}  {label(w)}  {flags}")
    _out(args, data, human)
    return 0


def _cli_peek(args) -> int:
    from .cli import _out, _persist
    from .state import State
    st = State()
    set_peek(st, args.state == "on")
    res = _persist(args, st, f"sway-apps: stacking peek {args.state}", apply_rules=True)
    _out(args, res, lambda: print(f"peek {args.state}"))
    return 0


def _cli_window(args) -> int:
    from . import swayipc
    from .cli import _out
    feature = "stacking" if args.verb == "pin" else "above_fullscreen"
    if not supported(feature):
        print(f"this sway has no `{args.verb}` (the Nix flag for the {feature} patch is off)")
        return 2
    con = args.con_id
    if con is None:
        w = swayipc.focused_window()
        if w is None:
            print("no focused window")
            return 1
        con = w.id
    try:
        res = swayipc.command(window_command(con, args.verb, args.mode))
    except swayipc.SwayError as exc:
        print(exc)
        return 1
    _out(args, res, lambda: print(f"{args.verb} {args.mode} on {con}"))
    return 0


def _cli_always_pin(args) -> int:
    from .cli import _out, _persist
    from .state import State
    st = State()
    rule = pin_rule(st, identity_criteria({"class": args.app} if args.is_class else {"app_id": args.app}),
                    args.above_fullscreen, args.scope)
    st.save_rule(rule)
    res = _persist(args, st, f"sway-apps: always pin {args.app}", apply_rules=True, live_rule=rule)
    _out(args, res, lambda: print(rule.render()))
    return 0


def setup_watch(reg) -> None:
    pass
