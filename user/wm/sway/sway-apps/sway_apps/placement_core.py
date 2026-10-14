"""Placement logic without IO: tree model, rect math, journal records, loans.

Everything here takes a World (one parsed get_tree) and returns sway commands,
so the unit tests drive it with literal trees. placement.py executes them.

Measured in nested sway 1.11 (2026-10-14), shaping every command below:
  - `move [absolute] position` on a floating con whose workspace is HIDDEN makes
    it hop to its output's VISIBLE workspace (container_floating_move_to picks
    output_get_active_workspace). So: position first, then `move container to
    workspace` (same output keeps the position; another output re-centres it).
  - `window:new` arrives BEFORE for_window criteria run (payload: tiled, not
    sticky, rect 0x0); the tree read while handling it already has them applied.
  - The `close` payload carries the final rect; no event carries the workspace.
  - DESK runs `workspace_auto_back_and_forth yes`: a move to the workspace the
    con is already on would bounce it to the previous one, hence
    --no-auto-back-and-forth on every move. The flag goes right after `move`:
    `move container to workspace --no-auto-back-and-forth 22` created a
    workspace NAMED "--no-auto-back-and-forth 22".
"""
from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable

Rect = tuple[int, int, int, int]  # x, y, w, h in layout coordinates

# AkuWM Desk.Compute GrabMarginPx: "A floating window the person can still take
# hold of: at least this much of it, both ways, on the work area. Dragging a
# window mostly off the screen to see what is under it is a thing people do, and
# 'more than half inside' pulled every such window back (Diego, 2026-09-23 11:52;
# 24 px is his number)."
GRAB_MARGIN_PX = 24

POLICIES = ("ignore", "move")
GAME_RX = re.compile(r"^(gamescope.*|steam_app_.*)$", re.I)
DIALOG_TYPES = frozenset(("dialog", "utility", "splash", "toolbar", "menu", "dropdown_menu", "popup_menu", "tooltip", "notification"))
SCRATCH = "__i3_scratch"


# --------------------------------------------------------------------------
# rect math

def overlap(a: Rect, b: Rect) -> tuple[int, int]:
    return (min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]),
            min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))


def reachable(rect: Rect, area: Rect) -> bool:
    across, down = overlap(rect, area)
    return across >= GRAB_MARGIN_PX and down >= GRAB_MARGIN_PX


def offscreen(rect: Rect, areas: Iterable[Rect]) -> bool:
    for a in areas:
        if reachable(rect, a):
            return False
    return True


def clamp_into(rect: Rect, area: Rect) -> Rect:
    """AkuWM FloatingRectOf: trimmed only when larger than the area (the size is
    the person's choice), then moved inside."""
    x, y, w, h = rect
    ax, ay, aw, ah = area
    w, h = min(w, aw), min(h, ah)
    return (max(ax, min(x, ax + aw - w)), max(ay, min(y, ay + ah - h)), w, h)


def fraction_of(rect: Rect, area: Rect) -> list[float]:
    """Position as a fraction of the area, size in px: survives a mode change."""
    return [round((rect[0] - area[0]) / area[2], 5) if area[2] else 0.0,
            round((rect[1] - area[1]) / area[3], 5) if area[3] else 0.0, rect[2], rect[3]]


def from_fraction(rel: list[float], area: Rect) -> Rect:
    return clamp_into((area[0] + round(rel[0] * area[2]), area[1] + round(rel[1] * area[3]), int(rel[2]), int(rel[3])), area)


def map_rect(rect: Rect, src: Rect, dst: Rect) -> Rect:
    return from_fraction(fraction_of(rect, src), dst)


def _rect(d: dict[str, Any] | None) -> Rect:
    d = d or {}
    return (int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("width", 0)), int(d.get("height", 0)))


def quote(name: str) -> str:
    return json.dumps(name)


# --------------------------------------------------------------------------
# world: one parsed get_tree

@dataclass(slots=True)
class Win:
    id: int
    app_id: str | None
    cls: str | None
    title: str | None
    window_type: str | None
    transient: bool
    shell: str | None
    ws: str
    output: str
    floating: bool
    fullscreen: int
    sticky: bool
    pinned: bool
    rect: Rect
    focused: bool = False
    instance: str | None = None
    window_role: str | None = None
    pid: int | None = None
    marks: list[str] = field(default_factory=list)


@dataclass(slots=True)
class Out:
    name: str
    hw: str
    rect: Rect
    area: Rect          # usable rect (workspace rect: bars excluded)
    visible_ws: str | None


