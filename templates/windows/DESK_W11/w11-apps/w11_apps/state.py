"""The state: one JSON in the repo, plus an optional per-machine layer.

    apps/common.json      everything shared
    apps/DESK_W11.json    what only this machine has

Reads merge the two (the machine layer wins by id); writes go to the layer you
name, `common` by default. Every write is atomic and keeps the file sorted, so
a diff shows what changed and nothing else.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from . import paths
from .model import Rule, Shortcut, StartupEntry, Workspace

VERSION = 1
SECTIONS = ("rules", "shortcuts", "startup", "workspaces", "settings")


def _empty() -> dict[str, Any]:
    return {"version": VERSION, "rules": [], "shortcuts": [], "startup": [],
            "workspaces": [], "settings": {}}


def _read(path: Path) -> dict[str, Any]:
    if not path.exists():
        return _empty()
    data = json.loads(path.read_text(encoding="utf-8") or "{}")
    base = _empty()
    base.update(data)
    for key in SECTIONS:
        base.setdefault(key, [] if key != "settings" else {})
    return base


def _write(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False) + "\n"
    # Atomic: a half-written state file is a broken desktop.
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class State:
    def __init__(self, common: Path | None = None, profile: Path | None = None):
        self.common_path = common or paths.COMMON_STATE
        self.profile_path = profile if profile is not None else paths.profile_state()
        self.common = _read(self.common_path)
        self.profile = _read(self.profile_path) if self.profile_path else _empty()

    # ---- reading ----------------------------------------------------------
    def _merged(self, section: str) -> list[dict[str, Any]]:
        by_id: dict[str, dict[str, Any]] = {}
        order: list[str] = []
        for scope, data in (("common", self.common), ("profile", self.profile)):
            for item in data.get(section, []):
                key = str(item.get("id") or item.get("name") or len(order))
                if key not in by_id:
                    order.append(key)
                by_id[key] = dict(item, _scope=scope)
        return [by_id[k] for k in order]

    def rules(self) -> list[Rule]:
        return [Rule.from_dict(d, d.get("_scope", "common")) for d in self._merged("rules")]

    def shortcuts(self) -> list[Shortcut]:
        return [Shortcut.from_dict(d, d.get("_scope", "common")) for d in self._merged("shortcuts")]

    def startup(self) -> list[StartupEntry]:
        return [StartupEntry.from_dict(d, d.get("_scope", "common")) for d in self._merged("startup")]

    def workspaces(self) -> list[Workspace]:
        return [Workspace.from_dict(d, d.get("_scope", "common")) for d in self._merged("workspaces")]

    def settings(self) -> dict[str, Any]:
        merged = dict(self.common.get("settings") or {})
        merged.update(self.profile.get("settings") or {})
        return merged

    # ---- writing ----------------------------------------------------------
    def _layer(self, scope: str) -> tuple[dict[str, Any], Path]:
        if scope == "profile":
            return self.profile, self.profile_path
        return self.common, self.common_path

    def upsert(self, section: str, item: dict[str, Any], scope: str = "common") -> None:
        data, path = self._layer(scope)
        items = data.setdefault(section, [])
        key = "id" if "id" in item else "name"
        for i, existing in enumerate(items):
            if existing.get(key) == item.get(key):
                items[i] = item
                break
        else:
            items.append(item)
        _write(path, data)

    def remove(self, section: str, item_id: str, scope: str | None = None) -> bool:
        removed = False
        for layer in (("common", "profile") if scope is None else (scope,)):
            data, path = self._layer(layer)
            items = data.get(section, [])
            keep = [i for i in items if i.get("id") != item_id and i.get("name") != item_id]
            if len(keep) != len(items):
                data[section] = keep
                _write(path, data)
                removed = True
        return removed

    def set_enabled(self, section: str, item_id: str, enabled: bool) -> bool:
        changed = False
        for layer in ("common", "profile"):
            data, path = self._layer(layer)
            for item in data.get(section, []):
                if item.get("id") == item_id or item.get("name") == item_id:
                    item["enabled"] = enabled
                    _write(path, data)
                    changed = True
        return changed

    def save_rule(self, rule: Rule, scope: str | None = None) -> None:
        self.upsert("rules", rule.to_dict(), scope or rule.scope)

    def save_shortcut(self, sc: Shortcut, scope: str | None = None) -> None:
        self.upsert("shortcuts", sc.to_dict(), scope or sc.scope)

    def save_startup(self, entry: StartupEntry, scope: str | None = None) -> None:
        self.upsert("startup", entry.to_dict(), scope or entry.scope)

    def save_workspace(self, ws: Workspace, scope: str | None = None) -> None:
        self.upsert("workspaces", ws.to_dict(), scope or ws.scope)

    def summary(self) -> str:
        return (f"{self.common_path.name}: {len(self.common['rules'])} rules, "
                f"{len(self.common['shortcuts'])} shortcuts, "
                f"{len(self.common['startup'])} startup, "
                f"{len(self.common['workspaces'])} workspaces")
