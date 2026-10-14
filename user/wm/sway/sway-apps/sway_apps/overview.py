"""Window overview (SWAY-15): Hyper+Tab opens a Task-View-style panel per output.

GTK-free half: the card model built from get_tree, keyboard navigation, the
thumbnail cache, grim argv, the control socket protocol and the CLI. The
resident GTK4 layer-shell process is overview_app.py (`sway-apps overview run`,
service sway-apps-overview).

Previews are CACHED snapshots: sway 1.11 / wlroots 0.19 expose only output
capture (per-toplevel capture arrives with wlroots 0.20) and windows on hidden
workspaces are not drawn. A window is captured 1 s after it gains focus (still
focused, visible, not fullscreen, not excluded) and again when it loses focus
after holding it that long. Optionally (live_capture_ms > 0) visible windows are
re-captured when the overview opens, BEFORE the panels map (a capture after
mapping would contain the overlay). Nothing is captured while a fullscreen
window has focus.

grim captures at the output's own scale and the process downscales: grim's own
-s resampling is the slow path. Measured DESK 2026-10-14 (4K@1.5 + QHD@1.25):
`-s 0.25` of a whole output 618 ms (DP-1) / 300 ms (DP-2) whatever the format;
at the output scale 75-100 ms per output, 40-50 ms per window, plus ~15 ms
load+scale in GdkPixbuf.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import socket
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

SETTINGS_KEY = "overview"
SETTINGS_DEFAULTS: dict = {
    "enabled": True,
    "thumbnails": True,
    "thumb_scale": 0.25,          # grim -s: thumbnail px per logical px
    "jpeg_quality": 75,
    "capture_delay_ms": 1000,     # focus -> capture debounce
    # open waits at most this long for live captures of the visible windows; 0 = cached only.
    # 0 by default: a native capture of one output alone takes 75-100 ms on DESK, so any
    # useful wait doubles the open time (measured 2026-10-14: ~10 ms cached vs 110-145 ms)
    # for windows that are on screen anyway.
    "live_capture_ms": 0,
    "card_width": 260,            # logical px of a thumbnail
    # app_id / class regexes never captured (games, password managers).
    "exclude": ["^steam_app_", "^gamescope$", "(?i)keepassxc", "(?i)bitwarden", "(?i)1password"],
}

NOP = "nop sway-apps overview"
ACTIONS = ("toggle", "show", "hide", "state")
CARD_GAP = 16
PANEL_MARGIN = 48


# --------------------------------------------------------------------------
# model

@dataclass(slots=True)
class Card:
    id: int
    app_id: str
    title: str
    workspace: str
    output: str
    focused: bool
    visible: bool
    fullscreen: bool
    floating: bool
    x: int
    y: int
    w: int
    h: int
    pid: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "app_id": self.app_id, "title": self.title, "workspace": self.workspace,
                "output": self.output, "focused": self.focused, "visible": self.visible,
                "fullscreen": self.fullscreen, "floating": self.floating, "rect": [self.x, self.y, self.w, self.h]}


@dataclass(slots=True)
class Group:
    workspace: str
    num: int | None
    visible: bool
    cards: list[Card] = field(default_factory=list)
    focused: bool = False          # sway's focus is on this workspace (window or the empty ws)


@dataclass(slots=True)
class OutputView:
    name: str
    x: int
    y: int
    w: int
    h: int
    scale: float
    focused: bool
    groups: list[Group] = field(default_factory=list)

    def cards(self) -> list[Card]:
        return [c for g in self.groups for c in g.cards]


def _app_id(node: dict[str, Any]) -> str:
    if node.get("app_id"):
        return node["app_id"]
    props = node.get("window_properties") or {}
    return props.get("class") or props.get("instance") or ""


def _views(node: dict[str, Any], out: list[dict[str, Any]], floating: bool) -> None:
    kids = node.get("nodes") or []
    flt = node.get("floating_nodes") or []
    if not kids and not flt and node.get("type") in ("con", "floating_con") and node.get("pid"):
        node["_floating"] = floating
        out.append(node)
        return
    for c in kids:
        _views(c, out, floating)
    for c in flt:
        _views(c, out, True)


def _has_focus(node: dict[str, Any]) -> bool:
    if node.get("focused"):
        return True
    for c in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
        if _has_focus(c):
            return True
    return False


def _focus_chain(tree: dict[str, Any]) -> set[int]:
    """Ids on sway's focus path (each node's focus stack, first entry). Measured on sway
    1.11: while the overview's EXCLUSIVE layer surface holds the keyboard no node has
    focused=true, but the focus stacks still name the focused output/workspace/window."""
    ids: set[int] = set()
    n = tree
    while True:
        f = n.get("focus") or []
        if not f:
            return ids
        n = next((c for c in (n.get("nodes") or []) + (n.get("floating_nodes") or []) if c.get("id") == f[0]), None)
        if n is None:
            return ids
        ids.add(n["id"])


def build(tree: dict[str, Any]) -> list[OutputView]:
    """Outputs left to right (then top to bottom); per output one column per workspace
    by number, named ones last (Diego 2026-10-14: workspaces as columns in their spatial
    order, not the visible one first); per workspace tiles in tree order, then floats.
    Empty workspaces are left out unless on screen (Hyper+Q/W/N into an empty one must
    still show where focus went); the scratchpad always is."""
    views: list[OutputView] = []
    chain = _focus_chain(tree)    # empty for trees without focus stacks (unit fixtures): flags then
    for o in tree.get("nodes") or []:
        name = o.get("name") or ""
        if name == "__i3" or o.get("type") != "output":
            continue
        r = o.get("rect") or {}
        current = o.get("current_workspace")
        ov = OutputView(name, r.get("x", 0), r.get("y", 0), r.get("width", 0), r.get("height", 0),
                        float(o.get("scale") or 1.0), False)
        for ws in o.get("nodes") or []:
            if ws.get("type") != "workspace":
                continue
            wsfocus = ws.get("id") in chain if chain else _has_focus(ws)
            if wsfocus:
                ov.focused = True
            leaves: list[dict[str, Any]] = []
            _views(ws, leaves, False)
            wsname = ws.get("name") or ""
            if not leaves and wsname != current:
                continue
            g = Group(wsname, ws.get("num") if isinstance(ws.get("num"), int) and ws.get("num") >= 0 else None,
                      wsname == current, focused=wsfocus)
            for n in leaves:
                rr = n.get("rect") or {}
                wr = n.get("window_rect") or {}
                g.cards.append(Card(
                    id=n["id"], app_id=_app_id(n), title=n.get("name") or "", workspace=wsname, output=name,
                    focused=n["id"] in chain if chain else bool(n.get("focused")), visible=bool(n.get("visible")),
                    fullscreen=bool(n.get("fullscreen_mode")), floating=n["_floating"],
                    x=rr.get("x", 0) + wr.get("x", 0), y=rr.get("y", 0) + wr.get("y", 0),
                    w=wr.get("width") or rr.get("width", 0), h=wr.get("height") or rr.get("height", 0),
                    pid=n.get("pid") or 0))
            ov.groups.append(g)
        ov.groups.sort(key=lambda g: (g.num is None, g.num if g.num is not None else 0, g.workspace))
        views.append(ov)
    views.sort(key=lambda v: (v.x, v.y))
    return views


def focused_card(views: Iterable[OutputView]) -> Card | None:
    for v in views:
        for c in v.cards():
            if c.focused:
                return c
    return None


def blocked(views: list[OutputView], force: bool = False) -> bool:
    """The fullscreen guard: a focused fullscreen window (a game) keeps the overview shut."""
    if force:
        return False
    c = focused_card(views)
    return bool(c and c.fullscreen)


# --------------------------------------------------------------------------
# navigation: selection is a con_id. Columns = workspaces, rows = their windows.
# Up/Down stay in the column; Left/Right go to the neighbour column at the same row
# (clamped) and cross to the next output at the edge; Tab walks every card in order.

CARD_CHROME = 2 * 10 + 2 * 10   # card padding + border, then the column padding (CSS .sa-ov-card/.sa-ov-col)
MIN_CARD_WIDTH = 140


def fit_card_width(width: int, card_width: int, ncols: int) -> int:
    """Shrink the thumbnails so every workspace column fits the output; below
    MIN_CARD_WIDTH the panel scrolls sideways instead."""
    if ncols <= 0:
        return card_width
    fit = (width - 2 * PANEL_MARGIN + CARD_GAP) // ncols - CARD_CHROME - CARD_GAP
    return max(MIN_CARD_WIDTH, min(card_width, fit))


def initial_selection(views: list[OutputView]) -> int | None:
    c = focused_card(views)
    if c:
        return c.id
    for v in views:
        if v.focused and v.cards():
            return v.cards()[0].id
    for v in views:
        if v.cards():
            return v.cards()[0].id
    return None


def signature(views: list[OutputView]) -> tuple:
    """What the panels draw, minus the selection: equal signatures need no re-render."""
    return tuple((v.name, tuple((g.workspace, g.visible, g.focused, tuple(c.id for c in g.cards)) for g in v.groups))
                 for v in views)


def focused_workspace(views: list[OutputView]) -> str | None:
    for v in views:
        for g in v.groups:
            if g.focused:
                return g.workspace
    return None


def move(views: list[OutputView], sel: int | None, direction: str) -> int | None:
    cols = [[c.id for c in g.cards] for v in views for g in v.groups if g.cards]
    order = [i for col in cols for i in col]
    if not order:
        return None
    if sel not in order:
        return initial_selection(views)
    if direction in ("next", "prev"):
        i = order.index(sel) + (1 if direction == "next" else -1)
        return order[i % len(order)]
    ci = next(i for i, col in enumerate(cols) if sel in col)
    row = cols[ci].index(sel)
    if direction in ("up", "down"):
        r = row + (1 if direction == "down" else -1)
        return cols[ci][max(0, min(len(cols[ci]) - 1, r))]
    c2 = ci + (1 if direction == "right" else -1)
    if not 0 <= c2 < len(cols):
        return sel
    return cols[c2][min(row, len(cols[c2]) - 1)]


# --------------------------------------------------------------------------
# thumbnails

def cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "sway-apps" / "thumbs"


def session_key(sock_path: str | None) -> str:
    """Con ids restart at 1 with every sway: thumbnails are kept per compositor
    instance (the pid in sway-ipc.<uid>.<pid>.sock) so a new session never shows
    the old session's pixels for a reused id."""
    name = os.path.basename(sock_path or "")
    m = re.fullmatch(r"sway-ipc\.\d+\.(\d+)\.sock", name)
    if m:
        return m.group(1)
    return re.sub(r"[^A-Za-z0-9_.-]", "_", name) or "default"


