"""Placement with IO: machine-local stores, the executor shared by the CLI and
the watch daemon, and the daemon's tracker (journal, rolling snapshot, power-off).
"""
from __future__ import annotations

import json
import os
import re
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from . import ipc, log, paths, swayipc
from .placement_core import (SCRATCH, Rect, Win, World, identity, make_loan, offscreen_plan, quote, reclaim_plan,
                             record_of, resolve_policy, restore_command, rule_places, same_record, skip_reason)

_log = log.get("placement")

KEY = "placement"
JOURNAL_FILE = paths.LOCAL_STATE_DIR / "placement-journal.json"
LOANS_FILE = paths.LOCAL_STATE_DIR / "placement-loans.json"

READ_COALESCE = 0.2   # one get_tree per burst of window events, never one per event
SAVE_DEBOUNCE = 1.0
# Hotplug in nested sway 1.11 (2026-10-14): `output X disable|enable` gives the
# workspace move/init events and ONE output event in the same millisecond. Real
# DRM resumes come in bursts (AkuWM on Windows: 2 s for a change of shape, 6 s
# while a screen is missing). The settle must also outlast watch.OUTPUT_DEBOUNCE
# (1.5 s), whose reconcile sends pinned workspaces home before windows return.
SETTLE_S = 2.0
VERIFY_DELAYS = (0.15, 0.25, 0.4, 0.6, 0.6)  # 2 s in all: AkuWM PlacementPatienceMs
WINDOW_DIRTY = frozenset(("new", "close", "move", "floating", "fullscreen_mode", "focus"))
WORKSPACE_DIRTY = frozenset(("move", "rename"))


