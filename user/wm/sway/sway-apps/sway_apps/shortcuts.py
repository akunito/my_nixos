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

KINDS = ("app", "exec", "sway", "tmux")
PROGRAMS = ("sway", "tmux")
TMUX_TABLES = ("prefix", "root", "copy-mode-vi")
CATEGORIES = ("Apps", "Tools", "Gaming", "Windows", "Workspaces", "Media", "Screenshots", "System", "Terminal")
TMUX_INCLUDE = paths.TMUX_INCLUDE
TMUX_CONF = paths.XDG_CONFIG_HOME / "tmux" / "tmux.conf"
KITTY_CONF = paths.XDG_CONFIG_HOME / "kitty" / "kitty.conf"
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
    category: str = ""             # Apps, Gaming, Windows, ... (free text, CATEGORIES suggested)
    table: str = "prefix"          # tmux only: prefix | root | copy-mode-vi
    updated_at: int = 0
    scope: str = "common"

    @property
    def program(self) -> str:
        return "tmux" if self.kind == "tmux" else "sway"

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
                   notes=str(d.get("notes") or ""), category=str(d.get("category") or ""),
                   table=str(d.get("table") or "prefix"), updated_at=int(d.get("updated_at", 0) or 0), scope=scope)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self); d.pop("scope", None); return d

    def default_id(self) -> str:
        if self.kind == "tmux":
            return "k-" + hashlib.sha1(f"tmux|{self.table}|{self.keys}".encode()).hexdigest()[:8]
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
        if self.kind == "tmux":
            if not self.keys.strip() or " " in self.keys.strip():
                out.append("tmux key must be a single tmux key name (e, C-M-e, F5, \\;)")
            if self.table not in TMUX_TABLES:
                out.append(f"tmux table must be one of {TMUX_TABLES}")
            if not self.command.strip():
                out.append("empty tmux command")
            return out
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

    def tmux_render(self, with_unbind: bool = False) -> str:
        tbl = {"prefix": "", "root": "-n ", "copy-mode-vi": "-T copy-mode-vi "}[self.table]
        line = f"bind {tbl}{self.keys} {self.command}"
        return (f"unbind {tbl}{self.keys}\n" if with_unbind else "") + line

    def render(self, with_unbind: bool = False, unbind_flags: str = "") -> str:
        if self.kind == "tmux":
            return self.tmux_render(with_unbind)
        flags = ("--release " if self.release else "") + ("--locked " if self.locked else "")
        keys = sway_keys(self.keys)
        line = f"bindsym {flags}{keys} {self.sway_command()}"
        # unbindsym must repeat the flags of the binding it removes
        # ("Could not find binding ... for the given flags" otherwise).
        uf = (unbind_flags.strip() + " ") if unbind_flags.strip() else ""
        return (f"unbindsym {uf}{keys}\n" if with_unbind else "") + line


def guess_category(command: str, program: str = "sway") -> str:
    c = command.lower()
    if program in ("tmux", "kitty"):
        return "Terminal"
    if "app-toggle" in c:
        return "Apps"
    if "gamescope" in c or "steam" in c:
        return "Gaming"
    if "screenshot" in c or "grim" in c or "swappy" in c:
        return "Screenshots"
    if "xf86audio" in c or "playerctl" in c or "swayosd" in c or "brightness" in c or "volume" in c or "mic" in c:
        return "Media"
    if c.startswith(("workspace", "move container to workspace", "move workspace")) or "swaysome" in c or "workspace" in c:
        return "Workspaces"
    if c.startswith(("focus", "move", "resize", "split", "layout", "fullscreen", "floating", "sticky", "kill", "scratchpad", "border", "opacity")):
        return "Windows"
    return "System"


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
        out.append({"keys": friendly_keys(keys), "sway_keys": keys, "fold": f, "command": cmd.strip(), "flags": flags.strip(),
                    "program": "sway", "category": guess_category(cmd)})
    return out


# --------------------------------------------------------------------------
# tmux (nix-owned binds from tmux.conf; ours go to the sourced include) + kitty

_TMUX_BIND_RX = re.compile(r"^\s*bind(?:-key)?\s+(?:(-n)\s+|-T\s+(\S+)\s+)?(?:-N\s+\"[^\"]*\"\s+|-N\s+\S+\s+)?(?:-r\s+)?(\S+)\s+(.*)$")


