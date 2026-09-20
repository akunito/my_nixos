"""What the state holds: rules, shortcuts, startup entries, workspaces.

The shapes mirror user/wm/sway/sway-apps so both desks read the same way --
an id, a human name, an enabled flag, notes, and a timestamp -- but the fields
inside speak GlazeWM and Windows instead of sway and Wayland.
"""
from __future__ import annotations

import hashlib
import time
from dataclasses import asdict, dataclass, field
from typing import Any

# What a window can be matched on. GlazeWM matches on the process name, the
# window class and the title; each can be an exact string or a regex.
CRITERIA_KEYS = ("process", "class", "title")

# The states a rule can put a window in, plus the flags that go with them.
# Anything else is free text and goes through untouched.
KNOWN_ACTIONS: dict[str, str] = {
    "set-floating": "floating",
    "set-tiling": "tiling",
    "set-fullscreen": "fullscreen",
    "set-minimized": "minimized",
    "set-sticky": "shown on every workspace of its monitor",
    "unset-sticky": "not sticky",
    "ignore": "not managed at all",
}


def _stamp() -> int:
    return int(time.time())


def _short_id(*parts: str) -> str:
    return hashlib.sha1("|".join(parts).encode()).hexdigest()[:8]


@dataclass
class Rule:
    """One window rule: what to match, and what to do with it."""

    id: str = ""
    criteria: dict[str, str] = field(default_factory=dict)
    actions: list[str] = field(default_factory=list)
    name: str = ""
    enabled: bool = True
    notes: str = ""
    # Which workspace a window should open on, if any. Symbolic on purpose:
    # {"monitor": "main"|"vertical", "slot": 1..10} resolves to 11..10 / 21..20
    # through the workspace table, so the rule survives a monitor swap.
    target: dict[str, Any] | None = None
    updated_at: int = 0
    scope: str = "common"

    @classmethod
    def new(cls, criteria: dict[str, str], actions: list[str], **kw: Any) -> "Rule":
        rule = cls(criteria=dict(criteria), actions=list(actions), **kw)
        rule.id = rule.default_id()
        if not rule.name:
            rule.name = rule.default_name()
        rule.updated_at = _stamp()
        return rule

    def default_id(self) -> str:
        return "r-" + _short_id(*(f"{k}={v}" for k, v in sorted(self.criteria.items())),
                                *sorted(self.actions))

    def default_name(self) -> str:
        return self.criteria.get("process") or self.criteria.get("class") \
            or self.criteria.get("title") or "rule"

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "Rule":
        return cls(
            id=str(d.get("id") or ""),
            criteria={str(k): str(v) for k, v in (d.get("criteria") or {}).items()},
            actions=[str(a) for a in (d.get("actions") or [])],
            name=str(d.get("name") or ""),
            enabled=bool(d.get("enabled", True)),
            notes=str(d.get("notes") or ""),
            target=dict(d["target"]) if isinstance(d.get("target"), dict) else None,
            updated_at=int(d.get("updated_at") or 0),
            scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        if not d.get("target"):
            d.pop("target", None)
        return d

    def matches(self, window: dict[str, Any]) -> bool:
        """Would this rule fire for a window from `glazewm query windows`?"""
        import re

        for key, pattern in self.criteria.items():
            value = {
                "process": window.get("processName", ""),
                "class": window.get("className", ""),
                "title": window.get("title", ""),
            }.get(key, "")
            if pattern.startswith("re:"):
                if not re.search(pattern[3:], value, re.I):
                    return False
            elif value.lower() != pattern.lower():
                return False
        return bool(self.criteria)


@dataclass
class Shortcut:
    """A Hyper+<key> binding.

    `kind` says what pressing it does:
      app    raise-or-launch the app (the AppToggle table)
      exec   run a command
      glaze  send a GlazeWM command
      ahk    call a function of hyper-desktops.ahk (the hand-written gestures)
    """

    id: str = ""
    keys: str = ""                 # "Hyper+L", "Hyper+Shift+S"
    kind: str = "app"
    spec: str = ""                 # app: the process name, or "title:regex"
    command: str = ""              # app/exec: what to launch; glaze: the command
    name: str = ""
    enabled: bool = True
    notes: str = ""
    category: str = ""             # Apps, Windows, Workspaces, Gaming, ...
    updated_at: int = 0
    scope: str = "common"

    @classmethod
    def new(cls, keys: str, kind: str = "app", **kw: Any) -> "Shortcut":
        sc = cls(keys=keys, kind=kind, **kw)
        sc.id = sc.default_id()
        if not sc.name:
            sc.name = sc.default_name()
        sc.updated_at = _stamp()
        return sc

    def default_id(self) -> str:
        return "s-" + _short_id(self.keys.lower(), self.kind)

    def default_name(self) -> str:
        return self.spec or self.command or self.keys

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "Shortcut":
        return cls(
            id=str(d.get("id") or ""), keys=str(d.get("keys") or ""),
            kind=str(d.get("kind") or "app"), spec=str(d.get("spec") or ""),
            command=str(d.get("command") or ""), name=str(d.get("name") or ""),
            enabled=bool(d.get("enabled", True)), notes=str(d.get("notes") or ""),
            category=str(d.get("category") or ""),
            updated_at=int(d.get("updated_at") or 0), scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        return d


@dataclass
class StartupEntry:
    """Something to run when the session starts."""

    id: str = ""
    command: str = ""
    name: str = ""
    enabled: bool = True
    notes: str = ""
    delay_ms: int = 0
    updated_at: int = 0
    scope: str = "common"

    @classmethod
    def new(cls, command: str, **kw: Any) -> "StartupEntry":
        entry = cls(command=command, **kw)
        entry.id = entry.default_id()
        if not entry.name:
            entry.name = command.split("\\")[-1]
        entry.updated_at = _stamp()
        return entry

    def default_id(self) -> str:
        return "u-" + _short_id(self.command.lower())

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "StartupEntry":
        return cls(
            id=str(d.get("id") or ""), command=str(d.get("command") or ""),
            name=str(d.get("name") or ""), enabled=bool(d.get("enabled", True)),
            notes=str(d.get("notes") or ""), delay_ms=int(d.get("delay_ms") or 0),
            updated_at=int(d.get("updated_at") or 0), scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        return d


@dataclass
class Workspace:
    """A workspace and the monitor it belongs to.

    `monitor` is a role, not an index: "main" and "vertical" survive the
    monitors being re-enumerated, which is exactly what a sleep cycle does.
    """

    name: str = ""
    monitor: str = "main"
    keep_alive: bool = False
    display_name: str = ""
    notes: str = ""
    scope: str = "common"

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "Workspace":
        return cls(
            name=str(d.get("name") or ""), monitor=str(d.get("monitor") or "main"),
            keep_alive=bool(d.get("keep_alive", False)),
            display_name=str(d.get("display_name") or ""),
            notes=str(d.get("notes") or ""), scope=scope,
        )

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("scope", None)
        return d
