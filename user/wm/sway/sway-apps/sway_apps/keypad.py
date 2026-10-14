"""Keypad mapping (SWAY-18): extra keypads (Razer Tartarus V2, …) remapped by keyd.

Source of truth: user/wm/sway/apps/keyd-devices.json, read by system/wm/keyd.nix. Each device
has PROFILES (one per game: {"name", "main": {key: action}}); Nix builds each into
/etc/keypad/<device>/<profile>, and /etc/keyd/<device>.conf includes /etc/keyd/<device>-active.
Switching is instant: `sudo -n keypad-profile set <device> <profile>` copies a Nix-built
profile there and runs `keyd reload` (no rebuild). Editing or adding a profile needs a deploy
(install.sh), because the profile files come from the Nix build.

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
KEYPAD_ETC = Path("/etc/keypad")              # Nix-built profiles
KEYPAD_VAR = Path("/var/lib/keypad")           # <device>.profile = the live one
PROFILE_BIN = "/run/current-system/sw/bin/keypad-profile"
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
    for d in data["devices"].values():
        profiles(d)
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


_SHORT = {"leftshift": "Shift", "rightshift": "R Shift", "leftcontrol": "Ctrl", "rightcontrol": "R Ctrl",
          "leftalt": "Alt", "rightalt": "AltGr", "leftmeta": "Super", "rightmeta": "R Super", "capslock": "Caps",
          "space": "Space", "enter": "Enter", "esc": "Esc", "tab": "Tab", "backspace": "Bksp", "delete": "Del",
          "pageup": "PgUp", "pagedown": "PgDn", "noop": "—"}
_MOD_NAMES = {"C": "Ctrl", "S": "Shift", "A": "Alt", "M": "Super", "G": "AltGr"}


def label(action: str) -> str:
    """Short text for the drawing: 'C-S-f5' -> 'Ctrl+Shift+F5', 'leftshift' -> 'Shift',
    'macro(…)' -> 'macro…'. The editor keeps the keyd syntax."""
    a = action.strip()
    fn = re.match(r"([a-z0-9]+)\(", a)
    if fn:
        return fn.group(1) + "…"
    mods, key = [], a
    while len(key) > 2 and key[1] == "-" and key[0] in MODS and key not in (keyd_keys() or ()):
        mods.append(_MOD_NAMES[key[0]])
        key = key[2:]
    k = _SHORT.get(key) or (key.upper() if re.fullmatch(r"f\d{1,2}|[a-z]", key) else key)
    return "+".join(mods + [k])


def device_model(dev: dict[str, Any]) -> Model | None:
    return MODELS.get(str(dev.get("model", "")))


def profiles(dev: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """The device's profiles; a pre-profiles file (a bare "main") becomes one called default."""
    if "profiles" not in dev:
        dev["profiles"] = {"default": {"name": "Default", "main": dev.pop("main", {})}}
        dev.setdefault("default_profile", "default")
    return dev["profiles"]


def default_profile(dev: dict[str, Any]) -> str:
    ps = profiles(dev)
    d = dev.get("default_profile")
    return d if d in ps else next(iter(ps))


def slug(name: str, taken: set[str] = frozenset()) -> str:
    base = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:24] or "profile"
    pid, n = base, 2
    while pid in taken:
        pid, n = f"{base}_{n}", n + 1
    return pid


def new_profile(dev: dict[str, Any], name: str, copy_from: str | None = None) -> str:
    ps = profiles(dev)
    pid = slug(name, set(ps))
    src = ps.get(copy_from or "", {})
    ps[pid] = {"name": name.strip() or pid, "main": dict(src.get("main") or {})}
    if src.get("layers"):
        ps[pid]["layers"] = json.loads(json.dumps(src["layers"]))
    return pid


def delete_profile(dev: dict[str, Any], pid: str) -> str | None:
    """None, or why not (the last one, or the default)."""
    ps = profiles(dev)
    if len(ps) < 2:
        return "a device needs at least one profile"
    if pid == default_profile(dev):
        return "the default profile cannot be deleted (pick another default first)"
    ps.pop(pid, None)
    return None


def action_of(profile: dict[str, Any], key: Key) -> str:
    """What the key does in this profile: its mapping, or its own code when unmapped."""
    return str((profile.get("main") or {}).get(key.code, key.code))


def set_action(profile: dict[str, Any], key: Key, action: str | None) -> None:
    """None or the key's own code = back to the default (entry removed)."""
    main = profile.setdefault("main", {})
    if action is None or action.strip() == key.code:
        main.pop(key.code, None)
    else:
        main[key.code] = action.strip()


def parse_main(text: str) -> dict[str, str]:
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


def deployed(dev_name: str, pid: str, etc: Path = KEYPAD_ETC) -> dict[str, str] | None:
    """[main] of the Nix-built profile file; None when that profile was never deployed."""
    try:
        return parse_main((etc / dev_name / pid).read_text())
    except OSError:
        return None


def live_profile(dev_name: str, var: Path = KEYPAD_VAR) -> str | None:
    try:
        return (var / f"{dev_name}.profile").read_text().strip() or None
    except OSError:
        return None