def thumb_path(root: Path, session: str, con_id: int) -> Path:
    return root / session / f"{con_id}.jpg"


def prune(root: Path, session: str, live_ids: set[int]) -> list[str]:
    """Drop other sessions' directories and this session's thumbnails of closed windows."""
    removed: list[str] = []
    try:
        entries = list(root.iterdir())
    except OSError:
        return removed
    for d in entries:
        if d.name != session:
            shutil.rmtree(d, ignore_errors=True)
            removed.append(d.name + "/")
    try:
        files = list((root / session).iterdir())
    except OSError:
        return removed
    for f in files:
        stem = f.name.split(".", 1)[0]
        if not stem.isdigit() or int(stem) not in live_ids or not f.name.endswith(".jpg"):
            try:
                f.unlink()
                removed.append(f.name)
            except OSError:
                pass
    return removed


def remove_thumb(root: Path, session: str, con_id: int) -> bool:
    try:
        thumb_path(root, session, con_id).unlink()
        return True
    except OSError:
        return False


def exclusion_matcher(settings: dict[str, Any]):
    pats = [p for p in settings.get("exclude") or [] if isinstance(p, str) and p]
    if not pats:
        return lambda _app: False
    # One regex per pattern: a joined "a|(?i)b" is a re.error since Python 3.11
    # (global flags only at the start), which silently excluded nothing.
    rxs = []
    for p in pats:
        try:
            rxs.append(re.compile(p))
        except re.error:
            rxs.append(re.compile(re.escape(p)))
    return lambda app: bool(app) and any(rx.search(app) for rx in rxs)