@dataclass(slots=True)
class Ws:
    name: str
    num: int | None
    output: str


def hw_of(node: dict[str, Any]) -> str:
    from .monitors import hw_id
    return hw_id(node)


class World:
    __slots__ = ("outputs", "workspaces", "windows", "focused_output", "by_hw")

    def __init__(self) -> None:
        self.outputs: dict[str, Out] = {}
        self.workspaces: dict[str, Ws] = {}
        self.windows: dict[int, Win] = {}
        self.focused_output: str | None = None
        self.by_hw: dict[str, Out] = {}

    @classmethod
    def from_tree(cls, tree: dict[str, Any]) -> "World":
        w = cls()
        for o in tree.get("nodes", ()):
            name = o.get("name") or ""
            if name == "__i3":
                continue  # scratchpad: hidden scratchpad windows are no one's
            out = Out(name=name, hw=hw_of(o), rect=_rect(o.get("rect")), area=_rect(o.get("rect")),
                      visible_ws=o.get("current_workspace"))
            w.outputs[name] = out
            w.by_hw[out.hw] = out
            if o.get("focused"):
                w.focused_output = name
            for ws in o.get("nodes", ()):
                if ws.get("type") != "workspace":
                    continue
                wsname = ws.get("name") or ""
                w.workspaces[wsname] = Ws(name=wsname, num=ws.get("num") if isinstance(ws.get("num"), int) and ws.get("num") >= 0 else None, output=name)
                if wsname == out.visible_ws:
                    out.area = _rect(ws.get("rect"))
                if ws.get("focused"):
                    w.focused_output = name
                # iterative walk: trees are shallow but recursion per node costs more
                stack = [(c, False) for c in ws.get("nodes", ())] + [(c, True) for c in ws.get("floating_nodes", ())]
                while stack:
                    n, fl = stack.pop()
                    if n.get("focused"):
                        w.focused_output = name
                    props = n.get("window_properties")
                    if n.get("app_id") is not None or props:
                        props = props or {}
                        w.windows[n["id"]] = Win(
                            id=n["id"], app_id=n.get("app_id"), cls=props.get("class"), title=n.get("name"),
                            window_type=props.get("window_type"), transient=bool(props.get("transient_for")),
                            shell=n.get("shell"), ws=wsname, output=name, floating=fl or n.get("type") == "floating_con",
                            fullscreen=int(n.get("fullscreen_mode") or 0), sticky=bool(n.get("sticky")),
                            pinned=bool(n.get("pinned")), rect=_rect(n.get("rect")), focused=bool(n.get("focused")),
                            instance=props.get("instance"), window_role=props.get("window_role"), pid=n.get("pid"),
                            marks=list(n.get("marks") or ()))
                    for c in n.get("nodes", ()):
                        stack.append((c, fl))
                    for c in n.get("floating_nodes", ()):
                        stack.append((c, True))
        if w.focused_output is None and w.outputs:
            w.focused_output = next(iter(w.outputs))
        return w

    def focused(self) -> Out | None:
        return self.outputs.get(self.focused_output or "")

    def ws_area(self, ws: str) -> Rect | None:
        x = self.workspaces.get(ws)
        o = self.outputs.get(x.output) if x else None
        return o.area if o else None


# --------------------------------------------------------------------------
# identity, eligibility

_TITLE_RX: dict[str, re.Pattern] = {}


def identity(win: Win, title_keys: dict[str, list[str]] | None = None) -> str | None:
    base = win.app_id or win.cls
    if not base:
        return None
    for rx in (title_keys or {}).get(base, ()):
        pat = _TITLE_RX.get(rx)
        if pat is None:
            try:
                pat = _TITLE_RX[rx] = re.compile(rx)
            except re.error:
                continue
        if win.title and pat.search(win.title):
            return f"{base} ~{rx}"
    return base


# Claude's live hand tests (tests/live) open windows with this app_id prefix; remembering them
# restored a test window onto another workspace and its 2 s verify undid a test's own move
# (DESK 2026-10-14), and the daemon's debounced save re-added them after a CLI forget.
TEST_APP_PREFIX = "handtest."


