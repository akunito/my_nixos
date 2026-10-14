"""Per-monitor Waybar (plan §2, SWAY-2..5).

One Waybar process, one bar per monitor role ("wb-<role>") plus a catch-all
"wb-other" for unregistered outputs. Every bar has "ipc": true and an id that
matches a sway `bar <id> { swaybar_command true; mode dock|invisible }` block
in ~/.config/sway/sway-apps-bars.conf: `bar <id> mode …` hides ONE bar of the
process. `swaymsg reload` resends the file's modes, so the file always carries
the current state.

Generated (only when the text changes, atomically, as regular files):
  ~/.config/waybar/config           bars; module definitions from the Nix catalog
  ~/.config/waybar/style.css        Nix base CSS + @import of the next one
  ~/.config/waybar/sway-apps.css    workspace mode, effective visibility, sizes
  ~/.config/sway/sway-apps-bars.conf
Layers: Nix catalog < settings.waybar (common < profile JSON; "save as
default") < ~/.local/state/sway-apps/waybar.json (hotkey and live changes).

Effectively visible = enabled AND output active AND its visible workspace has
no fullscreen view. Exactly one effectively visible bar shows every workspace.
Hyper+Shift+H = `nop sway-apps waybar toggle` (focused monitor's bar).
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import ipc, log, paths
from . import monitors as mon

_log = log.get("waybar")

SETTINGS_KEY = "waybar"
SETTINGS_DEFAULTS: dict = {"bars": {}, "templates": {}}

GUI_PANELS = [("waybar", "Waybar", "Bars per monitor · widgets", "view-continuous-symbolic", "panels_waybar:WaybarPanel")]

OTHER = "other"
WS_MODES = ("output", "all")
SECTIONS = ("left", "center", "right")
TEMPLATES = ("primary", "secondary")
BAR_TEMPLATES = ("primary", "secondary", "custom")
SIZE_MIN, SIZE_MAX = 50, 250
WORKSPACES = "sway/workspaces"
WINDOW_CHANGES = frozenset(("new", "close", "move", "fullscreen_mode"))
WORKSPACE_CHANGES = frozenset(("focus", "init", "empty", "move", "reload"))
CSS_THROTTLE = 0.15     # one get_tree per burst of workspace/window events
OUTPUTS_SETTLE = 2.0    # after watch.reconcile (1.5 s), which may adopt a monitor

CATALOG_FILE = paths.XDG_CONFIG_HOME / "sway-apps" / "waybar-modules.json"
BASE_CSS_FILE = paths.XDG_CONFIG_HOME / "sway-apps" / "waybar-base.css"
CONFIG_FILE = paths.XDG_CONFIG_HOME / "waybar" / "config"
STYLE_FILE = paths.XDG_CONFIG_HOME / "waybar" / "style.css"
CSS_FILE = paths.XDG_CONFIG_HOME / "waybar" / "sway-apps.css"
BARS_FILE = paths.XDG_CONFIG_HOME / "sway" / "sway-apps-bars.conf"
LOCAL_FILE = paths.LOCAL_STATE_DIR / "waybar.json"

FALLBACK_CATALOG: dict[str, Any] = {
    "version": 1,
    "modules": {WORKSPACES: {"disable-scroll": True}, "tray": {"icon-spacing": 8}, "clock": {"format": "{:%H:%M}"}},
    "layouts": {t: {"left": [], "center": [WORKSPACES], "right": ["tray", "clock"]} for t in TEMPLATES},
    "bar": {"layer": "top", "position": "top", "height": 30, "spacing": 0},
    "sizes": {"font": 13, "tray_icon": 16},
    "default_visible": "primary",
}

# Mirrors the paddings/margins of the stylix CSS in user/wm/sway/waybar.nix;
# scaled per bar when its size is not 100 %. Keep the two in step.
_MODULE_IDS = ("#clock", "#battery", "#backlight", "#network", "#pulseaudio", "#bluetooth", "#idle_inhibitor",
               "#custom-mic", "#custom-cpu", "#custom-gpu", "#custom-vram", "#custom-ram", "#custom-cpu-temp",
               "#custom-gpu-temp", "#custom-llm", "#custom-gcal", "#custom-notifications", "#custom-power-menu")
_CLUSTER_IDS = frozenset(("#battery", "#backlight", "#pulseaudio", "#custom-mic", "#custom-cpu", "#custom-gpu",
                          "#custom-vram", "#custom-ram", "#custom-cpu-temp", "#custom-gpu-temp"))


# --------------------------------------------------------------------------
# files

def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_if_changed(path: Path, text: str) -> bool:
    """Atomic replace, only when the text differs. A symlink (HM leftover) is
    always replaced: Waybar resolves CSS symlinks once at start
    (css_reload_helper.cpp:48-57) and would keep watching the old target."""
    try:
        if not path.is_symlink() and path.read_text() == text:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".sway-apps-", suffix=path.suffix or ".tmp")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    return True


def load_catalog(path: Path | None = None) -> dict[str, Any]:
    data = _read_json(path or CATALOG_FILE)
    if not isinstance(data, dict):
        return json.loads(json.dumps(FALLBACK_CATALOG))
    for k, v in FALLBACK_CATALOG.items():
        if not isinstance(data.get(k), type(v)):
            data[k] = json.loads(json.dumps(v))
    return data


def load_local() -> dict[str, Any]:
    data = _read_json(LOCAL_FILE)
    if not isinstance(data, dict):
        data = {}
    if not isinstance(data.get("bars"), dict):
        data["bars"] = {}
    if not isinstance(data.get("connectors"), dict):
        data["connectors"] = {}
    return data


def save_local(data: dict[str, Any]) -> None:
    write_if_changed(LOCAL_FILE, json.dumps(data, indent=1, sort_keys=True) + "\n")


def _mtime(p: Path) -> int:
    try:
        return os.stat(p).st_mtime_ns
    except OSError:
        return 0


# --------------------------------------------------------------------------
# model

def clamp_size(v: Any) -> int:
    try:
        return max(SIZE_MIN, min(SIZE_MAX, int(v)))
    except (TypeError, ValueError):
        return 100


def clean_layout(raw: Any, modules: dict[str, Any]) -> dict[str, list[str]]:
    """Known modules only (a template copied from another machine may name a
    module this host's catalog filtered out), each at most once per bar."""
    out: dict[str, list[str]] = {}
    seen: set[str] = set()
    raw = raw if isinstance(raw, dict) else {}
    for sec in SECTIONS:
        lst = []
        for name in raw.get(sec) or ():
            if isinstance(name, str) and name in modules and name not in seen:
                seen.add(name)
                lst.append(name)
        out[sec] = lst
    return out


@dataclass
class Bar:
    key: str                    # monitor role, or OTHER
    criteria: str = ""          # hardware id ("" for OTHER)
    name: str = ""
    primary: bool = False
    visible: bool = True        # effective setting (saved default < local)
    ws: str = "output"
    size: int = 100
    template: str = "secondary"
    layout: dict[str, list[str]] = field(default_factory=dict)
    saved: dict[str, Any] = field(default_factory=dict)   # the default (profile JSON / built-in)
    local: dict[str, Any] = field(default_factory=dict)   # live overrides

    @property
    def bar_id(self) -> str:
        return f"wb-{self.key}"

    def to_dict(self) -> dict[str, Any]:
        return {"key": self.key, "bar_id": self.bar_id, "criteria": self.criteria, "name": self.name,
                "primary": self.primary, "visible": self.visible, "ws": self.ws, "size": self.size,
                "template": self.template, "layout": self.layout, "default": self.saved, "live": self.local}


class Model:
    def __init__(self, state, catalog: dict[str, Any] | None = None, local: dict[str, Any] | None = None) -> None:
        self.state = state
        self.catalog = catalog if catalog is not None else load_catalog()
        self.local = local if local is not None else load_local()
        self.feat = state.feature(SETTINGS_KEY)
        self.modules: dict[str, Any] = self.catalog.get("modules") or {}
        self.bars = self._build()
        self.by_key = {b.key: b for b in self.bars}
        self.by_criteria = {b.criteria: b for b in self.bars if b.criteria}

    def template_layout(self, name: str) -> dict[str, list[str]]:
        raw = (self.feat.get("templates") or {}).get(name) or self.catalog["layouts"].get(name) \
            or self.catalog["layouts"].get("primary")
        return clean_layout(raw, self.modules)

    def default_template_layout(self, name: str) -> dict[str, list[str]]:
        return clean_layout(self.catalog["layouts"].get(name) or self.catalog["layouts"].get("primary"), self.modules)

    def _bar(self, key: str, criteria: str, name: str, primary: bool, default_visible: bool) -> Bar:
        s = (self.feat.get("bars") or {}).get(key) or {}
        loc = self.local["bars"].get(key) or {}
        saved = {"visible": bool(s.get("visible", default_visible)),
                 "ws": s.get("ws") if s.get("ws") in WS_MODES else "output",
                 "size": clamp_size(s.get("size", 100))}
        live: dict[str, Any] = {}
        if isinstance(loc.get("visible"), bool):
            live["visible"] = loc["visible"]
        if loc.get("ws") in WS_MODES:
            live["ws"] = loc["ws"]
        if "size" in loc:
            live["size"] = clamp_size(loc["size"])
        eff = {**saved, **live}
        template = s.get("template") if s.get("template") in BAR_TEMPLATES else ("primary" if primary else "secondary")
        if template == "custom":
            layout = clean_layout(s.get("modules"), self.modules)
        else:
            layout = self.template_layout(template)
        return Bar(key=key, criteria=criteria, name=name, primary=primary, visible=eff["visible"], ws=eff["ws"],
                   size=eff["size"], template=template, layout=layout, saved=saved, local=live)

    def _build(self) -> list[Bar]:
        policy = self.catalog.get("default_visible", "primary")
        mons = self.state.monitors()
        primary = next((m.id for m in mons if m.primary), mons[0].id if mons else None)
        bars = [self._bar(m.id, m.criteria, m.name or m.criteria, m.id == primary, policy == "all" or m.id == primary)
                for m in mons]
        # No registry at all: the catch-all is the only bar, so it starts visible.
        bars.append(self._bar(OTHER, "", "Unregistered outputs", False, not mons))
        return bars

    def bar_for_output(self, o: dict[str, Any]) -> Bar:
        return self.by_criteria.get(mon.hw_id(o)) or self.by_key[OTHER]

    def resolve(self, ref: str, outputs: list[dict[str, Any]] | None = None) -> Bar:
        """Bar by role key, bar id (wb-x) or connector name."""
        if ref in self.by_key:
            return self.by_key[ref]
        if ref.startswith("wb-") and ref[3:] in self.by_key:
            return self.by_key[ref[3:]]
        for o in outputs or ():
            if o.get("name") == ref:
                return self.bar_for_output(o)
        raise KeyError(f"no bar {ref!r} (bars: {', '.join(b.key for b in self.bars)})")


# --------------------------------------------------------------------------
# rendering

def _scaled(v: float, pct: int) -> int:
    return max(0, round(v * pct / 100))


def render_config(model: Model, connectors: dict[str, str]) -> str:
    cat = model.catalog
    base = cat["bar"]
    sizes = cat["sizes"]
    named: list[str] = []
    for b in model.bars:
        if b.key != OTHER:
            named.extend(x for x in (connectors.get(b.key), b.criteria) if x)
    bars = []
    for b in model.bars:
        if b.key == OTHER:
            output: list[str] = [f"!{x}" for x in named] + ["*"]
        else:
            output = [x for x in (connectors.get(b.key), b.criteria) if x]
        cfg: dict[str, Any] = {"name": b.bar_id, "id": b.bar_id, "ipc": True, "output": output}
        cfg.update(base)
        if b.size != 100 and isinstance(base.get("height"), int):
            cfg["height"] = _scaled(base["height"], b.size)
        # Waybar's "dock" preset is layer BOTTOM (bar.cpp PRESET_MODES): without
        # this, sway's `mode dock` would push the bar under floating windows.
        cfg["modes"] = {"dock": {"layer": base.get("layer", "top")}}
        cfg["reload_style_on_change"] = True
        for sec in SECTIONS:
            cfg[f"modules-{sec}"] = list(b.layout.get(sec, ()))
        for sec in SECTIONS:
            for name in b.layout.get(sec, ()):
                d = model.modules.get(name)
                if not isinstance(d, dict):
                    continue
                if name == WORKSPACES:
                    # "This monitor" is CSS on one all-outputs module: all-outputs
                    # is read once per module, so it cannot follow the live rules.
                    d = {**d, "all-outputs": True}
                elif name == "tray" and b.size != 100:
                    d = {**d, "icon-size": _scaled(sizes.get("tray_icon", 16), b.size)}
                cfg[name] = d
        bars.append(cfg)
    return json.dumps(bars, indent=1, ensure_ascii=False) + "\n"


BARS_HEADER = """# Generated by sway-apps (waybar) -- DO NOT EDIT BY HAND.
# Waybar draws these bars ("ipc": true); sway only holds their mode, and
# `swaymsg reload` resends it from here. Toggle: Hyper+Shift+H / sway-apps waybar.
"""


def render_bars(model: Model) -> str:
    out = [BARS_HEADER]
    for b in model.bars:
        out.append(f"bar {b.bar_id} {{\n    swaybar_command true\n    mode {'dock' if b.visible else 'invisible'}\n}}\n")
    return "".join(out)


def render_style(base_css: str) -> str:
    # @import must precede every rule; the generated selectors all start with
    # window#waybar.<bar>, which outranks the base selectors anyway.
    return (f"/* Generated by sway-apps from {BASE_CSS_FILE} -- DO NOT EDIT BY HAND. */\n"
            f'@import url("{CSS_FILE}");\n\n{base_css}')


@dataclass
class Win:
    """One bar window: Waybar draws a bar per matching output."""
    key: str
    output: str
    enabled: bool
    fullscreen: bool

    @property
    def effective(self) -> bool:
        return self.enabled and not self.fullscreen


def _fullscreen_mode(node: dict[str, Any]) -> int:
    best = 0
    stack = [node]
    while stack:
        n = stack.pop()
        fm = n.get("fullscreen_mode") or 0
        if fm > best:
            best = fm
            if best == 2:
                return 2
        stack.extend(n.get("nodes") or ())
        stack.extend(n.get("floating_nodes") or ())
    return best


def windows(model: Model, tree: dict[str, Any]) -> list[Win]:
    wins: list[Win] = []
    global_fs = False
    for o in tree.get("nodes") or ():
        name = o.get("name") or ""
        if o.get("type") != "output" or name.startswith("__") or mon.skip_output(name) or o.get("active") is False:
            continue
        cur = o.get("current_workspace")
        fs = 0
        for ws in o.get("nodes") or ():
            if ws.get("name") == cur:
                fs = _fullscreen_mode(ws)
                break
        global_fs = global_fs or fs == 2
        b = model.bar_for_output(o)
        wins.append(Win(b.key, name, b.visible, fs > 0))
    if global_fs:
        for w in wins:
            w.fullscreen = True
    return wins


CSS_HEADER = "/* Generated by sway-apps (waybar): workspace mode, auto-all, sizes. DO NOT EDIT BY HAND. */\n"
_COLLAPSE = "{ min-width: 0; min-height: 0; padding: 0; margin: 0; border: 0; font-size: 0; opacity: 0; box-shadow: none; }"


def render_css(model: Model, wins: list[Win]) -> str:
    eff = [w for w in wins if w.effective]
    solo = eff[0] if len(eff) == 1 else None
    out = [CSS_HEADER]
    for b in model.bars:
        sel = f"window#waybar.{b.bar_id}"
        if b.ws == "output":
            ws_sel: str | None = sel
            if solo is not None and solo.key == b.key:
                # The only visible bar shows every workspace. The catch-all may
                # draw on several outputs: exempt just the one that is visible.
                ws_sel = None if sum(1 for w in wins if w.key == b.key) <= 1 else f"{sel}:not(.{solo.output})"
            if ws_sel:
                btn = f"{ws_sel} #workspaces button:not(.current_output)"
                out.append(f"{btn},\n{btn} label {_COLLAPSE}\n")
        if b.size != 100:
            out.append(_size_css(sel, b.size, model.catalog["sizes"]))
    return "".join(out)


def _size_css(sel: str, pct: int, sizes: dict[str, Any]) -> str:
    def px(v: float) -> str:
        return f"{_scaled(v, pct)}px"
    mods = ",\n".join(f"{sel} {m}" for m in _MODULE_IDS)
    pills = ",\n".join(f"{sel} {m}" for m in _MODULE_IDS if m not in _CLUSTER_IDS)
    return (f"{sel} * {{ font-size: {px(sizes.get('font', 13))}; }}\n"
            f"{sel} #workspaces {{ margin: {px(4)} {px(8)}; }}\n"
            f"{sel} #workspaces button {{ min-width: {px(20)}; padding: 0 {px(5)}; margin: {px(2)}; }}\n"
            f"{sel} .modules-left {{ margin: {px(4)} {px(4)}; }}\n"
            f"{sel} #tray {{ margin: {px(4)} {px(4)}; padding: {px(4)} {px(8)}; }}\n"
            f"{mods} {{ padding: {px(4)} {px(12)}; }}\n"
            f"{pills} {{ margin: {px(4)} {px(4)}; }}\n"
            f"{sel} #custom-notifications.hidden {{ margin: 0; padding: 0; }}\n")


# --------------------------------------------------------------------------
# Waybar process

def waybar_pid() -> int | None:
    env = os.environ.get("SWAY_APPS_WAYBAR_PID", "")
    if env:
        return int(env) if env.isdigit() else None
    if paths.E2E:
        return None  # never signal the live session's Waybar from the suite
    try:
        out = subprocess.run(["systemctl", "--user", "show", "-p", "MainPID", "--value", "waybar.service"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return int(out) if out.isdigit() and out != "0" else None


def _proc_start(pid: int) -> float | None:
    try:
        with open(f"/proc/{pid}/stat") as fh:
            stat = fh.read()
        with open("/proc/stat") as fh:
            btime = next(int(line.split()[1]) for line in fh if line.startswith("btime"))
    except (OSError, StopIteration, ValueError):
        return None
    ticks = int(stat[stat.rfind(")") + 2:].split()[19])
    return btime + ticks / os.sysconf("SC_CLK_TCK")


def reload_waybar(since: float | None = None) -> bool:
    """SIGUSR2 (safe since sway-apps-tray owns the SNI watcher). With `since`,
    a Waybar started after that moment already read the change: skip."""
    pid = waybar_pid()
    if not pid:
        return False
    if since is not None:
        started = _proc_start(pid)
        if started is not None and started > since:
            return False
    try:
        os.kill(pid, signal.SIGUSR2)
    except OSError as exc:
        _log.warning("SIGUSR2 to waybar %s failed: %s", pid, exc)
        return False
    _log.info("waybar %s reloaded", pid)
    return True


# --------------------------------------------------------------------------
# runtime: one per process (the daemon keeps it; CLI/GUI make one per call)

class SwayLink:
    """The calls this module makes, over an ipc.Connection or a watch Ctx."""

    def __init__(self, conn: ipc.Connection | None = None, ctx: Any = None) -> None:
        self._conn, self._ctx = conn, ctx

    @classmethod
    def connect(cls) -> "SwayLink | None":
        try:
            return cls(conn=ipc.Connection())
        except (ipc.IpcError, OSError):
            return None

    def _c(self) -> ipc.Connection:
        return self._ctx.conn if self._ctx is not None else self._conn

    def command(self, cmd: str) -> list[dict[str, Any]]:
        return self._ctx.command(cmd) if self._ctx is not None else self._conn.command(cmd)

    def tree(self) -> dict[str, Any]:
        return self._ctx.tree() if self._ctx is not None else self._conn.tree()

    def outputs(self) -> list[dict[str, Any]]:
        return self._c().outputs()

    def bar_ids(self) -> list[str]:
        return self._c().request(ipc.GET_BAR_CONFIG) or []

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()


class Runtime:
    def __init__(self, state=None) -> None:
        self._state = state
        self._model: Model | None = None
        self._stamp: tuple | None = None
        self._css: str | None = None

    def _sources(self) -> tuple:
        return (_mtime(paths.common_file()), _mtime(paths.profile_file()), _mtime(CATALOG_FILE), _mtime(LOCAL_FILE))

    def model(self) -> Model:
        if self._state is not None:
            if self._model is None:
                self._model = Model(self._state)
            return self._model
        stamp = self._sources()
        if self._model is None or stamp != self._stamp:
            from .state import State
            self._model = Model(State())
            self._stamp = stamp
        return self._model

    def invalidate(self) -> None:
        self._model = None

    def _local_written(self) -> None:
        if self._state is None:
            self._stamp = self._sources()

    # ---- live state -------------------------------------------------------
    def set_live(self, keys: list[str], sway: SwayLink | None, **values: Any) -> dict[str, Any]:
        """Set visible / ws / size for bars (machine-local). visible=None toggles."""
        m = self.model()
        changed_vis: list[Bar] = []
        resize = False
        for k in keys:
            b = m.by_key[k]
            loc = m.local["bars"].setdefault(k, {})
            if "visible" in values:
                v = (not b.visible) if values["visible"] is None else bool(values["visible"])
                if v != b.visible:
                    changed_vis.append(b)
                b.visible = loc["visible"] = v
            if "ws" in values:
                if values["ws"] not in WS_MODES:
                    raise ValueError(f"ws must be one of {WS_MODES}")
                b.ws = loc["ws"] = values["ws"]
            if "size" in values:
                s = clamp_size(values["size"])
                resize = resize or s != b.size
                b.size = loc["size"] = s
            b.local = {kk: loc[kk] for kk in ("visible", "ws", "size") if kk in loc}
        save_local(m.local)
        self._local_written()
        res: dict[str, Any] = {"bars": {k: m.by_key[k].to_dict() for k in keys}}
        if changed_vis and sway is not None:
            cmd = "; ".join(f"bar {b.bar_id} mode {'dock' if b.visible else 'invisible'}" for b in changed_vis)
            try:
                sway.command(cmd)
            except ipc.IpcError as exc:
                _log.warning("%s: %s (bar unknown to sway? syncing)", cmd, exc)
                res["sync"] = self.sync(sway, reload=True)
        write_if_changed(BARS_FILE, render_bars(m))
        if resize:
            res["sync"] = self.sync(sway, reload=True)
        else:
            res["css_changed"] = self.refresh_css(sway)
        return res

    def refresh_css(self, sway: SwayLink | None) -> bool:
        m = self.model()
        wins: list[Win] = []
        if sway is not None:
            try:
                wins = windows(m, sway.tree())
            except (ipc.IpcError, OSError) as exc:
                _log.warning("get_tree failed: %s", exc)
        text = render_css(m, wins)
        if text == self._css:
            return False
        changed = write_if_changed(CSS_FILE, text)
        self._css = text
        return changed

    # ---- full regeneration -------------------------------------------------
    def sync(self, sway: SwayLink | None, reload: bool = True) -> dict[str, Any]:
        """Regenerate every file. reload: also bring sway's bar list and Waybar
        up to date (sway reload only when a bar id is new to it: sway cannot
        create a bar at runtime)."""
        m = self.model()
        res: dict[str, Any] = {}
        conns = dict(m.local.get("connectors") or {})
        outs: list[dict[str, Any]] = []
        if sway is not None:
            try:
                outs = sway.outputs()
            except (ipc.IpcError, OSError):
                outs = []
        for o in outs:
            b = m.by_criteria.get(mon.hw_id(o))
            if b is not None:
                conns[b.key] = o["name"]
        local_dirty = conns != m.local.get("connectors")
        m.local["connectors"] = conns
        base = ""
        try:
            base = BASE_CSS_FILE.read_text()
        except OSError:
            _log.warning("%s missing; style.css without base", BASE_CSS_FILE)
        cfg_changed = write_if_changed(CONFIG_FILE, render_config(m, conns))
        res["style_changed"] = write_if_changed(STYLE_FILE, render_style(base))
        bars_changed = write_if_changed(BARS_FILE, render_bars(m))
        res.update(config_changed=cfg_changed, bars_changed=bars_changed)
        sway_reloaded = False
        if reload and sway is not None:
            try:
                have = set(sway.bar_ids())
                if not {b.bar_id for b in m.bars} <= have:
                    sway.command("reload")
                    sway_reloaded = True
                elif bars_changed:
                    sway.command("; ".join(f"bar {b.bar_id} mode {'dock' if b.visible else 'invisible'}" for b in m.bars))
            except (ipc.IpcError, OSError) as exc:
                _log.warning("sway bar sync failed: %s", exc)
        res["sway_reloaded"] = sway_reloaded
        pending = m.local.get("pending_reload")
        if cfg_changed or sway_reloaded:
            pending = time.time()
        if reload and pending:
            # a Waybar started after the change already has it
            res["waybar_reloaded"] = reload_waybar(None if (cfg_changed or sway_reloaded) else pending)
            pending = None
        if pending != m.local.get("pending_reload"):
            local_dirty = True
            if pending:
                m.local["pending_reload"] = pending
            else:
                m.local.pop("pending_reload", None)
        if local_dirty:
            save_local(m.local)
            self._local_written()
        self._css = None
        res["css_changed"] = self.refresh_css(sway)
        return res


# --------------------------------------------------------------------------
# saved defaults (profile JSON)

def _profile_feat(state) -> dict[str, Any]:
    cur = (state.profile.get("settings") or {}).get(SETTINGS_KEY)
    return json.loads(json.dumps(cur)) if isinstance(cur, dict) else {}


def save_default(state) -> dict[str, Any]:
    """Live values of every bar become the profile default; local overrides go."""
    m = Model(state)
    feat = _profile_feat(state)
    bars = feat.setdefault("bars", {})
    for b in m.bars:
        bars.setdefault(b.key, {}).update(visible=b.visible, ws=b.ws, size=b.size)
    state.set_feature(SETTINGS_KEY, feat, "profile")
    local = load_local()
    local["bars"] = {}
    save_local(local)
    return feat


def reset_local() -> None:
    local = load_local()
    local["bars"] = {}
    save_local(local)


def set_template(state, name: str, layout: dict[str, list[str]] | None) -> None:
    """None = back to the Nix default."""
    if name not in TEMPLATES:
        raise ValueError(f"template must be one of {TEMPLATES}")
    feat = _profile_feat(state)
    tpl = feat.setdefault("templates", {})
    if layout is None:
        tpl.pop(name, None)
    else:
        tpl[name] = clean_layout(layout, load_catalog().get("modules") or {})
    state.set_feature(SETTINGS_KEY, feat, "profile")


def set_bar_template(state, key: str, template: str, layout: dict[str, list[str]] | None = None) -> None:
    if template not in BAR_TEMPLATES:
        raise ValueError(f"template must be one of {BAR_TEMPLATES}")
    feat = _profile_feat(state)
    entry = feat.setdefault("bars", {}).setdefault(key, {})
    entry["template"] = template
    if template == "custom":
        entry["modules"] = clean_layout(layout or {}, load_catalog().get("modules") or {})
    else:
        entry.pop("modules", None)
    state.set_feature(SETTINGS_KEY, feat, "profile")


def status(model: Model, sway: SwayLink | None) -> dict[str, Any]:
    wins: list[Win] = []
    outs: list[dict[str, Any]] = []
    if sway is not None:
        try:
            wins = windows(model, sway.tree())
            outs = sway.outputs()
        except (ipc.IpcError, OSError):
            pass
    eff = [w for w in wins if w.effective]
    rows = []
    for b in model.bars:
        mine = [w for w in wins if w.key == b.key]
        d = b.to_dict()
        d["outputs"] = [w.output for w in mine]
        d["fullscreen"] = [w.output for w in mine if w.fullscreen]
        d["effective"] = any(w.effective for w in mine)
        d["shows_all"] = b.ws == "all" or (len(eff) == 1 and eff[0].key == b.key)
        rows.append(d)
    return {"bars": rows, "focused_output": next((o["name"] for o in outs if o.get("focused")), None),
            "effective_count": len(eff)}


# --------------------------------------------------------------------------
# generate.apply hooks (features.before_reload / after_apply)

def _owns_session() -> bool:
    # Tests and cli-smoke.sh redirect the include (SWAY_APPS_INCLUDE /
    # paths.INCLUDE_FILE) but not XDG_CONFIG_HOME: they must not rewrite the
    # live Waybar config nor reload it.
    return paths.INCLUDE_FILE == paths.XDG_CONFIG_HOME / "sway" / "sway-apps.conf"


def before_reload(state) -> None:
    """Files the coming sway reload must see (the bar blocks)."""
    if not _owns_session():
        return
    sway = SwayLink.connect()
    try:
        Runtime(state).sync(sway, reload=False)
    finally:
        if sway:
            sway.close()


def after_apply(state, reloaded: bool) -> None:
    if not reloaded or not _owns_session():
        return
    sway = SwayLink.connect()
    try:
        Runtime(state).sync(sway, reload=True)
    finally:
        if sway:
            sway.close()


# --------------------------------------------------------------------------
# watch daemon

def setup_watch(reg) -> None:
    rt = Runtime()
    pending = {"css": False}

    def link(ctx) -> SwayLink:
        return SwayLink(ctx=ctx)

    def css_now(ctx) -> None:
        pending["css"] = False
        rt.refresh_css(link(ctx))

    def css_soon(ctx) -> None:
        if not pending["css"]:
            pending["css"] = True
            ctx.schedule("waybar.css", CSS_THROTTLE, css_now)

    def on_workspace(ev, ctx) -> None:
        if (ev or {}).get("change") in WORKSPACE_CHANGES:
            css_soon(ctx)

    def on_window(ev, ctx) -> None:
        if (ev or {}).get("change") in WINDOW_CHANGES:
            css_soon(ctx)

    def on_output(_ev, ctx) -> None:
        css_soon(ctx)
        ctx.schedule("waybar.outputs", OUTPUTS_SETTLE, lambda c: rt.sync(link(c), reload=True))

    def verb(args: list[str], ctx) -> None:
        t0 = time.perf_counter()
        sway = link(ctx)
        m = rt.model()
        op = args[0] if args else "toggle"
        rest = args[1:]
        value = {"toggle": None, "show": True, "hide": False}.get(op, "?")
        if value == "?":
            if op == "sync":
                rt.sync(sway, reload=True)
            else:
                _log.warning("waybar verb %r unknown", op)
            return
        if rest and rest[0] == "--all":
            keys = [b.key for b in m.bars]
            if value is None:
                value = not any(b.visible for b in m.bars)
        else:
            outs = sway.outputs()
            if rest:
                keys = [m.resolve(rest[-1], outs).key]
            else:
                o = next((x for x in outs if x.get("focused")), None)
                if o is None:
                    return
                keys = [m.bar_for_output(o).key]
        res = rt.set_live(keys, sway, visible=value)
        _log.info("waybar %s %s in %.1f ms", op, " ".join(rest), (time.perf_counter() - t0) * 1000)
        _log.debug("%s", res)

    reg.verb("waybar", verb)
    reg.on("workspace", on_workspace)
    reg.on("window", on_window)
    reg.on("output", on_output)
    # Login / daemon restart: connectors may have moved, the catalog may be new.
    reg.schedule("waybar.start", 0.0, lambda c: rt.sync(link(c), reload=True))


# --------------------------------------------------------------------------
# CLI

def _split(v: str | None) -> list[str] | None:
    if v is None:
        return None
    return [x.strip() for x in v.split(",") if x.strip()]


def _layout_args(a, base: dict[str, list[str]]) -> dict[str, list[str]]:
    out = {s: list(base.get(s, ())) for s in SECTIONS}
    for s in SECTIONS:
        v = _split(getattr(a, s, None))
        if v is not None:
            out[s] = v
    return out


def _cli(fn):
    def run(a) -> int:
        from . import cli
        sway = SwayLink.connect()
        try:
            data, human = fn(a, sway)
        except (KeyError, ValueError) as exc:
            raise cli.CliError(str(exc).strip("'\"")) from exc
        finally:
            if sway:
                sway.close()
        cli._out(a, data, human)
        return 0
    return run


def _human_status(st: dict[str, Any]) -> None:
    from .cli import _table
    rows = []
    for b in st["bars"]:
        live = "*" if b["live"] else ""
        rows.append([b["bar_id"], ",".join(b["outputs"]) or "-", ("on" if b["visible"] else "off") + live,
                     ("ALL" if b["shows_all"] else b["ws"]), f"{b['size']}%", b["template"],
                     "yes" if b["effective"] else ("fullscreen" if b["fullscreen"] else "no")])
    _table(rows, ["bar", "outputs", "visible", "workspaces", "size", "template", "drawn"])
    print("\n* = live change not saved as default (sway-apps waybar save-default)")


def _cmd_status(a, sway):
    st = status(Runtime().model(), sway)
    return st, lambda: _human_status(st)


def _targets(a, rt: Runtime, sway: SwayLink | None) -> list[str]:
    m = rt.model()
    if getattr(a, "all", False):
        return [b.key for b in m.bars]
    ref = getattr(a, "output", None) or getattr(a, "bar", None)
    outs = sway.outputs() if sway else []
    if ref:
        return [m.resolve(ref, outs).key]
    o = next((x for x in outs if x.get("focused")), None)
    if o is None:
        raise ValueError("no focused output (sway not reachable?): pass --bar or --all")
    return [m.bar_for_output(o).key]


def _cmd_visible(a, sway):
    rt = Runtime()
    keys = _targets(a, rt, sway)
    value = {"toggle": None, "show": True, "hide": False}[a.verb]
    if value is None and a.all:
        value = not any(b.visible for b in rt.model().bars)
    res = rt.set_live(keys, sway, visible=value)
    return res, lambda: print(", ".join(f"{b['bar_id']}: {'shown' if b['visible'] else 'hidden'}" for b in res["bars"].values()))


def _cmd_ws(a, sway):
    rt = Runtime()
    key = rt.model().resolve(a.bar, sway.outputs() if sway else []).key
    res = rt.set_live([key], sway, ws=a.mode)
    return res, lambda: print(f"wb-{key}: workspaces {a.mode}")


def _cmd_size(a, sway):
    rt = Runtime()
    key = rt.model().resolve(a.bar, sway.outputs() if sway else []).key
    res = rt.set_live([key], sway, size=a.pct)
    return res, lambda: print(f"wb-{key}: size {res['bars'][key]['size']}%")


def _persist(a, state, message: str, sway) -> dict[str, Any]:
    from . import cli
    res = cli._persist(a, state, message)
    res["sync"] = Runtime().sync(sway, reload=True)
    return res


def _cmd_save_default(a, sway):
    from .state import State
    st = State()
    feat = save_default(st)
    res = _persist(a, st, "waybar: save live bar state as default", sway)
    res["waybar"] = feat
    return res, lambda: print("saved as the profile default: " + ", ".join(
        f"{k}={'on' if v.get('visible') else 'off'}/{v.get('ws')}/{v.get('size')}%" for k, v in feat.get("bars", {}).items()))


def _cmd_reset(a, sway):
    reset_local()
    res = Runtime().sync(sway, reload=True)
    return res, lambda: print("live bar state dropped; profile defaults apply")


def _cmd_apply(a, sway):
    res = Runtime().sync(sway, reload=not a.no_reload)
    return res, lambda: print(json.dumps(res))


def _cmd_tpl_list(a, sway):
    m = Runtime().model()
    data = {"pool": sorted(m.modules), "templates": {t: m.template_layout(t) for t in TEMPLATES},
            "defaults": {t: m.default_template_layout(t) for t in TEMPLATES},
            "bars": {b.key: {"template": b.template, "layout": b.layout} for b in m.bars}}

    def human() -> None:
        for t in TEMPLATES:
            lay = data["templates"][t]
            print(f"{t}: " + " | ".join(f"{s}: {' '.join(lay[s]) or '-'}" for s in SECTIONS))
        for k, v in data["bars"].items():
            print(f"wb-{k}: {v['template']}")
        print("modules: " + " ".join(data["pool"]))
    return data, human


def _cmd_tpl_set(a, sway):
    from .state import State
    st = State()
    lay = _layout_args(a, Model(st).template_layout(a.name))
    set_template(st, a.name, lay)
    res = _persist(a, st, f"waybar: template {a.name}", sway)
    return res, lambda: print(f"template {a.name} saved")


def _cmd_tpl_reset(a, sway):
    from .state import State
    st = State()
    set_template(st, a.name, None)
    res = _persist(a, st, f"waybar: template {a.name} back to default", sway)
    return res, lambda: print(f"template {a.name} = Nix default")


def _cmd_tpl_use(a, sway):
    from .state import State
    st = State()
    m = Model(st)
    b = m.resolve(a.bar, sway.outputs() if sway else [])
    lay = _layout_args(a, b.layout) if a.template == "custom" else None
    set_bar_template(st, b.key, a.template, lay)
    res = _persist(a, st, f"waybar: wb-{b.key} uses template {a.template}", sway)
    return res, lambda: print(f"wb-{b.key}: template {a.template}")


def register_cli(sub) -> None:
    w = sub.add_parser("waybar", help="per-monitor Waybar: visibility, workspaces mode, size, widget templates") \
        .add_subparsers(dest="sub", required=True)
    w.add_parser("status").set_defaults(func=_cli(_cmd_status))
    for verb in ("toggle", "show", "hide"):
        x = w.add_parser(verb, help=f"{verb} a bar (default: the focused monitor's); machine-local, survives reboot")
        g = x.add_mutually_exclusive_group()
        g.add_argument("--output", help="connector, e.g. DP-1")
        g.add_argument("--bar", help="role (main), bar id (wb-main) or 'other'")
        g.add_argument("--all", action="store_true")
        x.set_defaults(func=_cli(_cmd_visible), verb=verb)
    x = w.add_parser("ws", help="workspaces widget: this monitor's only, or all (one visible bar always shows all)")
    x.add_argument("bar"); x.add_argument("mode", choices=WS_MODES)
    x.set_defaults(func=_cli(_cmd_ws))
    x = w.add_parser("size", help=f"bar scale in %% ({SIZE_MIN}-{SIZE_MAX}): font, height, paddings, tray icons")
    x.add_argument("bar"); x.add_argument("pct", type=int)
    x.set_defaults(func=_cli(_cmd_size))
    x = w.add_parser("save-default", help="live state of every bar -> profile JSON (committed)")
    x.add_argument("--no-git", action="store_true")
    x.set_defaults(func=_cli(_cmd_save_default))
    w.add_parser("reset", help="drop live changes; the profile default applies").set_defaults(func=_cli(_cmd_reset))
    x = w.add_parser("apply", help="regenerate config, CSS and sway bar blocks")
    x.add_argument("--no-reload", action="store_true")
    x.set_defaults(func=_cli(_cmd_apply))
    t = w.add_parser("template", help="widget templates (primary, secondary) and per-bar choice") \
        .add_subparsers(dest="sub2", required=True)
    t.add_parser("list").set_defaults(func=_cli(_cmd_tpl_list))

    def sections(p) -> None:
        for s in SECTIONS:
            p.add_argument(f"--{s}", help="comma-separated modules (empty string clears)")
        p.add_argument("--no-git", action="store_true")
    x = t.add_parser("set", help="edit a template (sections not given stay)"); x.add_argument("name", choices=TEMPLATES)
    sections(x); x.set_defaults(func=_cli(_cmd_tpl_set))
    x = t.add_parser("reset", help="template back to the Nix default"); x.add_argument("name", choices=TEMPLATES)
    x.add_argument("--no-git", action="store_true"); x.set_defaults(func=_cli(_cmd_tpl_reset))
    x = t.add_parser("use", help="which template a bar uses; custom = its own lists")
    x.add_argument("bar"); x.add_argument("template", choices=BAR_TEMPLATES)
    sections(x); x.set_defaults(func=_cli(_cmd_tpl_use))