def capturable(card: Card, excluded) -> bool:
    return card.visible and not card.fullscreen and card.w >= 16 and card.h >= 16 and not excluded(card.app_id)


def grim_argv(grim: str, x: int, y: int, w: int, h: int, out_scale: float, fmt: str, out: str) -> list[str]:
    """A capture at the output's own scale (no resampling in grim). fmt: ppm, or png at
    level 0 when gdk-pixbuf lacks the PNM loader."""
    return [grim, "-g", f"{x},{y} {w}x{h}", "-s", f"{out_scale:g}", "-t", fmt] + (["-l", "0"] if fmt == "png" else []) + [out]


def grim_window_argv(grim: str, card: Card, out_scale: float, fmt: str, out: str) -> list[str]:
    return grim_argv(grim, card.x, card.y, card.w, card.h, out_scale, fmt, out)


def grim_output_argv(grim: str, view: OutputView, fmt: str, out: str) -> list[str]:
    return grim_argv(grim, view.x, view.y, view.w, view.h, view.scale, fmt, out)


def thumb_size(w: int, h: int, thumb_scale: float) -> tuple[int, int]:
    """Thumbnail pixels for a w x h logical-px window."""
    return max(1, round(w * thumb_scale)), max(1, round(h * thumb_scale))


def crop_box(card: Card, view: OutputView, scale: float, img_w: int, img_h: int) -> tuple[int, int, int, int] | None:
    """The card's window inside an output capture taken at `scale`, clamped to the image."""
    x0 = max(0, round((card.x - view.x) * scale))
    y0 = max(0, round((card.y - view.y) * scale))
    x1 = min(img_w, round((card.x + card.w - view.x) * scale))
    y1 = min(img_h, round((card.y + card.h - view.y) * scale))
    if x1 - x0 < 4 or y1 - y0 < 4:
        return None
    return x0, y0, x1 - x0, y1 - y0