def skip_reason(win: Win, key: str | None, exclude: Iterable[str], rule_placed: bool) -> str | None:
    """Why this window is neither remembered nor restored (None = eligible)."""
    if key is None:
        return "no app identity"
    if GAME_RX.match(key) or (win.cls and GAME_RX.match(win.cls)):
        return "game"
    if key in exclude or (win.app_id or win.cls) in exclude:
        return "excluded"
    if (win.app_id or "").startswith(TEST_APP_PREFIX):
        return "test window"
    if win.sticky or win.pinned:
        return "sticky/pinned"
    if win.transient or (win.window_type or "").lower() in DIALOG_TYPES:
        return "dialog"
    if rule_placed:
        return "placed by a rule"
    return None


PLACING_ACTIONS = re.compile(r"^(floating|sticky|fullscreen|resize|move|workspace|output|assign)\b")


def rule_places(kind: str, actions: Iterable[str]) -> bool:
    if kind == "assign":
        return True
    if kind != "for_window":
        return False
    return any(PLACING_ACTIONS.match(a.strip()) for a in actions)


# --------------------------------------------------------------------------
# journal

def record_of(win: Win, world: World, role_of: Callable[[str], str]) -> dict[str, Any]:
    out = world.outputs.get(win.output)
    rec: dict[str, Any] = {"workspace": win.ws, "floating": win.floating, "output": role_of(out.hw) if out else ""}
    if win.floating and out:
        a = out.area
        rec["rect"] = [win.rect[0] - a[0], win.rect[1] - a[1], win.rect[2], win.rect[3]]
    if win.cls and not win.app_id:
        rec["x11"] = True
    return rec


def same_record(a: dict[str, Any] | None, b: dict[str, Any] | None) -> bool:
    if a is None or b is None:
        return a is b
    return all(a.get(k) == b.get(k) for k in ("workspace", "floating", "output", "rect"))


@dataclass(slots=True)
class Restore:
    command: str
    ws: str | None          # None: size only
    rect: Rect | None       # floating target (x, y, w, h); size only: (0, 0, w, h)

    def again(self) -> str:
        """Re-ask after the client's first commit overrode the size (see Tracker._verify)."""
        if self.rect is None:
            return ""
        if self.ws is None:
            return f"resize set {self.rect[2]} {self.rect[3]}"
        x, y, w, h = self.rect
        return f"resize set {w} {h}, move absolute position {x} {y}, move --no-auto-back-and-forth container to workspace {quote(self.ws)}"

    def reached(self, win: Win) -> bool:
        if self.rect is None:
            return True
        if self.ws is None:
            return win.rect[2:] == self.rect[2:]
        return win.rect == self.rect and win.ws == self.ws


def restore_command(win: Win, rec: dict[str, Any], world: World, output_for_role: Callable[[str], str | None],
                    pinned_output: Callable[[str], str | None], size_only: bool) -> Restore | None:
    """The ONE command restoring rec on a freshly mapped window (AkuWM RecallApp:
    size clamped to the output, position clamped inside)."""
    floating = bool(rec.get("floating")) and rec.get("rect")
    if size_only:
        if not floating:
            return None
        area = world.outputs[win.output].area if win.output in world.outputs else None
        if area is None:
            return None
        w, h = min(int(rec["rect"][2]), area[2]), min(int(rec["rect"][3]), area[3])
        return Restore(f"floating enable, resize set {w} {h}", None, (0, 0, w, h))
    ws = str(rec.get("workspace") or "")
    if not ws or ws == SCRATCH:
        ws = win.ws
    target = (world.workspaces[ws].output if ws in world.workspaces else None) or pinned_output(ws) \
        or output_for_role(str(rec.get("output") or "")) or win.output
    out = world.outputs.get(target) or world.outputs.get(win.output)
    parts: list[str] = []
    rect = None
    if floating and out is not None:
        dx, dy, w, h = (int(v) for v in rec["rect"])
        a = out.area
        rect = clamp_into((a[0] + dx, a[1] + dy, w, h), a)
        parts += ["floating enable", f"resize set {rect[2]} {rect[3]}", f"move absolute position {rect[0]} {rect[1]}"]
    elif not rec.get("floating") and win.floating:
        parts.append("floating disable")
    if ws != win.ws or parts:
        parts.append(f"move --no-auto-back-and-forth container to workspace {quote(ws)}")
    return Restore(", ".join(parts), ws, rect) if parts else None


# --------------------------------------------------------------------------
# bring off-screen

