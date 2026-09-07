"""Launch a tool and make its window float on top: a generated for_window rule
(floating + sticky + focus) covers windows opened from a key binding, and the
live placement below covers the sidebar / `tools run` path even when
app-toggle.sh restores a window that was tiled."""
from __future__ import annotations

import re
import threading
import time
from typing import Any

from . import log, swayipc
from .state import State, Tool

_log = log.get("toolrun")

FLOAT_ACTIONS = "floating enable, sticky enable, focus"
POLL = 0.25


def criteria_for(tool: Tool) -> list[dict[str, str]]:
    """Criteria sets that identify the tool's window, mirroring app-toggle.sh:
    `title:^regex` matches the title (regex, as given); anything else is an exact
    app_id (Wayland) or class (X11), so it is anchored and regex-escaped."""
    ident = tool.app_id.strip()
    if not ident:
        return []
    if ident.startswith("title:"):
        rx = ident[len("title:"):]
        return [{"title": rx}] if rx else []
    anchored = "^" + _ere_escape(ident) + "$"
    return [{"app_id": anchored}, {"class": anchored}]


_ERE_SPECIALS = set(".^$*+?()[]{}|\\")


def _ere_escape(text: str) -> str:
    """Escape for sway's POSIX ERE (re.escape would also escape '-' and ' ', which ERE treats as undefined)."""
    return "".join("\\" + ch if ch in _ERE_SPECIALS else ch for ch in text)


def _render_criteria(c: dict[str, str]) -> str:
    return "[" + " ".join(f'{k}="{v}"' for k, v in c.items()) + "]"


def render_rules(state: State) -> str:
    """The include block: one for_window per criteria set of every enabled floating tool."""
    lines: list[str] = []
    for t in state.tools():
        if not (t.enabled and t.float):
            continue
        crits = criteria_for(t)
        if not crits:
            continue
        lines.append(f"# {t.name} [{t.id}]")
        for c in crits:
            lines.append(f"for_window {_render_criteria(c)} {FLOAT_ACTIONS}")
    if not lines:
        return ""
    return "\n# ---- Tool windows: floating, sticky, on top (tools with float=on)\n" + "\n".join(lines) + "\n"


def matching(tool: Tool) -> list[swayipc.Window]:
    crits = criteria_for(tool)
    if not crits:
        return []
    return [w for w in swayipc.windows() if any(swayipc.window_matches(w, c) for c in crits)]


def launch(tool: Tool, timeout: float = 8.0) -> dict[str, Any]:
    """exec the tool (focus-or-launch), wait for its window, float it on top.
    Never touches any other window (the sway-apps window stays where it is)."""
    before = {w.id for w in matching(tool)}
    res: dict[str, Any] = {"tool": tool.id, "command": tool.launch_command(), "con_id": None, "new": False, "placed": False}
    swayipc.exec_(tool.launch_command())
    if not tool.float or not criteria_for(tool):
        return res
    deadline = time.monotonic() + timeout
    win: swayipc.Window | None = None
    while time.monotonic() < deadline:
        found = matching(tool)
        new = [w for w in found if w.id not in before]
        if new:
            win = new[0]; res["new"] = True; break
        # no new window: app-toggle showed / focused an existing one -> place it once it is visible
        vis = [w for w in found if w.visible]
        if vis and time.monotonic() > deadline - timeout + 1.0:
            win = vis[0]; break
        time.sleep(POLL)
    if win is None:
        _log.warning("tool %s: no window matched %s within %.0fs", tool.id, criteria_for(tool), timeout)
        return res
    res["con_id"] = win.id
    try:
        swayipc.command(f"[con_id={win.id}] {FLOAT_ACTIONS}")
        res["placed"] = True
        _log.info("tool %s: con %s floated on top (%s)", tool.id, win.id, "new" if res["new"] else "existing")
    except Exception as exc:  # noqa: BLE001
        _log.warning("tool %s: placing con %s failed: %s", tool.id, win.id, exc)
    return res


def launch_async(tool: Tool, done=None) -> threading.Thread:
    """GUI helper: run launch() off the main loop."""
    def worker():
        try:
            r = launch(tool)
        except Exception as exc:  # noqa: BLE001
            _log.warning("tool %s launch failed: %s", tool.id, exc)
            r = {"error": str(exc)}
        if done:
            done(r)
    th = threading.Thread(target=worker, daemon=True)
    th.start()
    return th
