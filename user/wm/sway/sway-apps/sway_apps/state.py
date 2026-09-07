"""Repo-backed, layered state: common.json + <PROFILE>.json.

Each file: {"version": 1, "rules": [...], "startup": [...]}.
The profile layer overrides common items with the same id (field-wise), so a
machine can disable or tweak a shared rule without forking it.
"""
from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

from . import log, paths
from .rules import Rule
from .shortcuts import Shortcut

_log = log.get("state")
VERSION = 1
SCOPES = ("common", "profile")


@dataclass
class StartupEntry:
    id: str
    name: str = ""
    command: str = ""
    app_id: str = ""          # expected app_id (regex, sway semantics); empty = fire and forget
    workspace: str = ""       # "11" or a name; empty = leave where it maps
    wait_seconds: int = 30    # how long to wait for the first window
    settle_seconds: float = 2 # extra wait for sibling windows (session restore)
    enabled: bool = True
    order: int = 100
    notes: str = ""
    desktop_id: str = ""      # origin .desktop, for the learned cache
    updated_at: int = 0
    scope: str = "common"

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "StartupEntry":
        return cls(
            id=str(d.get("id") or ""),
            name=str(d.get("name") or ""),
            command=str(d.get("command") or ""),
            app_id=str(d.get("app_id") or ""),
            workspace=str(d.get("workspace") or ""),
            wait_seconds=int(d.get("wait_seconds", 30)),
            settle_seconds=float(d.get("settle_seconds", 2)),
            enabled=bool(d.get("enabled", True)),
            order=int(d.get("order", 100)),
            notes=str(d.get("notes") or ""),
            desktop_id=str(d.get("desktop_id") or ""),
            updated_at=int(d.get("updated_at", 0) or 0),
            scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        return d

    def problems(self) -> list[str]:
        out = []
        if not self.command.strip():
            out.append("empty command")
        if self.wait_seconds < 0:
            out.append("wait_seconds must be >= 0")
        return out


@dataclass
class Monitor:
    """A monitor ROLE on this machine: role id (shared vocabulary across
    profiles: main, second, tv, left...), hardware id and workspace decade."""
    id: str                  # role: main | second | tv | ...
    criteria: str            # sway hardware id: "Make Model Serial"
    group: int = 0           # workspaces group*10+1 .. group*10+10 ; 0 = unpinned
    name: str = ""           # friendly label
    primary: bool = False
    enabled: bool = True
    notes: str = ""
    # Force the DRM connector to "connected" so switching the monitor OFF (DP
    # drops HPD like an unplug) does not make sway destroy the output and
    # evacuate its workspaces. Applied via the sudo helper sway-connector-force.
    always_connected: bool = False
    updated_at: int = 0
    scope: str = "profile"

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "profile") -> "Monitor":
        return cls(id=str(d.get("id") or ""), criteria=str(d.get("criteria") or ""), group=int(d.get("group", 0)),
                   name=str(d.get("name") or ""), primary=bool(d.get("primary", False)),
                   enabled=bool(d.get("enabled", True)), notes=str(d.get("notes") or ""),
                   always_connected=bool(d.get("always_connected", False)),
                   updated_at=int(d.get("updated_at", 0) or 0), scope=scope)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        return d

    def problems(self) -> list[str]:
        out = []
        if not self.id or not all(c.isalnum() or c in "-_" for c in self.id):
            out.append("role id must be alphanumeric (main, second, tv, ...)")
        if not self.criteria.strip():
            out.append("empty hardware id")
        if not 0 <= self.group <= 9:
            out.append("group must be 0..9 (0 = unpinned)")
        return out

    def workspaces(self) -> list[int]:
        return [self.group * 10 + i for i in range(1, 11)] if self.group else []


SETTINGS_DEFAULTS: dict[str, Any] = {
    "pin_geometry": False,   # emit output geometry keyed by hardware id (from nwg-displays' file)
}


