"""Keyboard shortcuts owned by sway-apps (hybrid model).

nix keeps the window-manager core (focus, move, resize, workspaces, media,
system) as a safety net; sway-apps owns the app launchers and whatever the
user adds. A tool shortcut may take over a key nix binds: the include emits
`unbindsym KEYS` before its own `bindsym`, which sway accepts without the
"overwriting binding" nag a duplicate bindsym would raise.

Keys are stored in a friendly form ("Hyper+Shift+n", "Super+Return") and
rendered to sway keysyms (Hyper = Mod4+Control+Mod1, Super = Mod4, Alt = Mod1,
Ctrl = Control). sway folds the keysym case, so conflicts are compared folded.
"""
from __future__ import annotations

import hashlib
import re
import shlex
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

from . import paths

KINDS = ("app", "exec", "sway")
HYPER = ("Mod4", "Control", "Mod1")
MOD_ALIASES = {
    "hyper": HYPER,
    "super": ("Mod4",), "win": ("Mod4",), "mod4": ("Mod4",), "logo": ("Mod4",),
    "ctrl": ("Control",), "control": ("Control",),
    "alt": ("Mod1",), "mod1": ("Mod1",),
    "shift": ("Shift",),
    "mod5": ("Mod5",), "altgr": ("Mod5",), "mod3": ("Mod3",), "mod2": ("Mod2",),
}
MOD_ORDER = ["Mod4", "Control", "Mod1", "Shift", "Mod2", "Mod3", "Mod5"]
APP_TOGGLE = "~/.config/sway/scripts/app-toggle.sh"


def normalize_keys(spec: str) -> tuple[tuple[str, ...], str]:
    """'hyper+shift+N' -> (('Mod4','Control','Mod1','Shift'), 'N')."""
    parts = [p for p in spec.replace(" ", "").split("+") if p]
    if not parts:
        raise ValueError("empty key combination")
    mods: list[str] = []
    key = parts[-1]
    for p in parts[:-1]:
        alias = MOD_ALIASES.get(p.lower())
        if alias is None:
            raise ValueError(f"unknown modifier {p!r} (use Hyper, Super, Ctrl, Alt, Shift)")
        for m in alias:
            if m not in mods:
                mods.append(m)
    if key.lower() in MOD_ALIASES:
        raise ValueError("a modifier cannot be the last element")
    mods.sort(key=lambda m: MOD_ORDER.index(m) if m in MOD_ORDER else 99)
    return tuple(mods), key


def sway_keys(spec: str) -> str:
    mods, key = normalize_keys(spec)
    return "+".join(list(mods) + [key])


def friendly_keys(sway_spec: str) -> str:
    """'Mod4+Control+Mod1+Shift+n' -> 'Hyper+Shift+n' (for nix-parsed bindings)."""
    parts = sway_spec.split("+")
    mods, key = parts[:-1], parts[-1]
    if all(m in mods for m in HYPER):
        rest = [m for m in mods if m not in HYPER]
        mods = ["Hyper"] + rest
    mods = [{"Mod4": "Super", "Control": "Ctrl", "Mod1": "Alt"}.get(m, m) for m in mods]
    return "+".join(mods + [key])


def fold(spec: str) -> str:
    """Collision key: sway resolves keysyms case-insensitively."""
    mods, key = normalize_keys(spec)
    return "+".join(list(mods) + [key.lower()])


@dataclass
class Shortcut:
    id: str
    keys: str                      # friendly form
    kind: str = "app"              # app | exec | sway
    app_id: str = ""               # app: app_id (or title:^regex) for app-toggle.sh
    command: str = ""              # app/exec: command line; sway: the sway command
    name: str = ""
    enabled: bool = True
    release: bool = False          # bindsym --release
    locked: bool = False           # bindsym --locked
    override: bool = False         # allowed to take over a nix-bound key
    notes: str = ""
    updated_at: int = 0
    scope: str = "common"

    @classmethod
    def new(cls, keys: str, kind: str, **kw: Any) -> "Shortcut":
        sc = cls(id="", keys=keys, kind=kind, **kw)
        sc.id = sc.default_id()
        if not sc.name:
            sc.name = sc.default_name()
        return sc

    @classmethod
    def from_dict(cls, d: dict[str, Any], scope: str = "common") -> "Shortcut":
        return cls(id=str(d.get("id") or ""), keys=str(d.get("keys") or ""), kind=str(d.get("kind") or "app"),
                   app_id=str(d.get("app_id") or ""), command=str(d.get("command") or ""), name=str(d.get("name") or ""),
                   enabled=bool(d.get("enabled", True)), release=bool(d.get("release", False)),
                   locked=bool(d.get("locked", False)), override=bool(d.get("override", False)),
                   notes=str(d.get("notes") or ""), updated_at=int(d.get("updated_at", 0) or 0), scope=scope)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self); d.pop("scope", None); return d

    def default_id(self) -> str:
        try:
            k = fold(self.keys)
        except ValueError:
            k = self.keys
        return "k-" + hashlib.sha1(k.encode()).hexdigest()[:8]

    def default_name(self) -> str:
        if self.kind == "app":
            return self.app_id.replace("title:", "") or self.command.split()[0] if self.command else self.app_id
        if self.kind == "exec":
            return (self.command.split() or ["exec"])[0]
        return self.command

    def problems(self) -> list[str]:
        out = []
        try:
            normalize_keys(self.keys)
        except ValueError as exc:
            out.append(str(exc))
        if self.kind not in KINDS:
            out.append(f"unknown kind {self.kind!r}")
        if self.kind == "app" and not self.app_id.strip():
            out.append("app shortcut needs an app_id (or title:^regex)")
        if not self.command.strip():
            out.append("empty command")
        return out

    def sway_command(self) -> str:
        if self.kind == "app":
            return f"exec {APP_TOGGLE} {shlex.quote(self.app_id)} {self.command}"
        if self.kind == "exec":
            return f"exec {self.command}"
        return self.command

    def render(self, with_unbind: bool = False, unbind_flags: str = "") -> str:
        flags = ("--release " if self.release else "") + ("--locked " if self.locked else "")
        keys = sway_keys(self.keys)
        line = f"bindsym {flags}{keys} {self.sway_command()}"
        # unbindsym must repeat the flags of the binding it removes
        # ("Could not find binding ... for the given flags" otherwise).
        uf = (unbind_flags.strip() + " ") if unbind_flags.strip() else ""
        return (f"unbindsym {uf}{keys}\n" if with_unbind else "") + line