def tmux_bindings(conf_path: Path | None = None) -> list[dict[str, str]]:
    """binds defined by nix in tmux.conf (the sourced include is skipped)."""
    path = conf_path or TMUX_CONF
    out = []
    try:
        text = path.read_text()
    except OSError:
        return out
    buf = ""
    for raw in text.splitlines():
        line = buf + raw
        if line.rstrip().endswith("\\"):
            buf = line.rstrip()[:-1] + " "
            continue
        buf = ""
        m = _TMUX_BIND_RX.match(line)
        if not m:
            continue
        root, table, key, cmd = m.groups()
        tbl = "root" if root else (table or "prefix")
        if tbl == "copy-mode-vi" and table is None:
            tbl = "prefix"
        out.append({"keys": key, "table": tbl, "command": cmd.strip(), "program": "tmux", "category": "Terminal",
                    "fold": f"tmux|{tbl}|{key}"})
    return out


def kitty_bindings(conf_path: Path | None = None) -> list[dict[str, str]]:
    path = conf_path or KITTY_CONF
    out = []
    try:
        text = path.read_text()
    except OSError:
        return out
    for raw in text.splitlines():
        m = re.match(r"^\s*map\s+(\S+)\s+(.*)$", raw)
        if m:
            out.append({"keys": m.group(1), "command": m.group(2).strip(), "program": "kitty", "category": "Terminal",
                        "fold": "kitty|" + m.group(1).lower()})
    return out


_TMUX_ROOT_RX = re.compile(r"^(?:(C)-)?(?:(M)-)?(?:(S)-)?(\S+)$")


def tmux_root_to_sway_fold(key: str) -> str | None:
    """tmux root key 'C-M-e' -> the sway fold 'Control+Mod1+e' a sway binding
    would need to shadow it (sway sees the key first)."""
    m = _TMUX_ROOT_RX.match(key)
    if not m:
        return None
    c, mm, sh, k = m.groups()
    mods = [x for x, f in (("Control", c), ("Mod1", mm), ("Shift", sh)) if f]
    if not mods:
        return None
    mods.sort(key=lambda x: MOD_ORDER.index(x))
    return "+".join(mods + [k.lower()])


def cross_conflicts(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None,
                    tmux: list[dict[str, str]] | None = None) -> list[dict[str, str]]:
    """sway bindings (nix or tool) that shadow a tmux root-table bind."""
    nix = nix if nix is not None else nix_bindings()
    tmux = tmux if tmux is not None else tmux_bindings()
    sway_folds: dict[str, str] = {b["fold"]: "nix: " + b["command"] for b in nix}
    for s in shortcuts:
        if s.program == "sway" and s.enabled and not s.problems():
            sway_folds[fold(s.keys)] = "sway-apps: " + s.sway_command()
    tmux_roots = [(t["keys"], t["command"], "nix") for t in tmux if t["table"] == "root"] + \
                 [(s.keys, s.command, "sway-apps") for s in shortcuts if s.kind == "tmux" and s.table == "root" and s.enabled]
    out = []
    for key, cmd, owner in tmux_roots:
        f = tmux_root_to_sway_fold(key)
        if f and f in sway_folds:
            out.append({"tmux_key": key, "tmux_command": cmd, "tmux_owner": owner, "shadowed_by": sway_folds[f]})
    return out


def render_tmux(shortcuts: list[Shortcut], tmux: list[dict[str, str]] | None = None) -> tuple[str, list[str]]:
    """Content of ~/.config/tmux/sway-apps.conf."""
    tmux = tmux if tmux is not None else tmux_bindings()
    nixset = {t["fold"] for t in tmux}
    lines = ["# Generated by sway-apps -- DO NOT EDIT BY HAND. Reload: tmux source-file " + str(TMUX_INCLUDE)]
    warns: list[str] = []
    seen: set[str] = set()
    for s in shortcuts:
        if s.kind != "tmux" or not s.enabled:
            continue
        if s.problems():
            warns.append(f"{s.id}: " + "; ".join(s.problems())); continue
        f = f"tmux|{s.table}|{s.keys}"
        if f in seen:
            warns.append(f"{s.id}: duplicate tmux key {s.table} {s.keys}"); continue
        if f in nixset and not s.override:
            warns.append(f"{s.id}: tmux {s.table} {s.keys} is bound by nix's tmux.conf; enable override to take it over"); continue
        seen.add(f)
        lines.append(f"# {s.name} [{s.id}]" + (" (overrides nix)" if f in nixset else ""))
        lines.append(s.tmux_render(with_unbind=f in nixset))
    return "\n".join(lines) + "\n", warns


