"""Keypad mapping (SWAY-18): extra keypads (Razer Tartarus V2, …) remapped by keyd.

Source of truth: user/wm/sway/apps/keyd-devices.json, read by system/wm/keyd.nix (one keyd
keyboard per device, `main` = its [main] section). The GUI page "Keypad" draws the device,
edits one key at a time and saves the JSON; keyd is a system service, so the change goes
live with the next install.sh (the page offers it). `deployed()` reads /etc/keyd/<device>.conf
to tell what is live.

keyd's `command()` runs a shell command AS ROOT on a key press: never accepted here."""
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import log, paths

_log = log.get("keypad")

SETTINGS_KEY = "keypad"
SETTINGS_DEFAULTS: dict = {}
GUI_PANELS = [("keypad", "Keypad", "Tartarus · keyd mapping", "input-gaming-symbolic", "panels_keypad:KeypadPanel")]

FILE_NAME = "keyd-devices.json"
KEYD_ETC = Path("/etc/keyd")
MODS = "CSAMG"                    # keyd: Control, Shift, Alt, Meta, AltGr
FUNCTIONS = ("macro", "overload", "overloadt", "overloadt2", "overloadi", "lettermod", "layer", "layerm",
             "oneshot", "oneshotm", "toggle", "togglem", "swap", "swapm", "timeout", "clear", "setlayout",
             "repeat")
FORBIDDEN = ("command(",)


@dataclass(frozen=True, slots=True)
class Key:
    id: str          # what the page shows ("01", "20", "alt", "up")
    code: str        # keyd name the device sends by default (the [main] left-hand side)
    x: int
    y: int
    w: int = 62
    h: int = 52


@dataclass(frozen=True, slots=True)
class Model:
    name: str
    size: tuple[int, int]
    keys: tuple[Key, ...]
    decor: tuple[tuple[str, int, int, int, int], ...] = ()   # (label, x, y, w, h), not mappable

    def key(self, kid: str) -> Key | None:
        return next((k for k in self.keys if k.id == kid), None)


def _tartarus() -> Model:
    # Schematic, not a photo: the 4 x 5 key block (row 4 has 4 keys), the scroll wheel,
    # the big thumb key 20, the small thumb Alt button and the d-pad. Default codes captured
    # with `keyd monitor` by Diego 2026-10-13.
    codes = ["1", "2", "3", "4", "5", "tab", "q", "w", "e", "r", "capslock", "a", "s", "d", "f",
             "leftshift", "z", "x", "c"]
    keys = []
    for i, code in enumerate(codes):
        row, col = divmod(i, 5)
        keys.append(Key(f"{i + 1:02d}", code, 30 + col * 70 + (row % 2) * 8, 30 + row * 64))
    keys += [Key("20", "space", 210, 300, 112, 62), Key("alt", "leftalt", 340, 300, 62, 34),
             Key("up", "up", 452, 262, 46, 42), Key("down", "down", 452, 350, 46, 42),
             Key("left", "left", 404, 306, 46, 42), Key("right", "right", 500, 306, 46, 42)]
    return Model("Razer Tartarus V2", (580, 420), tuple(keys), (("wheel", 400, 40, 36, 96),))


MODELS: dict[str, Model] = {"razer_tartarus_v2": _tartarus()}


def file_path() -> Path:
    return paths.STATE_DIR / FILE_NAME


def load(path: Path | None = None) -> dict[str, Any]:
    p = path or file_path()
    try:
        data = json.loads(p.read_text())
    except FileNotFoundError:
        data = {"version": 1, "devices": {}}
    data.setdefault("devices", {})
    return data


def save(data: dict[str, Any], path: Path | None = None) -> Path:
    p = path or file_path()
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, p)
    return p


_KEYD_KEYS: set[str] | None = None


def keyd_keys() -> set[str] | None:
    """Every key name keyd accepts (`keyd list-keys`; SWAY_APPS_KEYD_BIN from the wrapper)."""
    global _KEYD_KEYS
    if _KEYD_KEYS is None:
        binary = os.environ.get("SWAY_APPS_KEYD_BIN", "keyd")
        try:
            out = subprocess.run([binary, "list-keys"], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.TimeoutExpired):
            return None
        _KEYD_KEYS = {k for k in out.split() if k}
    return _KEYD_KEYS or None


def _balanced(s: str) -> bool:
    depth = 0
    for ch in s:
        depth += ch == "("
        depth -= ch == ")"
        if depth < 0:
            return False
    return depth == 0