# --------------------------------------------------------------------------
# nix-owned bindings (read from the generated main config, never the include)

_BIND_RX = re.compile(r"^\s*bindsym\s+((?:--\S+\s+)*)(\S+)\s+(.*)$")


def nix_bindings(config_path: Path | None = None) -> list[dict[str, str]]:
    path = config_path or (paths.XDG_CONFIG_HOME / "sway" / "config")
    out = []
    try:
        text = path.read_text()
    except OSError:
        return out
    for line in text.splitlines():
        m = _BIND_RX.match(line)
        if not m:
            continue
        flags, keys, cmd = m.groups()
        try:
            f = fold(keys)
        except ValueError:
            f = keys.lower()
        out.append({"keys": friendly_keys(keys), "sway_keys": keys, "fold": f, "command": cmd.strip(), "flags": flags.strip()})
    return out


def conflicts(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None) -> dict[str, dict[str, Any]]:
    """id -> {'nix': cmd | None, 'tool': [other ids]} for every shortcut whose folded keys collide."""
    nix = nix if nix is not None else nix_bindings()
    nixmap: dict[str, str] = {}
    nixflags: dict[str, str] = {}
    for b in nix:
        nixmap.setdefault(b["fold"], b["command"])
        nixflags.setdefault(b["fold"], b.get("flags", ""))
    byfold: dict[str, list[str]] = {}
    for sc in shortcuts:
        try:
            byfold.setdefault(fold(sc.keys), []).append(sc.id)
        except ValueError:
            pass
    out: dict[str, dict[str, Any]] = {}
    for sc in shortcuts:
        try:
            f = fold(sc.keys)
        except ValueError:
            continue
        others = [i for i in byfold.get(f, []) if i != sc.id]
        n = nixmap.get(f)
        if n is not None or others:
            out[sc.id] = {"nix": n, "nix_flags": nixflags.get(f, ""), "tool": others}
    return out


def render_all(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None) -> tuple[str, list[str]]:
    """Include section text + warnings for skipped shortcuts."""
    conf = conflicts(shortcuts, nix)
    lines: list[str] = []
    warns: list[str] = []
    enabled = [s for s in shortcuts if s.enabled]
    if not enabled:
        return "", warns
    lines.append(f"\n# ---- Shortcuts ({len(enabled)})")
    seen: set[str] = set()
    for sc in enabled:
        if sc.problems():
            warns.append(f"{sc.id}: " + "; ".join(sc.problems()))
            continue
        c = conf.get(sc.id)
        f = fold(sc.keys)
        if f in seen:
            warns.append(f"{sc.id}: {sc.keys} already emitted by another shortcut; skipped")
            continue
        if c and c["nix"] and not sc.override:
            warns.append(f"{sc.id}: {sc.keys} is bound by nix ({c['nix'][:60]}); enable override to take it over")
            continue
        seen.add(f)
        lines.append(f"# {sc.name} [{sc.id}]" + (" (overrides nix)" if c and c["nix"] else ""))
        lines.append(sc.render(with_unbind=bool(c and c["nix"]), unbind_flags=(c or {}).get("nix_flags", "")))
    return "\n".join(lines) + "\n", warns


def validation_context(nix: list[dict[str, str]] | None = None) -> str:
    """The nix bindsym lines, so an include with `unbindsym` validates on its own."""
    nix = nix if nix is not None else nix_bindings()
    return "".join(f"bindsym {(b['flags'] + ' ') if b['flags'] else ''}{b['sway_keys']} {b['command']}\n" for b in nix)


def doc_markdown(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None) -> str:
    nix = nix if nix is not None else nix_bindings()
    conf = conflicts(shortcuts, nix)
    rows = []
    overridden = {conf[s.id]["nix"] for s in shortcuts if s.enabled and s.override and s.id in conf and conf[s.id]["nix"]}
    for s in sorted(shortcuts, key=lambda x: fold(x.keys) if not x.problems() else x.keys):
        rows.append((s.keys, s.name, s.sway_command(), "sway-apps" + ("" if s.enabled else " (disabled)")))
    for b in sorted(nix, key=lambda x: x["fold"]):
        if b["command"] in overridden:
            continue
        rows.append((b["keys"], "", b["command"], "nix"))
    out = ["| Keys | Name | Command | Owner |", "|---|---|---|---|"]
    for k, n, c, o in rows:
        out.append(f"| `{k}` | {n} | `{c.replace('|', '\\\\|')[:90]}` | {o} |")
    return "\n".join(out) + "\n"