def conflicts(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None,
              tmux: list[dict[str, str]] | None = None) -> dict[str, dict[str, Any]]:
    """id -> {'nix': cmd | None, 'tool': [other ids]} for every shortcut whose folded keys collide.
    tmux shortcuts collide on (table, key) against nix's tmux.conf binds."""
    nix = nix if nix is not None else nix_bindings()
    tmux = tmux if tmux is not None else tmux_bindings()
    tmuxmap = {t["fold"]: t["command"] for t in tmux}
    nixmap: dict[str, str] = {}
    nixflags: dict[str, str] = {}
    for b in nix:
        nixmap.setdefault(b["fold"], b["command"])
        nixflags.setdefault(b["fold"], b.get("flags", ""))
    byfold: dict[str, list[str]] = {}
    for sc in shortcuts:
        if sc.kind == "tmux":
            byfold.setdefault(f"tmux|{sc.table}|{sc.keys}", []).append(sc.id)
            continue
        try:
            byfold.setdefault(fold(sc.keys), []).append(sc.id)
        except ValueError:
            pass
    out: dict[str, dict[str, Any]] = {}
    for sc in shortcuts:
        if sc.kind == "tmux":
            f = f"tmux|{sc.table}|{sc.keys}"
            others = [i for i in byfold.get(f, []) if i != sc.id]
            n = tmuxmap.get(f)
            if n is not None or others:
                out[sc.id] = {"nix": n, "nix_flags": "", "tool": others}
            continue
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
    enabled = [s for s in shortcuts if s.enabled and s.kind != "tmux"]
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
    tmux = tmux_bindings()
    kitty = kitty_bindings()
    conf = conflicts(shortcuts, nix)
    overridden = {conf[s.id]["nix"] for s in shortcuts if s.enabled and s.override and s.id in conf and conf[s.id]["nix"]}
    rows: list[tuple[str, str, str, str, str]] = []  # category, keys, name, command, owner
    for s in shortcuts:
        cat = s.category or guess_category(s.sway_command() if s.kind != "tmux" else s.command, s.program)
        keys = s.keys if s.kind != "tmux" else ({"prefix": "Ctrl+O, ", "root": "", "copy-mode-vi": "[copy] "}[s.table] + s.keys)
        rows.append((cat, keys, s.name, s.sway_command() if s.kind != "tmux" else s.command, "sway-apps" + ("" if s.enabled else " (disabled)")))
    for b in nix:
        if b["command"] not in overridden:
            rows.append((b["category"], b["keys"], "", b["command"], "nix"))
    tool_tmux = {f"tmux|{s.table}|{s.keys}" for s in shortcuts if s.kind == "tmux" and s.enabled}
    for t in tmux:
        if t["fold"] in tool_tmux:
            continue
        rows.append(("Terminal", {"prefix": "Ctrl+O, ", "root": "", "copy-mode-vi": "[copy] "}[t["table"]] + t["keys"], "", t["command"], "tmux (nix)"))
    for k in kitty:
        rows.append(("Terminal", k["keys"], "", k["command"], "kitty (nix)"))
    out = []
    for cat in list(CATEGORIES) + sorted({r[0] for r in rows} - set(CATEGORIES)):
        block = [r for r in rows if r[0] == cat]
        if not block:
            continue
        out += [f"## {cat}", "", "| Keys | Name | Command | Owner |", "|---|---|---|---|"]
        for _c, k, n, c, o in sorted(block, key=lambda r: (r[4] != "sway-apps", r[1].lower())):
            out.append(f"| `{k}` | {n} | `{c.replace('|', '\\|')[:90]}` | {o} |")
        out.append("")
    return "\n".join(out) + "\n"


def _doc_markdown_flat(shortcuts: list[Shortcut], nix: list[dict[str, str]] | None = None) -> str:
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