def _atomic_write(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime_ns
    except OSError:
        return 0


# --------------------------------------------------------------------------
# settings + rules, re-read only when their files change

class Config:
    def __init__(self) -> None:
        self._stamp: tuple | None = None
        self._state = None
        self._nix_stamp: float | None = None
        self._nix_rules: list[dict[str, str]] = []
        self._rules: list[dict[str, str]] = []

    def state(self):
        from .state import State
        stamp = (_mtime(paths.common_file()), _mtime(paths.profile_file()))
        if self._state is None or stamp != self._stamp:
            try:
                self._state = State()
                self._stamp = stamp
                self._rules = self._state_rules(self._state)
            except RuntimeError as exc:  # half-written JSON: keep the last good copy
                _log.warning("state unreadable, keeping the previous: %s", exc)
                if self._state is None:
                    raise
        return self._state

    def settings(self) -> dict[str, Any]:
        return self.state().feature(KEY)

    @staticmethod
    def _state_rules(st) -> list[dict[str, str]]:
        out = [r.criteria for r in st.resolved_rules() if r.enabled and r.criteria and rule_places(r.kind, r.actions)]
        for e in st.startup():
            if e.enabled and e.app_id and e.workspace:
                out.append({"app_id": e.app_id})
        return out

    def placing_rules(self) -> list[dict[str, str]]:
        self.state()
        cfg = paths.XDG_CONFIG_HOME / "sway" / "config"
        stamp = _mtime(cfg)
        if stamp != self._nix_stamp:
            self._nix_stamp = stamp
            try:
                from .rules import parse_config
                self._nix_rules = [r.criteria for r in parse_config(cfg.read_text()) if r.criteria and rule_places(r.kind, r.actions)]
            except OSError:
                self._nix_rules = []
        return self._rules + self._nix_rules

    def rule_placed(self, w: Win) -> bool:
        sw = swayipc.Window(id=w.id, app_id=w.app_id, title=w.title, cls=w.cls, instance=w.instance, window_role=w.window_role,
                            window_type=w.window_type, shell=w.shell, pid=w.pid, workspace=w.ws, workspace_num=None, output=w.output,
                            floating=w.floating, focused=w.focused, visible=True, sticky=w.sticky, fullscreen=bool(w.fullscreen),
                            marks=w.marks)
        for crit in self.placing_rules():
            if swayipc.window_matches(sw, crit):
                return True
        return False

    # ---- roles ------------------------------------------------------------------
    def role_of(self, hw: str) -> str:
        m = self.state().monitor_by_criteria(hw)
        return m.id if m else hw

    def output_for_role(self, world: World, role: str) -> str | None:
        if not role:
            return None
        m = self.state().monitor(role)
        o = world.by_hw.get(m.criteria if m else role)
        return o.name if o else None

    def pinned_output(self, world: World, ws: str) -> str | None:
        m = re.match(r"^(\d+)", ws)
        mon = self.state().monitor_for_workspace(int(m.group(1))) if m else None
        o = world.by_hw.get(mon.criteria) if mon and mon.enabled else None
        return o.name if o else None

    def owner_of(self, world: World, ws: str) -> tuple[str, str] | None:
        """(source key, hw id) a workspace belongs to: its pinned role, else its output."""
        m = re.match(r"^(\d+)", ws)
        mon = self.state().monitor_for_workspace(int(m.group(1))) if m else None
        if mon and mon.enabled:
            return mon.id, mon.criteria
        w = world.workspaces.get(ws)
        o = world.outputs.get(w.output) if w else None
        return (self.role_of(o.hw), o.hw) if o else None

    def poweroff_policy(self, hw: str) -> str:
        return resolve_policy(self.settings().get("poweroff") or {}, self.role_of(hw), hw)


# --------------------------------------------------------------------------
# machine-local stores

class Journal:
    """{identity: record}. The daemon holds it; CLI/GUI edits land through the
    file and are picked up before the next change (mtime check)."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or JOURNAL_FILE
        self.records: dict[str, dict[str, Any]] = {}
        self._stamp: float | None = None
        self.dirty = False
        self.refresh()

    def refresh(self) -> None:
        stamp = _mtime(self.path)
        if stamp == self._stamp:
            return
        self._stamp = stamp
        try:
            data = json.loads(self.path.read_text())
            self.records = dict(data.get("records") or {})
        except (OSError, ValueError):
            self.records = {}

    def get(self, key: str) -> dict[str, Any] | None:
        self.refresh()
        return self.records.get(key)

    def put(self, key: str, rec: dict[str, Any]) -> bool:
        self.refresh()
        if same_record(self.records.get(key), rec):
            return False
        self.records[key] = dict(rec, updated=int(time.time()))
        self.dirty = True
        return True

    def forget(self, key: str) -> bool:
        self.refresh()
        found = self.records.pop(key, None) is not None
        if found:
            self.dirty = True
        return found

    def save(self) -> None:
        if not self.dirty:
            return
        _atomic_write(self.path, {"version": 1, "records": self.records})
        self._stamp = _mtime(self.path)
        self.dirty = False


def load_loans(epoch: str, path: Path | None = None) -> list[dict[str, Any]]:
    """Loans of this sway instance only: con ids restart with every compositor."""
    try:
        data = json.loads((path or LOANS_FILE).read_text())
    except (OSError, ValueError):
        return []
    return [l for l in data.get("loans") or [] if l.get("epoch") == epoch]


def save_loans(loans: list[dict[str, Any]], path: Path | None = None) -> None:
    _atomic_write(path or LOANS_FILE, {"version": 1, "loans": loans})


# --------------------------------------------------------------------------
# executor (CLI, GUI and daemon verbs)

class Placer:
    def __init__(self, command: Callable[[str], Any], epoch: str, cfg: Config | None = None) -> None:
        self.command = command
        self.epoch = epoch
        self.cfg = cfg or Config()

    @classmethod
    def connect(cls) -> tuple["Placer", ipc.Connection]:
        conn = ipc.Connection()
        return cls(conn.command, conn.path or ""), conn

    def _run(self, cid: int, cmd: str) -> bool:
        try:
            self.command(f"[con_id={cid}] {cmd}")
            return True
        except (ipc.IpcError, swayipc.SwayError, OSError) as exc:
            _log.warning("con %s: %s failed: %s", cid, cmd, exc)
            return False

    def _exec(self, plan: list[tuple[int, str]]) -> int:
        return sum(1 for cid, cmd in plan if self._run(cid, cmd))

    def bring_offscreen(self, world: World) -> dict[str, Any]:
        with log.action("placement.bring_offscreen") as res:
            plan = offscreen_plan(world)
            res["moved"] = self._exec(plan)
            return {"moved": res["moved"], "windows": [cid for cid, _ in plan]}

    def bring_all(self, world: World) -> dict[str, Any]:
        """AkuWM fetch-windows: lend everything here, or give back what is lent."""
        loans = load_loans(self.epoch)
        returnable = [l for l in loans if l.get("source_hw") in world.by_hw]
        if returnable:
            out = {"action": "returned", "loans": []}
            for loan in returnable:
                out["loans"].append(self.reclaim(world, loan))
            save_loans([l for l in loans if l not in returnable])
            return out
        host = world.focused()
        if host is None:
            return {"action": "nothing", "reason": "no focused output"}
        host_key = self.cfg.role_of(host.hw)
        lent_sources = {l.get("source") for l in loans}
        groups: dict[str, tuple[str, list[tuple[Win, Rect | None, Rect | None]]]] = {}
        for w in world.windows.values():
            if w.ws in (SCRATCH, host.visible_ws):
                continue
            owner = self.cfg.owner_of(world, w.ws)
            if owner is None or owner[0] == host_key or owner[0] in lent_sources:
                continue
            area = world.outputs[w.output].area if w.output in world.outputs else None
            groups.setdefault(owner[0], (owner[1], []))[1].append((w, w.rect, area))
        made = []
        with log.action("placement.bring_all", host=host_key) as res:
            for source, (hw, items) in groups.items():
                loan, plan = make_loan(source, hw, host, "bring", self.epoch, items)
                if loan["windows"]:
                    self._exec(plan)
                    made.append(loan)
            res["lent"] = sum(len(l["windows"]) for l in made)
        save_loans(loans + made)
        return {"action": "lent", "host": host_key, "host_ws": host.visible_ws,
                "loans": [{"source": l["source"], "windows": len(l["windows"])} for l in made]}

    def lend(self, world: World, source: str, source_hw: str, items, reason: str) -> dict[str, Any] | None:
        loans = load_loans(self.epoch)
        if any(l.get("source_hw") == source_hw for l in loans):
            return None  # already on loan (AkuWM: _loans.ContainsKey(role))
        host = world.focused()
        if host is None or host.hw == source_hw:
            host = next((o for o in world.outputs.values() if o.hw != source_hw), None)
        if host is None:
            return None  # every screen is gone; there is nowhere to lend to
        loan, plan = make_loan(source, source_hw, host, reason, self.epoch, items)
        if not loan["windows"]:
            return None
        with log.action("placement.lend", source=source, host=host.name, reason=reason) as res:
            res["windows"] = self._exec(plan)
        save_loans(loans + [loan])
        return loan

    def reclaim(self, world: World, loan: dict[str, Any]) -> dict[str, Any]:
        src = world.by_hw.get(loan.get("source_hw", ""))
        plan, pins, stays = reclaim_plan(loan, world, src.name if src else None, lambda ws: self.cfg.pinned_output(world, ws))
        with log.action("placement.reclaim", source=loan.get("source"), reason=loan.get("reason")) as res:
            for ws in pins:
                try:
                    self.command(f"workspace {quote(ws)} output {quote(src.hw if src else '')}")
                except (ipc.IpcError, swayipc.SwayError) as exc:
                    _log.warning("pin %s failed: %s", ws, exc)
            res["returned"] = self._exec(plan)
            res["stayed"] = len(stays)
        return {"source": loan.get("source"), "returned": res["returned"], "stayed": stays}


def reclaim_returned(placer: Placer, world: World, came_back: set[str]) -> list[dict[str, Any]]:
    """Loans whose source is back: power-off loans always, bring loans only on a
    replug (AkuWM: fetched windows also go back when the screen is replugged)."""
    loans = load_loans(placer.epoch)
    done, keep = [], []
    for l in loans:
        hw = l.get("source_hw")
        if hw in world.by_hw and (l.get("reason") == "poweroff" or hw in came_back):
            done.append(placer.reclaim(world, l))
        else:
            keep.append(l)
    if done:
        save_loans(keep)
    return done


# --------------------------------------------------------------------------
# watch daemon

@dataclass(slots=True)
class ConInfo:
    key: str | None
    skip: str | None
    last: dict[str, Any] | None = None
    abs: Rect | None = None
    area: Rect | None = None
    settling: bool = False


class Tracker:
    def __init__(self) -> None:
        self.cfg = Config()
        self.journal = Journal()
        self.cons: dict[int, ConInfo] = {}
        self.snap: dict[str, dict[str, Any]] = {}
        self.baseline: set[str] | None = None
        self.frozen = False
        self._read_pending = False
        self._save_pending = False

    # ---- registry glue --------------------------------------------------------
    def setup(self, reg) -> None:
        reg.on("window", self.on_window)
        reg.on("workspace", self.on_workspace)
        reg.on("output", self.on_output)
        reg.verb("bring", self.on_verb_bring)
        reg.schedule("placement.read", 0.0, self.read)

    def _placer(self, ctx) -> Placer:
        return Placer(ctx.command, ctx.conn.path or "", self.cfg)

    def _dirty(self, ctx) -> None:
        if not self._read_pending:
            self._read_pending = True
            ctx.schedule("placement.read", READ_COALESCE, self.read)

    # ---- events -------------------------------------------------------------------
    def on_window(self, ev: dict[str, Any], ctx) -> None:
        change = ev.get("change")
        if change not in WINDOW_DIRTY:
            return
        if change == "new":
            self.on_new(ev, ctx)
        elif change == "close":
            self.on_close(ev, ctx)
        self._dirty(ctx)

    def on_workspace(self, ev: dict[str, Any], ctx) -> None:
        if ev.get("change") in WORKSPACE_DIRTY:
            self._dirty(ctx)

    def on_output(self, _ev: Any, ctx) -> None:
        # Never snapshot while an output is missing: "recording a layout with a
        # monitor missing would memorise exactly the damage" (AkuWM).
        self.frozen = True
        ctx.schedule("placement.settle", SETTLE_S, self.settle)
        grace = float((self.cfg.settings().get("poweroff") or {}).get("grace_seconds", 5))
        ctx.schedule("placement.grace", max(grace, 0.1), self.grace)

    def on_verb_bring(self, args: list[str], ctx) -> None:
        what = args[0] if args else "offscreen"
        world = World.from_tree(ctx.tree())
        p = self._placer(ctx)
        res = p.bring_all(world) if what == "all" else p.bring_offscreen(world)
        _log.info("bring %s: %s", what, res)

    # ---- journal ------------------------------------------------------------------
    def _settings(self) -> dict[str, Any]:
        return self.cfg.settings()

    def _classify(self, w: Win, s: dict[str, Any]) -> ConInfo:
        j = s.get("journal") or {}
        key = identity(w, s.get("title_keys") or {})
        return ConInfo(key=key, skip=skip_reason(w, key, j.get("exclude") or (), self.cfg.rule_placed(w) if key else False))

    def on_new(self, ev: dict[str, Any], ctx) -> None:
        cid = (ev.get("container") or {}).get("id")
        if cid is None:
            return
        world = World.from_tree(ctx.tree())  # criteria already applied (see placement_core)
        w = world.windows.get(cid)
        if w is None:
            return
        s = self._settings()
        info = self._classify(w, s)
        if info.skip is None and w.fullscreen:
            info.skip = "fullscreen-born"
        if info.skip is None and w.floating:
            info.skip = "born floating (dialog or fixed size)"
        self.cons[cid] = info
        if info.skip:
            return
        # Baseline from this tree, not from the first coalesced read: whatever
        # moves the window within 200 ms of its map (startup, a script, the
        # person) is a change to record.
        out = world.outputs.get(w.output)
        info.last, info.abs, info.area = record_of(w, world, self.cfg.role_of), w.rect, out.area if out else None
        if not (s.get("journal") or {}).get("enabled", True):
            return
        rec = self.journal.get(info.key)
        if not rec:
            return
        size_only = any(o.id != cid and identity(o, s.get("title_keys") or {}) == info.key for o in world.windows.values())
        r = restore_command(w, rec, world, lambda role: self.cfg.output_for_role(world, role),
                            lambda ws: self.cfg.pinned_output(world, ws), size_only)
        if r is None:
            return
        ok = Placer(ctx.command, "", self.cfg)._run(cid, r.command)
        _log.info("restored %s (con %s%s): %s%s", info.key, cid, ", size only" if size_only else "", r.command, "" if ok else " FAILED")
        if ok and not size_only:
            info.last = {k: rec[k] for k in ("workspace", "floating", "output", "rect") if k in rec}
        if ok and r.rect is not None:
            info.settling = True
            self._verify(ctx, cid, r, 0)

    def _verify(self, ctx, cid: int, r, attempt: int) -> None:
        # window:new comes after sway sent the TILED configure. When the client
        # commits at that size, sway sizes the floating con to the commit AND
        # configures the client to it again (view_update_size + set_size in
        # handle_commit), so our resize is lost for good. Measured in nested sway
        # 1.11: a GTK4 window relaunched onto a hidden ws came up 1024x600 instead
        # of 420x260 six runs out of six, sometimes > 400 ms after the restore.
        # So look, and ask again, at every step of AkuWM's placement patience
        # (2 s), not only until it first looks right.
        def check(ctx) -> None:
            info = self.cons.get(cid)
            w = World.from_tree(ctx.tree()).windows.get(cid)
            if info is None or w is None or not w.floating:
                if info is not None:
                    info.settling = False
                return
            if not r.reached(w):
                _log.debug("con %s at %s %s, want %s %s: asking again", cid, w.ws, w.rect, r.ws, r.rect)
                Placer(ctx.command, "", self.cfg)._run(cid, r.again())
            if attempt + 1 < len(VERIFY_DELAYS):
                self._verify(ctx, cid, r, attempt + 1)
                return
            info.settling = False
            if not r.reached(w):
                _log.warning("con %s did not reach %s (is %s %s)", cid, r.rect, w.ws, w.rect)
            self._dirty(ctx)
        ctx.schedule(f"placement.verify.{cid}", VERIFY_DELAYS[attempt], check)

    def on_close(self, ev: dict[str, Any], ctx) -> None:
        c = ev.get("container") or {}
        info = self.cons.pop(c.get("id"), None)
        if info is None or info.skip or info.last is None or info.area is None:
            return
        if c.get("type") != "floating_con" or c.get("fullscreen_mode"):
            return
        r = c.get("rect") or {}
        rect = (int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("width", 0)), int(r.get("height", 0)))
        if rect == info.abs or not rect[2]:
            return
        # Without the stacking patch a drag/resize emits nothing; the close
        # payload is the first place the final rect shows up.
        a = info.area
        rec = dict(info.last, floating=True, rect=[rect[0] - a[0], rect[1] - a[1], rect[2], rect[3]])
        if (self._settings().get("journal") or {}).get("enabled", True) and info.key and self.journal.put(info.key, rec):
            self._schedule_save(ctx)

    def _schedule_save(self, ctx) -> None:
        if not self._save_pending:
            self._save_pending = True
            ctx.schedule("placement.journal.save", SAVE_DEBOUNCE, self._save)

    def _save(self, _ctx) -> None:
        self._save_pending = False
        try:
            self.journal.save()
        except OSError as exc:
            _log.warning("journal write failed: %s", exc)

    # ---- coalesced tree read -----------------------------------------------------------
    def read(self, ctx) -> None:
        self._read_pending = False
        self.observe(World.from_tree(ctx.tree()), ctx)

    def observe(self, world: World, ctx) -> None:
        if self.baseline is None:
            self.baseline = set(world.by_hw)
        s = self._settings()
        if (s.get("journal") or {}).get("enabled", True):
            changed = False
            for w in world.windows.values():
                if w.ws == SCRATCH:
                    continue
                info = self.cons.get(w.id)
                if info is None:
                    info = self.cons[w.id] = self._classify(w, s)
                if info.skip or info.settling or not info.key or w.fullscreen or w.sticky or w.pinned:
                    continue
                out = world.outputs.get(w.output)
                rec = record_of(w, world, self.cfg.role_of)
                first = info.last is None
                if first or not same_record(rec, info.last):
                    info.last = rec
                    if not first:  # first sighting is the baseline, not the person's doing
                        changed = self.journal.put(info.key, rec) or changed
                info.abs = w.rect
                info.area = out.area if out else None
            if changed:
                self._schedule_save(ctx)
        if not self.frozen:
            self._snapshot(world)

    def _snapshot(self, world: World) -> None:
        by_out: dict[str, dict[str, Any]] = {}
        for o in world.outputs.values():
            by_out[o.name] = {"hw": o.hw, "name": o.name, "area": o.area, "role": self.cfg.role_of(o.hw), "windows": {}}
        for w in world.windows.values():
            e = by_out.get(w.output)
            if e is not None and w.ws != SCRATCH:
                e["windows"][w.id] = w.rect
        for e in by_out.values():
            self.snap[e["hw"]] = e

    # ---- power-off ---------------------------------------------------------------------
    def settle(self, ctx) -> None:
        world = World.from_tree(ctx.tree())
        now = set(world.by_hw)
        base = self.baseline if self.baseline is not None else now
        came_back = now - base
        if now:
            done = reclaim_returned(self._placer(ctx), world, came_back)
            if done:
                _log.info("returned loans: %s", done)
                world = World.from_tree(self._fresh_tree(ctx))
        if not (base - now):
            self.baseline = now
            self.frozen = False
            ctx.cancel("placement.grace")
            self._snapshot(world)
        else:
            self.baseline = base | now

    def grace(self, ctx) -> None:
        world = World.from_tree(ctx.tree())
        now = set(world.by_hw)
        base = self.baseline if self.baseline is not None else now
        if not now:
            _log.info("every output is gone: nothing lent")  # AkuWM: every screen gone lends nothing
            return
        placer = self._placer(ctx)
        for hw in sorted(base - now):
            policy = self.cfg.poweroff_policy(hw)  # read now, not cached (AkuWM)
            snap = self.snap.get(hw)
            if policy != "move" or not snap:
                _log.info("output %s left: policy %s%s", hw, policy, "" if snap else ", no snapshot")
                continue
            items = []
            for cid, rect in snap["windows"].items():
                w = world.windows.get(cid)
                if w is not None and w.ws != SCRATCH:
                    items.append((w, rect, snap["area"]))
            loan = placer.lend(world, snap["role"], hw, items, "poweroff")
            if loan:
                _log.info("output %s left: %d window(s) lent to %s ws %s", hw, len(loan["windows"]), loan["host_output"], loan["host_ws"])
                world = World.from_tree(self._fresh_tree(ctx))
        self.baseline = now
        self.frozen = False
        self._snapshot(world)

    @staticmethod
    def _fresh_tree(ctx) -> dict[str, Any]:
        ctx.invalidate()
        return ctx.tree()
