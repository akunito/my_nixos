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


def _empty() -> dict[str, Any]:
    return {"version": VERSION, "rules": [], "startup": []}


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

    def write(self) -> list[Path]:
        written = []
        for path, data in ((self.common_path, self.common), (self.profile_path, self.profile)):
            data["version"] = VERSION
            # Do not create an empty profile file just because we loaded it.
            if not data["rules"] and not data["startup"] and not path.exists():
                continue
            _write(path, data)
            written.append(path)
        return written

    def files(self) -> list[Path]:
        return [p for p in (self.common_path, self.profile_path) if p.exists()]
