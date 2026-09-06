"""App discovery: .desktop entries (nix, system, flatpak) + learned app_ids."""
from __future__ import annotations

import configparser
import json
import os
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

from . import log, paths

_log = log.get("discover")

_EXEC_FIELD_CODES = re.compile(r"\s%[fFuUdDnNickvm]")


@dataclass
class App:
    desktop_id: str
    name: str
    exec: str
    command: str          # exec with field codes stripped, ready for `swaymsg exec`
    icon: str
    source: str           # nix-profile | system | user | flatpak-user | flatpak-system | other
    path: str
    no_display: bool
    terminal: bool
    startup_wm_class: str
    flatpak_id: str
    app_id_guess: str
    app_id_candidates: list[str] = field(default_factory=list)
    learned_app_id: str = ""
    categories: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _dirs() -> list[tuple[Path, str]]:
    """(applications dir, source label), most specific first."""
    home = paths.HOME
    user = os.environ.get("USER", "")
    out: list[tuple[Path, str]] = [
        (home / ".local/share/applications", "user"),
        (home / ".local/share/flatpak/exports/share/applications", "flatpak-user"),
        (Path("/var/lib/flatpak/exports/share/applications"), "flatpak-system"),
        (home / ".nix-profile/share/applications", "nix-profile"),
        (Path(f"/etc/profiles/per-user/{user}/share/applications"), "nix-profile"),
        (Path("/run/current-system/sw/share/applications"), "system"),
    ]
    for d in os.environ.get("XDG_DATA_DIRS", "").split(":"):
        if not d:
            continue
        p = Path(d) / "applications"
        if all(p != x for x, _ in out):
            label = "flatpak-user" if "/.local/share/flatpak/" in str(p) else \
                    "flatpak-system" if "/var/lib/flatpak/" in str(p) else \
                    "nix-profile" if "/.nix-profile/" in str(p) or "/etc/profiles/" in str(p) else \
                    "system" if "/run/current-system/" in str(p) else "other"
            out.append((p, label))
    return out


def _clean_exec(exec_line: str) -> str:
    cmd = _EXEC_FIELD_CODES.sub("", " " + exec_line).strip()
    cmd = re.sub(r"\s+", " ", cmd)
    return cmd


def _guess_app_id(desktop_id: str, exec_cmd: str, wm_class: str, flatpak_id: str) -> tuple[str, list[str]]:
    cands: list[str] = []
    if flatpak_id:
        cands.append(flatpak_id)
    if wm_class:
        cands.append(wm_class)
    if desktop_id and desktop_id not in cands:
        cands.append(desktop_id)  # many Wayland apps use their desktop id verbatim
    binary = ""
    if exec_cmd:
        first = exec_cmd.split()[0]
        if first.endswith("flatpak") and "run" in exec_cmd:
            pass
        else:
            binary = os.path.basename(first)
            # nix wrappers: .foo-wrapped -> foo
            if binary.startswith(".") and binary.endswith("-wrapped"):
                binary = binary[1:-8]
            if binary and binary not in cands:
                cands.append(binary)
    guess = cands[0] if cands else desktop_id
    return guess, cands


def load_learned() -> dict[str, str]:
    try:
        return json.loads(paths.LEARNED_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def learn(key: str, app_id: str) -> None:
    if not key or not app_id:
        return
    data = load_learned()
    if data.get(key) == app_id:
        return
    data[key] = app_id
    paths.LEARNED_FILE.parent.mkdir(parents=True, exist_ok=True)
    paths.LEARNED_FILE.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    _log.info("learned %s -> app_id %s", key, app_id)


def apps(include_hidden: bool = False) -> list[App]:
    learned = load_learned()
    seen: set[str] = set()
    out: list[App] = []
    for d, source in _dirs():
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.desktop")):
            desktop_id = f.stem
            if desktop_id in seen:
                continue  # first dir wins, as with XDG lookups
            cp = configparser.RawConfigParser(strict=False, interpolation=None)
            cp.optionxform = str  # type: ignore[assignment]
            try:
                cp.read(f, encoding="utf-8")
                sec = cp["Desktop Entry"]
            except Exception as exc:
                _log.debug("skip %s: %s", f, exc)
                continue
            if sec.get("Type", "Application") != "Application":
                continue
            if sec.get("Hidden", "false").lower() == "true":
                continue
            no_display = sec.get("NoDisplay", "false").lower() == "true"
            if no_display and not include_hidden:
                seen.add(desktop_id)
                continue
            exec_line = sec.get("Exec", "")
            if not exec_line:
                continue
            seen.add(desktop_id)
            flatpak_id = sec.get("X-Flatpak", "")
            if not flatpak_id and source.startswith("flatpak"):
                flatpak_id = desktop_id
            wm_class = sec.get("StartupWMClass", "")
            command = _clean_exec(exec_line)
            guess, cands = _guess_app_id(desktop_id, command, wm_class, flatpak_id)
            learned_id = learned.get(desktop_id, "")
            if learned_id:
                guess = learned_id
                if learned_id not in cands:
                    cands.insert(0, learned_id)
            out.append(App(
                desktop_id=desktop_id,
                name=sec.get("Name", desktop_id),
                exec=exec_line,
                command=command,
                icon=sec.get("Icon", ""),
                source=source,
                path=str(f),
                no_display=no_display,
                terminal=sec.get("Terminal", "false").lower() == "true",
                startup_wm_class=wm_class,
                flatpak_id=flatpak_id,
                app_id_guess=guess,
                app_id_candidates=cands,
                learned_app_id=learned_id,
                categories=[c for c in sec.get("Categories", "").split(";") if c],
            ))
    out.sort(key=lambda a: a.name.lower())
    _log.debug("discovered %d apps", len(out))
    return out


def find(query: str, include_hidden: bool = True) -> list[App]:
    q = query.lower()
    return [a for a in apps(include_hidden)
            if q == a.desktop_id.lower() or q in a.name.lower() or q in a.desktop_id.lower()
            or q in a.app_id_guess.lower()]