def _empty() -> dict[str, Any]:
    return {"version": VERSION, "rules": [], "startup": [], "monitors": [], "shortcuts": [], "settings": {}}


def _read(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return _empty()
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise RuntimeError(f"{path}: expected an object")
    data.setdefault("version", VERSION)
    data.setdefault("rules", [])
    data.setdefault("startup", [])
    data.setdefault("monitors", [])
    data.setdefault("shortcuts", [])
    data.setdefault("settings", {})
    return data


def _write(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".json")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    _log.debug("wrote %s (%d bytes)", path, len(text))


class State:
    """Load both layers, expose merged views, save back to the right layer."""

    def __init__(self, common_path: Path | None = None, profile_path: Path | None = None):
        self.common_path = common_path or paths.common_file()
        self.profile_path = profile_path or paths.profile_file()
        self.common = _read(self.common_path)
        self.profile = _read(self.profile_path)
        _log.debug("loaded common=%s (%d rules, %d startup) profile=%s (%d rules, %d startup)",
                   self.common_path, len(self.common["rules"]), len(self.common["startup"]),
                   self.profile_path, len(self.profile["rules"]), len(self.profile["startup"]))

    # ---- merged views -------------------------------------------------------
    def _merged(self, section: str) -> list[dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for item in self.common[section]:
            d = dict(item)
            d["_scope"] = "common"
            out[d["id"]] = d
        for item in self.profile[section]:
            if item["id"] in out:
                merged = dict(out[item["id"]])
                merged.update(item)
                merged["_scope"] = "profile"  # overridden here
                merged["_overrides"] = True
                out[item["id"]] = merged
            else:
                d = dict(item)
                d["_scope"] = "profile"
                out[item["id"]] = d
        return list(out.values())

    def rules(self) -> list[Rule]:
        return [Rule.from_dict(d, d["_scope"]) for d in self._merged("rules")]

    def monitors(self) -> list[Monitor]:
        items = [Monitor.from_dict(d, d["_scope"]) for d in self._merged("monitors")]
        items.sort(key=lambda m: (m.group or 99, m.id))
        return items

    def monitor(self, role: str) -> Monitor | None:
        for m in self.monitors():
            if m.id == role:
                return m
        return None

    def monitor_by_criteria(self, criteria: str) -> Monitor | None:
        for m in self.monitors():
            if m.criteria == criteria:
                return m
        return None

    def monitor_for_workspace(self, num: int) -> Monitor | None:
        for m in self.monitors():
            if m.group and num in m.workspaces():
                return m
        return None

    def shortcuts(self) -> list[Shortcut]:
        items = [Shortcut.from_dict(d, d["_scope"]) for d in self._merged("shortcuts")]
        items.sort(key=lambda x: x.keys.lower())
        return items

    def shortcut(self, sid: str) -> Shortcut | None:
        for x in self.shortcuts():
            if x.id == sid:
                return x
        return None

    def save_shortcut(self, sc: Shortcut, scope: str | None = None) -> None:
        self.upsert("shortcuts", sc.to_dict(), scope or sc.scope)

    def settings(self) -> dict[str, Any]:
        out = dict(SETTINGS_DEFAULTS)
        out.update(self.common.get("settings") or {})
        out.update(self.profile.get("settings") or {})
        return out

    def set_setting(self, key: str, value: Any, scope: str = "profile") -> None:
        layer = self._layer(scope)
        layer.setdefault("settings", {})[key] = value

    # ---- symbolic targets ---------------------------------------------------
    def resolve_target(self, rule: Rule) -> tuple[int | None, str | None]:
        """(workspace number, problem). None/None when the rule has no target."""
        if not rule.target:
            return None, None
        role = str(rule.target.get("monitor", ""))
        try:
            slot = int(rule.target.get("slot", 0))
        except (TypeError, ValueError):
            return None, f"bad slot {rule.target.get('slot')!r}"
        if not 1 <= slot <= 10:
            return None, f"slot must be 1..10, got {slot}"
        m = self.monitor(role)
        if m is None:
            return None, f"monitor role {role!r} is not defined for profile {paths.profile_name()}"
        if not m.group:
            return None, f"monitor {role!r} has no workspace group"
        return m.group * 10 + slot, None

    def resolved_rules(self) -> list[Rule]:
        """Rules with symbolic targets rewritten to this machine's numbers.
        Unresolvable targets keep their stored numeric action (fallback)."""
        out = []
        for r in self.rules():
            n, _prob = self.resolve_target(r)
            out.append(r.with_workspace_number(n) if n is not None else r)
        return out

    def target_problems(self) -> list[tuple[Rule, str]]:
        out = []
        for r in self.rules():
            _n, prob = self.resolve_target(r)
            if prob:
                out.append((r, prob))
        return out

    def save_monitor(self, mon: Monitor, scope: str | None = None) -> None:
        self.upsert("monitors", mon.to_dict(), scope or mon.scope)

    def startup(self) -> list[StartupEntry]:
        items = [StartupEntry.from_dict(d, d["_scope"]) for d in self._merged("startup")]
        items.sort(key=lambda e: (e.order, e.name))
        return items

    def rule(self, rule_id: str) -> Rule | None:
        for r in self.rules():
            if r.id == rule_id:
                return r
        return None

    def startup_entry(self, entry_id: str) -> StartupEntry | None:
        for e in self.startup():
            if e.id == entry_id:
                return e
        return None

    # ---- mutation -----------------------------------------------------------
    def _layer(self, scope: str) -> dict[str, Any]:
        if scope == "profile":
            return self.profile
        if scope == "common":
            return self.common
        raise ValueError(f"scope must be one of {SCOPES}, got {scope!r}")

    def upsert(self, section: str, item: dict[str, Any], scope: str) -> None:
        import time
        item["updated_at"] = int(time.time())
        layer = self._layer(scope)
        other = self._layer("common" if scope == "profile" else "profile")
        items = layer[section]
        for i, existing in enumerate(items):
            if existing["id"] == item["id"]:
                items[i] = item
                break
        else:
            items.append(item)
        # Moving scope: drop the copy from the other layer so it does not
        # linger as a shadowed duplicate.
        other[section] = [x for x in other[section] if x["id"] != item["id"]]

    def remove(self, section: str, item_id: str) -> bool:
        found = False
        for layer in (self.common, self.profile):
            before = len(layer[section])
            layer[section] = [x for x in layer[section] if x["id"] != item_id]
            found = found or len(layer[section]) != before
        return found

    def save_rule(self, rule: Rule, scope: str | None = None) -> None:
        self.upsert("rules", rule.to_dict(), scope or rule.scope)

    def save_startup(self, entry: StartupEntry, scope: str | None = None) -> None:
        self.upsert("startup", entry.to_dict(), scope or entry.scope)

    def sync_targets(self) -> int:
        """Keep the numeric fallback of every symbolic rule equal to its current
        resolution, so a machine without the role (or a later role removal)
        still gets the last known-good number. Returns rules rewritten."""
        n = 0
        for r in self.rules():
            num, _prob = self.resolve_target(r)
            if num is None:
                continue
            synced = r.with_workspace_number(num)
            if synced.actions != r.actions:
                self.save_rule(synced, r.scope)
                n += 1
        return n

    def write(self) -> list[Path]:
        self.sync_targets()
        written = []
        for path, data in ((self.common_path, self.common), (self.profile_path, self.profile)):
            data["version"] = VERSION
            # Do not create an empty profile file just because we loaded it.
            if not any(data.get(k) for k in ("rules", "startup", "monitors", "shortcuts", "settings")) and not path.exists():
                continue
            _write(path, data)
            written.append(path)
        return written

    def files(self) -> list[Path]:
        return [p for p in (self.common_path, self.profile_path) if p.exists()]
