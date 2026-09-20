"""Seed the state from what is already configured.

Nothing is designed twice: the rules in glazewm/config.yaml, the Hyper+<letter>
table in hyper-desktops.ahk and the workspace bindings are read back into the
state, so the first `apply` regenerates exactly what is there today.

The YAML is parsed by hand on purpose. The config is a small, known shape and
this way the tool has no dependencies at all outside the GUI.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from . import paths
from .model import Rule, Shortcut, StartupEntry, Workspace

# - window_process: { equals: 'Telegram' }    -> ("process", "Telegram")
# - window_class: { regex: 'Chrome_.*' }      -> ("class", "re:Chrome_.*")
_MATCH_LINE = re.compile(
    r"^\s*-?\s*window_(process|class|title):\s*\{\s*(equals|regex):\s*'([^']*)'\s*\}")
_COMMANDS_LINE = re.compile(r"^\s*-\s*commands:\s*\[([^\]]*)\]")
_WS_LINE = re.compile(r"^\s*-\s*\{\s*name:\s*'([^']+)',\s*bind_to_monitor:\s*(\d+)\s*\}")
# ^!#l:: AppToggle("Telegram.exe", A_AppData "\Telegram Desktop\Telegram.exe")
_TOGGLE_LINE = re.compile(r'^\^!#(\+?)(\w):: AppToggle\("([^"]+)",\s*(.+?)\)\s*(?:;.*)?$')


def _key_name(shift: str, letter: str) -> str:
    return f"Hyper+{'Shift+' if shift else ''}{letter.upper()}"


def import_glazewm_rules(config: Path | None = None) -> tuple[list[Rule], list[Workspace]]:
    path = config or paths.GLAZE_CONFIG
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    rules: list[Rule] = []
    workspaces: list[Workspace] = []

    in_rules = False
    actions: list[str] = []
    criteria: list[dict[str, str]] = []
    current: dict[str, str] = {}

    def flush() -> None:
        nonlocal actions, criteria, current
        if current:
            criteria.append(current)
            current = {}
        for crit in criteria:
            if crit and actions:
                rules.append(Rule.new(crit, list(actions), notes="imported from config.yaml"))
        actions, criteria = [], []

    for raw in text.splitlines():
        if raw.startswith("window_rules:"):
            in_rules = True
            continue
        if in_rules and raw and not raw.startswith((" ", "\t", "#")):
            flush()
            in_rules = False
        if not in_rules:
            m = _WS_LINE.match(raw)
            if m:
                workspaces.append(Workspace(
                    name=m.group(1),
                    monitor="main" if m.group(2) == "0" else "vertical"))
            continue

        m = _COMMANDS_LINE.match(raw)
        if m:
            flush()
            actions = [a.strip().strip("'\"") for a in m.group(1).split(",") if a.strip()]
            continue
        m = _MATCH_LINE.match(raw)
        if m:
            key, how, value = m.group(1), m.group(2), m.group(3)
            # A "- " starts a new alternative; a continuation line adds to it.
            if raw.lstrip().startswith("-") and current:
                criteria.append(current)
                current = {}
            current[key] = value if how == "equals" else f"re:{value}"
    flush()
    return rules, workspaces


def import_ahk_shortcuts(ahk: Path | None = None) -> list[Shortcut]:
    path = ahk or paths.AHK_MAIN
    text = path.read_text(encoding="utf-8-sig") if path.exists() else ""
    out: list[Shortcut] = []
    for raw in text.splitlines():
        m = _TOGGLE_LINE.match(raw.strip())
        if not m:
            continue
        shift, letter, spec, command = m.groups()
        out.append(Shortcut.new(
            _key_name(shift, letter), "app", spec=spec, command=command.strip(),
            category="Apps", notes="imported from hyper-desktops.ahk"))
    return out


def import_startup(startup_dir: Path | None = None) -> list[StartupEntry]:
    """The Startup folder, as the session runs it today."""
    folder = startup_dir or (paths.windows_temp().parents[2]
                             / "Roaming/Microsoft/Windows/Start Menu/Programs/Startup")
    entries: list[StartupEntry] = []
    if not folder.exists():
        return entries
    for item in sorted(folder.iterdir()):
        if item.suffix.lower() == ".lnk":
            entries.append(StartupEntry.new(str(item), name=item.stem,
                                            notes="found in the Startup folder"))
    return entries
