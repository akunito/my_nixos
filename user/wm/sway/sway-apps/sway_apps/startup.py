"""Manual startup runner: launch, wait for the window, place it."""
from __future__ import annotations

import re
import time
from typing import Callable

from . import log, swayipc
from .state import StartupEntry, State
from .discover import learn

_log = log.get("startup")

Progress = Callable[[str], None]


def _matching_ids(app_id_rx: str) -> set[int]:
    if not app_id_rx:
        return set()
    return {w.id for w in swayipc.windows() if swayipc.window_matches(w, {"app_id": app_id_rx})}


def _all_ids() -> set[int]:
    return {w.id for w in swayipc.windows()}


def _workspace_of(con_id: int) -> str | None:
    for w in swayipc.windows():
        if w.id == con_id:
            return w.workspace
    return None


def _place(con_id: int, workspace: str) -> bool:
    """Move only when needed: a redundant move re-attaches the container and
    drags the next moved window along (measured on DESK 2026-09-02)."""
    target = workspace.strip()
    ws_cmd = f"workspace number {target}" if re.fullmatch(r"\d+", target) else f"workspace {target}"
    for _ in range(5):
        cur = _workspace_of(con_id)
        if cur is None:
            return False
        if cur == target or (target.isdigit() and cur.split(":")[0] == target):
            return True
        try:
            swayipc.command(f"[con_id={con_id}] move container to {ws_cmd}")
        except swayipc.SwayError as exc:
            if "sticky" in str(exc).lower():
                # sway refuses to move a sticky container between workspaces of
                # the same output (the app has a `sticky enable` rule). Lift the
                # flag for the move and put it back.
                try:
                    swayipc.command(f"[con_id={con_id}] sticky disable, move container to {ws_cmd}, sticky enable")
                    _log.info("move %s -> %s done with sticky lifted", con_id, target)
                except swayipc.SwayError as exc2:
                    _log.warning("move %s -> %s failed even with sticky lifted: %s", con_id, target, exc2)
            else:
                _log.warning("move %s -> %s failed: %s", con_id, target, exc)
        time.sleep(0.5)
    return _workspace_of(con_id) == target


def run_entry(entry: StartupEntry, progress: Progress | None = None) -> dict:
    say = progress or (lambda s: None)
    with log.action("startup.run_entry", id=entry.id, name=entry.name, command=entry.command) as res:
        known = _matching_ids(entry.app_id) if entry.app_id else _all_ids()
        if entry.app_id and known:
            # Already running: adopt its windows instead of waiting for new ones.
            say(f"{entry.name}: already running, adopting {len(known)} window(s)")
            new_ids = set(known)
            res["adopted"] = True
        else:
            say(f"{entry.name}: launching")
            swayipc.exec_(entry.command)
            new_ids = set()
            deadline = time.monotonic() + max(0, entry.wait_seconds)
            while time.monotonic() < deadline:
                time.sleep(0.5)
                now = _matching_ids(entry.app_id) if entry.app_id else _all_ids()
                new_ids = now - known
                if new_ids:
                    break
            if not new_ids:
                if entry.wait_seconds == 0 or not entry.app_id:
                    res["placed"] = 0
                    return {"id": entry.id, "launched": True, "windows": [], "placed": 0}
                _log.warning("%s: no window matching app_id=%r within %ss", entry.name, entry.app_id, entry.wait_seconds)
                res["timeout"] = True
                return {"id": entry.id, "launched": True, "windows": [], "placed": 0, "timeout": True}
            if entry.settle_seconds > 0:
                time.sleep(entry.settle_seconds)
                now = _matching_ids(entry.app_id) if entry.app_id else _all_ids()
                new_ids = now - known
        if entry.desktop_id or entry.command:
            observed = [w.app_id for w in swayipc.windows() if w.id in new_ids and w.app_id]
            if observed:
                learn(entry.desktop_id or entry.command, observed[0])
        placed = 0
        if entry.workspace:
            for cid in sorted(new_ids):
                if _place(cid, entry.workspace):
                    placed += 1
                    say(f"{entry.name}: window {cid} -> workspace {entry.workspace}")
        res["windows"] = len(new_ids)
        res["placed"] = placed
        return {"id": entry.id, "launched": True, "windows": sorted(new_ids), "placed": placed}


def run(state: State, only: list[str] | None = None, progress: Progress | None = None) -> list[dict]:
    entries = [e for e in state.startup() if e.enabled or (only and e.id in only)]
    if only:
        entries = [e for e in entries if e.id in only or e.name in only]
    results = []
    with log.action("startup.run", count=len(entries)) as res:
        for e in entries:
            if e.problems():
                _log.warning("skipping %s: %s", e.id, "; ".join(e.problems()))
                results.append({"id": e.id, "skipped": True, "problems": e.problems()})
                continue
            try:
                results.append(run_entry(e, progress))
            except swayipc.SwayError as exc:
                _log.error("%s failed: %s", e.name, exc)
                results.append({"id": e.id, "launched": False, "error": str(exc)})
        res["ok"] = sum(1 for r in results if r.get("launched"))
    return results