def pending(data: dict[str, Any], etc: Path = KEYPAD_ETC) -> list[str]:
    """'device/profile' entries whose saved mapping is not what the last deploy built."""
    out = []
    for n, d in data.get("devices", {}).items():
        for pid, p in profiles(d).items():
            if deployed(n, pid, etc) != dict(p.get("main") or {}):
                out.append(f"{n}/{pid}")
    return out


def activate(dev_name: str, pid: str) -> tuple[bool, str]:
    """Switch the keypad now (sudo rule: exactly `keypad-profile set *`)."""
    try:
        r = subprocess.run(["sudo", "-n", PROFILE_BIN, "set", dev_name, pid], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)
    return r.returncode == 0, (r.stdout + r.stderr).strip()


# --------------------------------------------------------------------------
# CLI

def register_cli(sub) -> None:
    p = sub.add_parser("keypad", help="keypad key mapping profiles (keyd), e.g. the Razer Tartarus").add_subparsers(dest="sub", required=True)
    x = p.add_parser("list", help="keys of a profile (default: the live one)")
    x.add_argument("--device"); x.add_argument("--profile"); x.set_defaults(func=_cmd_list)
    x = p.add_parser("profiles", help="every device's profiles, the live one marked")
    x.set_defaults(func=_cmd_profiles)
    x = p.add_parser("use", help="switch a keypad to a deployed profile now (keyd reload, no rebuild)")
    x.add_argument("device"); x.add_argument("profile"); x.set_defaults(func=_cmd_use)
    x = p.add_parser("set", help="map a key in a profile: keypad set razer_tartarus 07 C-a [--profile l2]")
    x.add_argument("device"); x.add_argument("key"); x.add_argument("action"); x.add_argument("--profile")
    x.add_argument("--no-git", action="store_true"); x.set_defaults(func=_cmd_set)
    x = p.add_parser("reset", help="key back to its own code")
    x.add_argument("device"); x.add_argument("key"); x.add_argument("--profile")
    x.add_argument("--no-git", action="store_true"); x.set_defaults(func=_cmd_set, action=None)
    p.add_parser("status", help="saved vs deployed vs live").set_defaults(func=_cmd_status)


def _dev(data: dict[str, Any], name: str | None) -> tuple[str, dict[str, Any]] | tuple[None, None]:
    name = name or next(iter(data["devices"]), None)
    return (name, data["devices"][name]) if name in data["devices"] else (None, None)


def _cmd_list(a) -> int:
    data = load()
    name, dev = _dev(data, a.device)
    if dev is None:
        print("no such device")
        return 2
    pid = a.profile or live_profile(name) or default_profile(dev)
    prof = profiles(dev).get(pid)
    m = device_model(dev)
    if prof is None or m is None:
        print(f"no profile {pid!r}")
        return 2
    rows = [{"device": name, "profile": pid, "key": k.id, "code": k.code, "action": action_of(prof, k)} for k in m.keys]
    print(json.dumps(rows) if getattr(a, "json", False) else "\n".join(f"{r['key']:6} {r['code']:10} -> {r['action']}" for r in rows))
    return 0


def _cmd_profiles(a) -> int:
    data = load()
    rows = [{"device": n, "profile": pid, "name": p.get("name", pid), "live": live_profile(n) == pid,
             "default": pid == default_profile(d), "deployed": deployed(n, pid) == dict(p.get("main") or {})}
            for n, d in data["devices"].items() for pid, p in profiles(d).items()]
    print(json.dumps(rows) if getattr(a, "json", False) else "\n".join(
        f"{'*' if r['live'] else ' '} {r['device']:16} {r['profile']:16} {r['name']}{'' if r['deployed'] else '  (not deployed)'}" for r in rows))
    return 0


def _cmd_use(a) -> int:
    ok, msg = activate(a.device, a.profile)
    print(msg)
    return 0 if ok else 1


def _cmd_set(a) -> int:
    data = load()
    name, dev = _dev(data, a.device)
    m = device_model(dev or {})
    key = m.key(a.key) if m else None
    pid = a.profile or (default_profile(dev) if dev else None)
    prof = profiles(dev).get(pid) if dev else None
    if dev is None or key is None or prof is None:
        print(f"no device {a.device!r}, key {a.key!r} or profile {pid!r}")
        return 2
    if a.action is not None:
        err = validate(a.action)
        if err:
            print(f"refused: {err}")
            return 2
    set_action(prof, key, a.action)
    p = save(data)
    if not a.no_git:
        from . import gitsync
        gitsync.commit([p], f"sway-apps: keypad {name}/{pid} {a.key} -> {a.action or 'default'}")
    print(f"{name}/{pid} {a.key} -> {action_of(prof, key)} (saved; deploy to rebuild the profile)")
    return 0


def _cmd_status(a) -> int:
    data = load()
    pend = pending(data)
    live = {n: live_profile(n) for n in data["devices"]}
    print(json.dumps({"live": live, "pending_deploy": pend}) if getattr(a, "json", False)
          else "live: " + ", ".join(f"{n}={p}" for n, p in live.items()) + ("" if not pend else " · not deployed: " + ", ".join(pend)))
    return 0