# --------------------------------------------------------------------------
# control socket (CLI -> resident process). `swaymsg nop …` emits no binding
# event, so the CLI cannot go through sway.

def selection_file() -> str:
    """While the overview is open: the selected con_id, read by the workspace bindings'
    wrapper (user/wm/sway/scripts/overview-selected.sh) to act on that window. Absent when
    closed, so the bindings pay one `test -s`."""
    explicit = os.environ.get("SWAY_APPS_OVERVIEW_SEL")
    if explicit:
        return explicit
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, "sway-apps-overview.sel")


def control_socket() -> str:
    explicit = os.environ.get("SWAY_APPS_OVERVIEW_SOCK")
    if explicit:
        return explicit
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, "sway-apps-overview.sock")


def parse_request(line: str) -> tuple[str, bool]:
    parts = line.split()
    action = parts[0] if parts and parts[0] in ACTIONS else "toggle"
    return action, "--force" in parts


def request(action: str, force: bool = False, timeout: float = 3.0) -> dict[str, Any]:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(control_socket())
        s.sendall(f"{action}{' --force' if force else ''}\n".encode())
        s.shutdown(socket.SHUT_WR)
        buf = bytearray()
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    finally:
        s.close()
    return json.loads(buf or b"{}")


# --------------------------------------------------------------------------
# watch daemon + CLI

def setup_watch(reg) -> None:
    # The resident overview process consumes the binding; this keeps the watch
    # daemon from logging "no handler for verb" on every Hyper+Tab.
    reg.verb("overview", lambda _args, _ctx: None)


def register_cli(sub) -> None:
    p = sub.add_parser("overview", help="Hyper+Tab window overview (resident process: sway-apps-overview)")
    p.add_argument("action", nargs="?", default="toggle", choices=ACTIONS + ("run",),
                   help="toggle/show/hide the overview, dump its state, or run the resident process")
    p.add_argument("--force", action="store_true", help="open even when the focused window is fullscreen")
    p.set_defaults(func=_cmd)


def _cmd(a) -> int:
    from . import cli
    if a.action == "run":
        from . import overview_app
        return overview_app.main()
    try:
        res = request(a.action, a.force)
    except (OSError, ValueError) as exc:
        cli._out(a, {"ok": False, "error": f"overview process not reachable at {control_socket()}: {exc}"},
                 lambda: print(f"overview process not reachable ({exc}); is sway-apps-overview.service running?"))
        return 1
    cli._out(a, res, lambda: print(json.dumps(res, indent=2)))
    return 0 if res.get("ok", True) else 1