def offscreen_plan(world: World) -> list[tuple[int, str]]:
    host = world.focused()
    if host is None:
        return []
    areas = [o.rect for o in world.outputs.values()]
    plan = []
    for w in world.windows.values():
        if not w.floating or w.fullscreen or w.ws == SCRATCH or not offscreen(w.rect, areas):
            continue
        x, y, nw, nh = clamp_into(w.rect, host.area)
        cmd = f"move absolute position {x} {y}"
        if (nw, nh) != (w.rect[2], w.rect[3]):
            cmd = f"resize set {nw} {nh}, " + cmd
        plan.append((w.id, cmd))
    return plan


# --------------------------------------------------------------------------
# loans (AkuWM Desk.Loans): a source lends its windows to a host's visible
# workspace; the return takes back each window "still where the loan put it,
# and still there at all; anything else was the person's doing since, and stands".

def make_loan(source: str, source_hw: str, host: Out, reason: str, epoch: str,
              items: list[tuple[Win, Rect | None, Rect | None]], host_ws: str | None = None) -> tuple[dict[str, Any], list[tuple[int, str]]]:
    """items: (window, its rect at home or None, the home output's usable area or None).
    host_ws: the workspace to lend to (default: the host's visible one)."""
    host_ws = host_ws or host.visible_ws or ""
    entries, plan = [], []
    move = f"move --no-auto-back-and-forth container to workspace {quote(host_ws)}"
    for win, home_rect, home_area in items:
        if win.ws == host_ws:
            continue
        e: dict[str, Any] = {"id": win.id, "home": win.ws, "floating": win.floating, "fullscreen": win.fullscreen,
                             "sticky": win.sticky, "lent_ws": host_ws}
        if win.fullscreen:
            # AkuWM: "A window that covered its screen floats on the host"
            plan.append((win.id, f"fullscreen disable, floating enable, {move}"))
        elif win.floating:
            r = home_rect or win.rect
            src = home_area or r
            e["rel"] = fraction_of(r, src)
            x, y, w, h = map_rect(r, src, host.area)
            plan.append((win.id, f"{move}, resize set {w} {h}, move absolute position {x} {y}"))
        else:
            plan.append((win.id, move))
        entries.append(e)
    loan = {"source": source, "source_hw": source_hw, "host": host.hw, "host_output": host.name, "host_ws": host_ws,
            "reason": reason, "epoch": epoch, "at": int(time.time()), "windows": entries}
    return loan, plan


def still_lent(e: dict[str, Any], world: World, loan: dict[str, Any]) -> bool:
    w = world.windows.get(int(e["id"]))
    if w is None:
        return False
    if e.get("sticky") or w.sticky:
        # sticky follows its output's visible workspace: where the loan put it = that output
        return w.output == loan.get("host_output") or w.ws == e.get("lent_ws")
    return w.ws == e.get("lent_ws")


def reclaim_plan(loan: dict[str, Any], world: World, source_output: str | None,
                 pinned_output: Callable[[str], str | None]) -> tuple[list[tuple[int, str]], list[str], list[int]]:
    """(per-window commands, runtime workspace pins needed, ids left where they are)."""
    plan: list[tuple[int, str]] = []
    pins: list[str] = []
    stays: list[int] = []
    src = world.outputs.get(source_output or "")
    for e in loan.get("windows", ()):
        cid = int(e["id"])
        if not still_lent(e, world, loan):
            stays.append(cid)
            continue
        w = world.windows[cid]
        home = str(e.get("home") or "")
        target = world.workspaces[home].output if home in world.workspaces else pinned_output(home)
        if target is None and src is not None:
            # A workspace sway emptied away is gone; created now it would land on the
            # FOCUSED output (workspace_get_initial_output), so pin it first.
            target = src.name
            if home not in pins:
                pins.append(home)
        out = world.outputs.get(target or "") or src
        move = f"move --no-auto-back-and-forth container to workspace {quote(home)}"
        if e.get("fullscreen"):
            plan.append((cid, ("floating enable, " if e.get("floating") else "floating disable, ") + move + ", fullscreen enable"))
        elif e.get("floating") and e.get("rel") and out is not None:
            x, y, ww, hh = from_fraction(e["rel"], out.area)
            plan.append((cid, f"floating enable, resize set {ww} {hh}, move absolute position {x} {y}, {move}"))
        else:
            plan.append((cid, ("floating disable, " if w.floating and not e.get("floating") else "") + move))
    return plan, pins, stays


def resolve_policy(cfg: dict[str, Any], role: str | None, hw: str | None = None) -> str:
    monitors = cfg.get("monitors") or {}
    for k in (role, hw):
        if k and monitors.get(k) in POLICIES:
            return monitors[k]
    d = cfg.get("default")
    return d if d in POLICIES else "ignore"