def validate(action: str, keys: set[str] | None = None) -> str | None:
    """None when keyd will take it; else why not."""
    a = action.strip()
    if not a:
        return "empty"
    if any(f in a for f in FORBIDDEN):
        return "command() runs a shell command as root on every press: not allowed from here"
    if a == "noop":
        return None
    m = re.fullmatch(r"([a-z0-9]+)\((.*)\)", a, re.S)
    if m:
        if m.group(1) not in FUNCTIONS:
            return f"unknown keyd function {m.group(1)}()"
        return None if _balanced(a) else "unbalanced parentheses"
    keys = keys if keys is not None else keyd_keys()
    if keys is not None and a in keys:
        return None
    mods, key = [], a
    while len(key) > 2 and key[1] == "-" and key[0] in MODS:
        if key[0] in mods:
            return f"modifier {key[0]} twice"
        mods.append(key[0])
        key = key[2:]
    if keys is None:
        return None if re.fullmatch(r"[A-Za-z0-9_.\-]+", key) else f"not a key name: {key!r}"
    return None if key in keys else f"keyd has no key named {key!r}"


def chord(mods: set[str] | list[str], key: str) -> str:
    """{'C', 'S'}, 'a' -> 'C-S-a' (keyd order C S A M G)."""
    return "".join(f"{m}-" for m in MODS if m in mods) + key


def device_model(dev: dict[str, Any]) -> Model | None:
    return MODELS.get(str(dev.get("model", "")))


def action_of(dev: dict[str, Any], key: Key) -> str:
    """What the key does now: its mapping, or its own code when unmapped."""
    return str((dev.get("main") or {}).get(key.code, key.code))


def set_action(dev: dict[str, Any], key: Key, action: str | None) -> None:
    """None or the key's own code = back to the default (entry removed)."""
    main = dev.setdefault("main", {})
    if action is None or action.strip() == key.code:
        main.pop(key.code, None)
    else:
        main[key.code] = action.strip()


def deployed(name: str, etc: Path = KEYD_ETC) -> dict[str, str] | None:
    """[main] of /etc/keyd/<name>.conf as keyd runs it now; None when missing."""
    try:
        text = (etc / f"{name}.conf").read_text()
    except OSError:
        return None
    out: dict[str, str] = {}
    section = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section == "main" and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def pending(data: dict[str, Any], etc: Path = KEYD_ETC) -> list[str]:
    """Devices whose saved mapping is not what keyd runs (needs install.sh)."""
    return [n for n, d in data.get("devices", {}).items() if deployed(n, etc) != dict(d.get("main") or {})]


# --------------------------------------------------------------------------
# CLI

def register_cli(sub) -> None:
    p = sub.add_parser("keypad", help="keypad key mapping (keyd), e.g. the Razer Tartarus").add_subparsers(dest="sub", required=True)
    p.add_parser("list", help="every device and key with its action").set_defaults(func=_cmd_list)
    s = p.add_parser("set", help="map a key: keypad set razer_tartarus 07 C-a")
    s.add_argument("device"); s.add_argument("key"); s.add_argument("action")
    s.add_argument("--no-git", action="store_true"); s.set_defaults(func=_cmd_set)
    r = p.add_parser("reset", help="back to the key's own code")
    r.add_argument("device"); r.add_argument("key")
    r.add_argument("--no-git", action="store_true"); r.set_defaults(func=_cmd_set, action=None)
    p.add_parser("status", help="saved vs live in keyd").set_defaults(func=_cmd_status)


def _cmd_list(a) -> int:
    data = load()
    rows = []
    for name, dev in data["devices"].items():
        m = device_model(dev)
        for k in (m.keys if m else ()):
            rows.append({"device": name, "key": k.id, "code": k.code, "action": action_of(dev, k)})
    print(json.dumps(rows) if getattr(a, "json", False) else "\n".join(f"{r['device']:16} {r['key']:6} {r['code']:10} -> {r['action']}" for r in rows))
    return 0


def _cmd_set(a) -> int:
    data = load()
    dev = data["devices"].get(a.device)
    m = device_model(dev or {})
    key = m.key(a.key) if m else None
    if dev is None or key is None:
        print(f"no device {a.device!r} or key {a.key!r}")
        return 2
    if a.action is not None:
        err = validate(a.action)
        if err:
            print(f"refused: {err}")
            return 2
    set_action(dev, key, a.action)
    p = save(data)
    if not a.no_git:
        from . import gitsync
        gitsync.commit([p], f"sway-apps: keypad {a.device} {a.key} -> {a.action or 'default'}")
    print(f"{a.device} {a.key} -> {action_of(dev, key)} (saved; live after install.sh)")
    return 0


def _cmd_status(a) -> int:
    data = load()
    pend = pending(data)
    print(json.dumps({"devices": sorted(data["devices"]), "pending_deploy": pend}) if getattr(a, "json", False)
          else ("in sync with keyd" if not pend else "saved, not live yet (install.sh): " + ", ".join(pend)))
    return 0
