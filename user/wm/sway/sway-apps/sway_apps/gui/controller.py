"""One place for every mutation the GUI performs; mirrors cli._persist so the
GUI and the CLI behave identically (write -> apply -> live -> commit)."""
from __future__ import annotations

import threading
from dataclasses import dataclass, field
from typing import Any, Callable

from .. import discover, generate, gitsync, log, startup, swayipc
from .. import monitors as mon
from .. import shortcuts as sc_mod
from ..rules import Rule
from ..shortcuts import Shortcut
from ..state import Monitor, Node, StartupEntry, State, Tool

_log = log.get("gui.ctl")


@dataclass
class Outcome:
    ok: bool
    message: str
    details: dict[str, Any] = field(default_factory=dict)


class Controller:
    def __init__(self) -> None:
        self.state = State()
        self.swayfx = swayipc.is_swayfx() if swayipc.available() else False

    def reload_state(self) -> None:
        self.state = State()

    # ---- rules --------------------------------------------------------------
    def _finish(self, message: str, apply_rules: bool, live_rule: Rule | None) -> Outcome:
        details: dict[str, Any] = {}
        self.state.write()
        if apply_rules:
            details["apply"] = generate.apply(self.state, reload=True)
            if live_rule is not None and swayipc.available():
                details["live"] = generate.apply_live(live_rule, self.state)
        try:
            details["commit"] = gitsync.commit(self.state.files(), message)
        except RuntimeError as exc:
            _log.warning("commit failed: %s", exc)
            details["commit_error"] = str(exc)
        live = details.get("live")
        extra = ""
        if live is not None:
            extra = f" · applied to {len({h['window'] for h in live})} open window(s)"
        commit = details.get("commit")
        extra += f" · committed {commit}" if commit else ""
        if commit and gitsync.auto_sync_enabled():
            try:
                details["sync"] = gitsync.sync()
                if details["sync"].get("ok"):
                    extra += " · pushed" if details["sync"].get("pushed") else ""
                    if details["sync"].get("merged"):
                        extra += " · merged upstream edits"
                else:
                    extra += f" · sync: {details['sync'].get('error') or details['sync'].get('skipped')}"
            except Exception as exc:
                _log.warning("sync failed: %s", exc)
                extra += " · sync failed (kept locally)"
        return Outcome(True, message + extra, details)

    def save_rule(self, rule: Rule, scope: str) -> Outcome:
        probs = rule.problems()
        if probs:
            return Outcome(False, "Invalid rule: " + "; ".join(probs))
        with log.action("gui.rules.save", id=rule.id, line=rule.render(), scope=scope):
            self.state.save_rule(rule, scope)
            return self._finish(f"Saved rule {rule.name}", True, rule if rule.enabled else None)

    def delete_rule(self, rule: Rule) -> Outcome:
        with log.action("gui.rules.delete", id=rule.id):
            self.state.remove("rules", rule.id)
            return self._finish(f"Removed rule {rule.name}", True, None)

    def toggle_rule(self, rule: Rule, enabled: bool) -> Outcome:
        rule.enabled = enabled
        with log.action("gui.rules.toggle", id=rule.id, enabled=enabled):
            self.state.save_rule(rule)
            return self._finish(f"{'Enabled' if enabled else 'Disabled'} {rule.name}", True, rule if enabled else None)

    def test_rule(self, rule: Rule) -> Outcome:
        probs = rule.problems()
        if probs:
            return Outcome(False, "Invalid rule: " + "; ".join(probs))
        if not swayipc.available():
            return Outcome(False, "No sway socket")
        hits = generate.apply_live(rule, self.state)
        bad = [h for h in hits if not h["ok"]]
        wins = {h["window"] for h in hits}
        if bad:
            return Outcome(False, f"sway rejected: {bad[0]['error']}", {"hits": hits})
        return Outcome(True, f"Applied to {len(wins)} open window(s)" if wins else "No open window matches", {"hits": hits})

    def matching_windows(self, rule: Rule) -> list[swayipc.Window]:
        if not swayipc.available():
            return []
        return [w for w in swayipc.windows() if swayipc.window_matches(w, rule.criteria)]

    def apply_all(self) -> Outcome:
        res = generate.apply(self.state, reload=True)
        return Outcome(True, f"Regenerated {res['rules']} rules; sway reloaded" if res["reloaded"] else f"Regenerated {res['rules']} rules (no sway socket)", res)

    # ---- startup ------------------------------------------------------------
    def save_startup(self, entry: StartupEntry, scope: str) -> Outcome:
        probs = entry.problems()
        if probs:
            return Outcome(False, "Invalid entry: " + "; ".join(probs))
        with log.action("gui.startup.save", id=entry.id, command=entry.command, scope=scope):
            self.state.save_startup(entry, scope)
            return self._finish(f"Saved startup {entry.name}", False, None)

    def delete_startup(self, entry: StartupEntry) -> Outcome:
        with log.action("gui.startup.delete", id=entry.id):
            self.state.remove("startup", entry.id)
            return self._finish(f"Removed startup {entry.name}", False, None)

    def run_startup_async(self, only: list[str] | None, progress: Callable[[str], None], done: Callable[[list[dict]], None]) -> None:
        def worker() -> None:
            try:
                results = startup.run(self.state, only=only, progress=progress)
            except Exception as exc:  # surfaced in the UI
                _log.exception("startup run failed")
                results = [{"id": "*", "launched": False, "error": str(exc)}]
            done(results)
        threading.Thread(target=worker, name="sway-apps-startup", daemon=True).start()

    def launch_app_async(self, app: discover.App, workspace: str, done: Callable[[dict], None]) -> None:
        def worker() -> None:
            entry = StartupEntry(id="adhoc", name=app.name, command=app.command, app_id=app.app_id_guess,
                                 workspace=workspace, wait_seconds=20, settle_seconds=1, desktop_id=app.desktop_id)
            before = {w.id for w in swayipc.windows()}
            try:
                res = startup.run_entry(entry)
                if res.get("timeout"):
                    new = [w for w in swayipc.windows() if w.id not in before and w.app_id]
                    ids = {w.app_id for w in new}
                    if len(ids) == 1:
                        discover.learn(app.desktop_id, new[0].app_id)
                        res["learned_app_id"] = new[0].app_id
            except Exception as exc:
                _log.exception("launch failed")
                res = {"launched": False, "error": str(exc)}
            done(res)
        threading.Thread(target=worker, name="sway-apps-launch", daemon=True).start()

    # ---- monitors -----------------------------------------------------------
    def save_monitor(self, m: Monitor, scope: str) -> Outcome:
        probs = m.problems()
        if probs:
            return Outcome(False, "Invalid monitor: " + "; ".join(probs))
        clash = [x for x in self.state.monitors() if x.group and x.group == m.group and x.id != m.id]
        if clash:
            return Outcome(False, f"Group {m.group} is already used by {clash[0].id}")
        with log.action("gui.monitors.save", role=m.id, criteria=m.criteria, group=m.group, scope=scope, always_connected=m.always_connected):
            self.state.save_monitor(m, scope)
            out = self._finish(f"Saved monitor {m.id}", True, None)
            if swayipc.available():
                moved = mon.apply_live(self.state)
                n = sum(1 for h in moved if h.get("ok"))
                if n:
                    out.message += f" · moved {n} workspace(s)"
            force = mon.apply_force(self.state)
            bad = [f for f in force if f.get("ok") is False]
            if bad:
                out.ok = False
                out.message += f" · connector force FAILED: {bad[0].get('detail')}"
            elif any(f.get("mode") == "on" for f in force):
                out.message += " · connector forced on"
            return out

    def delete_monitor(self, m: Monitor) -> Outcome:
        with log.action("gui.monitors.delete", role=m.id):
            self.state.remove("monitors", m.id)
            return self._finish(f"Removed monitor {m.id}", True, None)

    def set_pin_geometry(self, on: bool) -> Outcome:
        self.state.set_setting("pin_geometry", on, "profile")
        with log.action("gui.monitors.pin_geometry", state=on):
            return self._finish(f"Geometry pinning {'on' if on else 'off'}", True, None)

    def fix_orphans(self) -> Outcome:
        res = mon.fix_orphans(self.state)
        after = mon.orphans()
        if not res.get("ok"):
            return Outcome(False, res.get("error") or "restore script failed", res)
        return Outcome(True, f"Group-0 sweep done; {len(after)} orphan workspace(s) left", res)

    def rename_monitor(self, m: Monitor, new_role: str) -> Outcome:
        old = m.id
        for r in self.state.rules():
            if r.target and r.target.get("monitor") == old:
                r.target["monitor"] = new_role
                self.state.save_rule(r)
        self.state.remove("monitors", old)
        m.id = new_role
        return self.save_monitor(m, m.scope)

    # ---- shortcuts ----------------------------------------------------------
    def save_shortcut(self, x: Shortcut, scope: str) -> Outcome:
        probs = x.problems()
        if probs:
            return Outcome(False, "Invalid shortcut: " + "; ".join(probs))
        others = [y for y in self.state.shortcuts() if y.id != x.id]
        c = sc_mod.conflicts(others + [x]).get(x.id)
        if c and c["tool"]:
            return Outcome(False, f"{x.keys} is already used by shortcut {c['tool'][0]}")
        if c and c["nix"] and not x.override:
            return Outcome(False, f"{x.keys} is bound by nix; enable Override to take it over")
        with log.action("gui.shortcuts.save", id=x.id, keys=x.keys, kind=x.kind, override=x.override, scope=scope):
            self.state.save_shortcut(x, scope)
            return self._finish(f"Saved shortcut {x.keys}", True, None)

    def delete_shortcut(self, x: Shortcut) -> Outcome:
        with log.action("gui.shortcuts.delete", id=x.id):
            self.state.remove("shortcuts", x.id)
            return self._finish(f"Removed shortcut {x.keys}", True, None)

    # ---- tools ----------------------------------------------------------------
    def save_tool(self, t: Tool, scope: str) -> Outcome:
        probs = t.problems()
        if probs:
            return Outcome(False, "Invalid tool: " + "; ".join(probs))
        with log.action("gui.tools.save", id=t.id, name=t.name, command=t.command, scope=scope):
            self.state.save_tool(t, scope)
            return self._finish(f"Saved tool {t.name}", False, None)

    def delete_tool(self, t: Tool) -> Outcome:
        with log.action("gui.tools.delete", id=t.id):
            self.state.remove("tools", t.id)
            return self._finish(f"Removed tool {t.name}", False, None)

    def launch_tool(self, t: Tool) -> Outcome:
        if not swayipc.available():
            return Outcome(False, "No sway socket")
        from .. import toolrun  # noqa: WPS433
        _log.info("gui.tools.launch id=%s command=%s", t.id, t.launch_command())
        toolrun.launch_async(t)          # exec + wait for the window + float it on top, off the main loop
        return Outcome(True, f"Launched {t.name}" + (" (floating, on top)" if t.float and t.app_id else ""))

    # ---- nodes ----------------------------------------------------------------
    def save_node(self, n: Node, scope: str) -> Outcome:
        probs = n.problems()
        if probs:
            return Outcome(False, "Invalid node: " + "; ".join(probs))
        with log.action("gui.nodes.save", id=n.id, ssh=n.ssh, daemons=n.daemons, scope=scope):
            self.state.save_node(n, scope)
            return self._finish(f"Saved node {n.id}", False, None)

    def delete_node(self, n: Node) -> Outcome:
        with log.action("gui.nodes.delete", id=n.id):
            self.state.remove("nodes", n.id)
            return self._finish(f"Removed node {n.id}", False, None)

    # ---- git ----------------------------------------------------------------
    def git_status(self) -> dict:
        try:
            return gitsync.status()
        except Exception as exc:
            return {"enabled": True, "repo": False, "error": str(exc)}

    def git_push(self) -> Outcome:
        try:
            out = gitsync.push()
            return Outcome(True, "Pushed", {"output": out})
        except RuntimeError as exc:
            return Outcome(False, f"Push failed: {exc}")

    def git_sync(self) -> Outcome:
        try:
            res = gitsync.sync()
        except Exception as exc:
            return Outcome(False, f"Sync failed: {exc}")
        if not res.get("ok"):
            return Outcome(False, f"Sync: {res.get('error') or res.get('skipped')}", res)
        self.reload_state()
        return Outcome(True, f"Synced (behind {res.get('behind', 0)}, pushed {res.get('pushed')}" + (f", merged {len(res['merged'])} file(s)" if res.get("merged") else "") + ")", res)

    def git_pull(self) -> Outcome:
        try:
            out = gitsync.pull()
            self.reload_state()
            return Outcome(True, "Pulled", {"output": out})
        except RuntimeError as exc:
            return Outcome(False, f"Pull failed: {exc}")
