"""Output layout owner (plan §0 + §4, SWAY-8/9).

On machines with swayAppsOwnsOutputs (paths.SWAY_FEATURES has "owns_outputs")
sway-apps is the ONLY writer of the output layout: kanshi and nwg-displays'
~/.config/sway/outputs include are dropped by Nix, and the include carries
`output "<make model serial>" {mode, position, scale, transform, adaptive_sync,
enable|disable}` keyed by hardware id (connectors drift) plus `xwayland_dpi`.
State: profile JSON settings.displays = {outputs: {hw_id: OutputConf},
xwayland_dpi: 0 (= the Nix default), imported_from}.

Changes from the GUI (and `set --revert-after N`) are LIVE ONLY until "Keep":
a pending record in LOCAL_STATE_DIR plus a detached guard process revert them
when the deadline passes, so a crashed GUI or a black screen never strands the
user. Measured 2026-10-14 (nested sway 1.11): `reload` resets EVERY output to
the config, dropping runtime `output` changes (a runtime-disabled output with
no config line comes back enabled) — a reload during the pending window is
therefore also a revert, and Keep must regenerate the include before reloading.
"""
from __future__ import annotations

import json
import os
import re
import struct
import secrets
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from . import log, paths, swayipc
from .monitors import hw_id, skip_output

_log = log.get("displays")

SETTINGS_KEY = "displays"
SETTINGS_DEFAULTS: dict = {"outputs": {}, "xwayland_dpi": 0, "imported_from": ""}

GUI_PANELS: list = []  # the canvas lives in the existing "monitors" section (gui/panels_monitors.py)

FEATURE = "owns_outputs"
TRANSFORMS = ("normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270")
ROTATED = frozenset(("90", "270", "flipped-90", "flipped-270"))
SCALE_FILTERS = ("", "linear", "nearest", "smart")
# wp-fractional-scale-v1: sway rounds every scale to 1/120 (config/output.c:471-474).
SCALE_DEN = 120
DEFAULT_REVERT_SECONDS = 15

FORCED_SCALE_WARNING = ("Not an exact scale: the logical size is fractional, so gamescope and fullscreen "
                        "apps get rescaled and some apps render blurry.")
DPI_LIFETIME_NOTE = ("Applies when Xwayland next starts: it lives while ANY X11 client (Steam, Wine, the meter) "
                     "is open, so close them all first.")


def owns() -> bool:
    return FEATURE in paths.SWAY_FEATURES


def nwg_file() -> Path:
    return paths.XDG_CONFIG_HOME / "sway" / "outputs"


def pending_file() -> Path:
    return paths.LOCAL_STATE_DIR / "displays-pending.json"


def nix_dpi() -> int:
    """swayXwaylandDpi from Nix (the default when the profile sets none)."""
    try:
        return int(os.environ.get("SWAY_APPS_XWAYLAND_DPI", "0") or 0)
    except ValueError:
        return 0


# --------------------------------------------------------------------------
# scale + mode math

def norm_scale(s: float) -> float:
    return round(round(float(s) * SCALE_DEN) / SCALE_DEN, 6)


def fmt_scale(s: float) -> str:
    return f"{float(s):.6f}".rstrip("0").rstrip(".")


def parse_mode(mode: str) -> tuple[int, int, int] | None:
    """'3840x2160@120.000Hz' -> (3840, 2160, 120000 mHz); '1280x720' -> (1280, 720, 0)."""
    m = _MODE_RX.match(mode.replace("--custom", "").strip())
    if not m:
        return None
    refresh = m.group(3)
    return int(m.group(1)), int(m.group(2)), int(round(float(refresh) * 1000)) if refresh else 0


_MODE_RX = re.compile(r"^(\d+)x(\d+)(?:@([\d.]+)\s*(?:Hz)?)?$")


def fmt_mode(w: int, h: int, mhz: int) -> str:
    return f"{w}x{h}@{mhz / 1000:.3f}Hz" if mhz else f"{w}x{h}"


def oriented(w: int, h: int, transform: str) -> tuple[int, int]:
    return (h, w) if transform in ROTATED else (w, h)


_F32 = struct.Struct("=f")


def _f32(x: float) -> float:
    return _F32.unpack(_F32.pack(x))[0]


def _eff(n: int, scale: float) -> int:
    """One axis of wlr_output_effective_resolution as sway 1.11 runs it: the scale snapped
    to k/120, stored as a C float, n / scale in float, truncated. Matches every size
    measured in nested sway 2026-10-14 (4K: 1.2 -> 3199x1799, 2.4 -> 1599x899,
    1.066667 -> 3599x2024, 1.333333 -> 2880x1620, 1.666667 -> 2304x1296; 1920/1.1 -> 1745)."""
    s32 = _f32(round((float(scale) or 1.0) * SCALE_DEN) / SCALE_DEN)
    return int(_f32(float(n) / s32))


def logical_size(w: int, h: int, transform: str, scale: float) -> tuple[int, int]:
    """wlr_output_effective_resolution: transformed size / scale, float32, truncated
    (1920/1.1 -> 1745, as nwg-displays placed X13's dock monitor; 3840/1.6 -> 2400).
    Emulated (_eff), not approximated with an epsilon: several k/120 scales that are
    integral on paper are truncated by sway (3840 at 1.2 is 3199)."""
    w, h = oriented(w, h, transform)
    return _eff(w, scale), _eff(h, scale)


def is_exact(w: int, h: int, scale: float) -> bool:
    k = round(float(scale) * SCALE_DEN)
    if k <= 0 or abs(float(scale) * SCALE_DEN - k) > 1e-3:
        return False
    return (w * SCALE_DEN) % k == 0 and (h * SCALE_DEN) % k == 0


def exact_scales(w: int, h: int, transform: str = "normal", lo: float = 1.0, hi: float = 3.0) -> list[tuple[float, int, int]]:
    """Scales k/120 in [lo, hi] with integral logical width AND height:
    [(scale, logical_w, logical_h)], logical size after the transform."""
    ow, oh = oriented(w, h, transform)
    W, H = ow * SCALE_DEN, oh * SCALE_DEN
    out = []
    for k in range(int(round(lo * SCALE_DEN)), int(round(hi * SCALE_DEN)) + 1):
        if W % k == 0 and H % k == 0:
            sc = round(k / SCALE_DEN, 6)
            # integral on paper is not enough: sway divides in float32 and truncates
            if (_eff(ow, sc), _eff(oh, sc)) == (W // k, H // k):
                out.append((sc, W // k, H // k))
    return out


def suggest_dpi(scale: float) -> int:
    return int(96 * float(scale) + 0.5)


# --------------------------------------------------------------------------
# one output's configuration

@dataclass
class OutputConf:
    mode: str = ""            # "3840x2160@120.000Hz"; "" = the panel's preferred mode
    x: int = 0
    y: int = 0
    scale: float = 1.0
    transform: str = "normal"
    adaptive_sync: bool = False
    enabled: bool = True
    scale_filter: str = ""    # "" = sway's default (smart)
    connector: str = ""       # last connector seen; informational

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "OutputConf":
        return cls(mode=str(d.get("mode") or ""), x=int(d.get("x", 0)), y=int(d.get("y", 0)),
                   scale=norm_scale(d.get("scale", 1.0) or 1.0), transform=str(d.get("transform") or "normal"),
                   adaptive_sync=bool(d.get("adaptive_sync", False)), enabled=bool(d.get("enabled", True)),
                   scale_filter=str(d.get("scale_filter") or ""), connector=str(d.get("connector") or ""))

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        if not d["scale_filter"]:
            del d["scale_filter"]
        if not d["connector"]:
            del d["connector"]
        return d

    def same_layout(self, other: "OutputConf | None") -> bool:
        if other is None:
            return False
        if not self.enabled and not other.enabled:
            return True
        return (self.enabled, self.mode, self.x, self.y, norm_scale(self.scale), self.transform, self.adaptive_sync) == \
               (other.enabled, other.mode, other.x, other.y, norm_scale(other.scale), other.transform, other.adaptive_sync)

    def size(self) -> tuple[int, int] | None:
        p = parse_mode(self.mode) if self.mode else None
        return (p[0], p[1]) if p else None

    def problems(self) -> list[str]:
        out = []
        if self.mode and parse_mode(self.mode) is None:
            out.append(f"bad mode {self.mode!r} (WxH or WxH@RHz)")
        if self.transform not in TRANSFORMS:
            out.append(f"bad transform {self.transform!r}")
        if not 0.25 <= float(self.scale) <= 10:
            out.append(f"scale {self.scale} out of range")
        if self.scale_filter not in SCALE_FILTERS:
            out.append(f"bad scale_filter {self.scale_filter!r}")
        return out

    def sway_args(self) -> list[str]:
        if not self.enabled:
            return ["disable"]
        args = []
        if self.mode:
            args.append(f"mode {self.mode}")
        args += [f"position {self.x} {self.y}", f"scale {fmt_scale(self.scale)}", f"transform {self.transform}",
                 f"adaptive_sync {'on' if self.adaptive_sync else 'off'}"]
        if self.scale_filter:
            args.append(f"scale_filter {self.scale_filter}")
        args.append("enable")
        return args


def _quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_block(key: str, c: OutputConf) -> str:
    return f"output {_quote(key)} {{\n" + "".join(f"    {a}\n" for a in c.sway_args()) + "}"


def live_command(target: str, c: OutputConf) -> str:
    return f"output {_quote(target)} " + " ".join(c.sway_args())


# --------------------------------------------------------------------------
# live outputs

@dataclass
class Live:
    name: str
    hw_id: str
    make: str
    model: str
    active: bool
    conf: OutputConf
    rect: tuple[int, int, int, int]               # logical layout rect (zeros while disabled)
    modes: list[tuple[int, int, int]] = field(default_factory=list)   # (w, h, mHz), sway's order, deduplicated
    current_workspace: str | None = None
    focused: bool = False

    @property
    def native(self) -> tuple[int, int] | None:
        return self.conf.size()


def from_ipc(o: dict[str, Any]) -> Live:
    mode = o.get("current_mode") or {}
    rect = o.get("rect") or {}
    active = bool(o.get("active"))
    conf = OutputConf(
        mode=fmt_mode(mode["width"], mode["height"], int(mode.get("refresh") or 0)) if active and mode.get("width") else "",
        x=int(rect.get("x", 0)), y=int(rect.get("y", 0)), scale=norm_scale(o.get("scale") or 1.0),
        transform=str(o.get("transform") or "normal"), adaptive_sync=o.get("adaptive_sync_status") == "enabled",
        enabled=active, connector=o.get("name", ""))
    seen: set[tuple[int, int, int]] = set()
    modes = []
    for m in o.get("modes") or ():
        t = (int(m["width"]), int(m["height"]), int(m.get("refresh") or 0))
        if t not in seen:
            seen.add(t)
            modes.append(t)
    return Live(name=o.get("name", ""), hw_id=hw_id(o), make=o.get("make", ""), model=o.get("model", ""), active=active,
                conf=conf, rect=(int(rect.get("x", 0)), int(rect.get("y", 0)), int(rect.get("width", 0)), int(rect.get("height", 0))),
                modes=modes, current_workspace=o.get("current_workspace"), focused=bool(o.get("focused")))


def live(outputs: list[dict[str, Any]] | None = None) -> list[Live]:
    if outputs is None:
        outputs = swayipc.outputs() if swayipc.available() else []
    return [from_ipc(o) for o in outputs if not skip_output(o.get("name", "")) and not o.get("non_desktop")]


def connector_map(outs: list[Live] | None = None) -> dict[str, str]:
    """connector -> hw id of every output sway knows (active or not)."""
    return {o.name: o.hw_id for o in (live() if outs is None else outs)}


# --------------------------------------------------------------------------
# saved layout (profile JSON)

def saved(state) -> dict[str, OutputConf]:
    return {k: OutputConf.from_dict(v) for k, v in (state.feature(SETTINGS_KEY).get("outputs") or {}).items()}


def _profile_ns(state) -> dict[str, Any]:
    return json.loads(json.dumps((state.profile.get("settings") or {}).get(SETTINGS_KEY) or {}))


def store(state, layout: dict[str, OutputConf] | None = None, *, dpi: int | None = None, imported_from: str | None = None,
          replace: bool = False) -> None:
    """Write into the PROFILE layer (the layout is per machine)."""
    ns = _profile_ns(state)
    if layout is not None:
        outs = {} if replace else dict(ns.get("outputs") or {})
        for key, c in layout.items():
            outs[key] = c.to_dict()
        ns["outputs"] = outs
    if dpi is not None:
        ns["xwayland_dpi"] = int(dpi)
    if imported_from is not None:
        ns["imported_from"] = imported_from
    state.set_feature(SETTINGS_KEY, ns, "profile")


def merged_with_live(saved_layout: dict[str, OutputConf], outs: list[Live]) -> dict[str, OutputConf]:
    """Saved layout updated with what sway runs now. Fields sway does not
    report back (scale_filter) and disabled outputs' geometry come from the
    saved entry."""
    out = dict(saved_layout)
    for o in outs:
        prev = saved_layout.get(o.hw_id)
        c = OutputConf(**asdict(o.conf))
        if prev is not None:
            c.scale_filter = prev.scale_filter
            if not o.active:
                c = OutputConf(**{**asdict(prev), "enabled": False})
        c.connector = o.name
        out[o.hw_id] = c
    return out


def effective(state, outs: list[Live] | None = None) -> tuple[dict[str, OutputConf], str]:
    """(layout the include renders, where it comes from)."""
    lay = saved(state)
    if lay or state.feature(SETTINGS_KEY).get("imported_from"):
        return lay, "profile JSON"
    try:
        text = nwg_file().read_text()
    except OSError:
        return {}, "nothing saved yet"
    if outs is None:
        try:
            outs = live()
        except Exception:  # HM activation without a session: connectors are kept as keys
            outs = []
    lay, _notes = import_nwg(text, connector_map(outs))
    return lay, f"{nwg_file()} (not imported yet: sway-apps displays import-nwg)"


def render_include(state) -> str:
    if not owns():
        return ""
    lay, src = effective(state)
    lines = [f"\n# ---- Output layout: sway-apps owns it, keyed by hardware id (source: {src})"]
    for key, c in sorted(lay.items(), key=lambda kv: (kv[1].y, kv[1].x, kv[0])):
        lines.append(render_block(key, c))
    dpi = int(state.feature(SETTINGS_KEY).get("xwayland_dpi") or 0)
    if dpi > 0 and "xwayland_zero_scaling" in paths.SWAY_FEATURES:
        lines.append(f"xwayland_dpi {dpi}")
    return "\n".join(lines) + "\n"


def effective_dpi(state) -> tuple[int, str]:
    dpi = int(state.feature(SETTINGS_KEY).get("xwayland_dpi") or 0)
    return (dpi, "profile") if dpi > 0 else (nix_dpi(), "nix default")


def xwayland_running() -> bool:
    try:
        names = os.listdir("/proc")
    except OSError:
        return False
    for pid in names:
        if pid.isdigit():
            try:
                with open(f"/proc/{pid}/comm") as fh:
                    if fh.read().strip() == "Xwayland":
                        return True
            except OSError:
                continue
    return False


# --------------------------------------------------------------------------
# nwg-displays import

_NWG_RX = re.compile(r'output\s+(?:"([^"]*)"|(\S+))\s*\{([^}]*)\}', re.S)


def parse_nwg(text: str) -> dict[str, dict[str, str]]:
    """{name: {key: value}}; `name` is a connector, or the full description
    when nwg-displays runs with "use desc". Bare `disable`/`enable` lines
    become {"enabled": "no"/"yes"}."""
    out: dict[str, dict[str, str]] = {}
    for m in _NWG_RX.finditer(text):
        name = m.group(1) if m.group(1) is not None else m.group(2)
        props: dict[str, str] = {}
        for line in m.group(3).splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition(" ")
            if k in ("disable", "enable"):
                props["enabled"] = "yes" if k == "enable" else "no"
            else:
                props[k] = v.strip()
        out[name] = props
    return out


def import_nwg(text: str, conn_to_hw: dict[str, str]) -> tuple[dict[str, OutputConf], list[str]]:
    """nwg-displays' connector-keyed blocks -> hw-id-keyed OutputConfs. A
    connector nobody maps keeps its name as the key (sway matches it by name)."""
    lay: dict[str, OutputConf] = {}
    notes: list[str] = []
    for name, p in parse_nwg(text).items():
        if " " in name:
            key, conn = name, ""
        else:
            key, conn = conn_to_hw.get(name, name), name
            if name not in conn_to_hw:
                notes.append(f"{name}: not connected now; kept by connector name")
        c = OutputConf(connector=conn)
        if "mode" in p:
            pm = parse_mode(p["mode"])
            if pm:
                c.mode = fmt_mode(*pm)
            else:
                notes.append(f"{name}: unparsable mode {p['mode']!r} dropped")
        pos = (p.get("pos") or p.get("position") or "").replace(",", " ").split()
        if len(pos) == 2:
            c.x, c.y = int(float(pos[0])), int(float(pos[1]))
        if p.get("transform") in TRANSFORMS:
            c.transform = p["transform"]
        if "scale" in p:
            c.scale = norm_scale(float(p["scale"]))
        if p.get("scale_filter") in SCALE_FILTERS:
            c.scale_filter = p["scale_filter"]
        c.adaptive_sync = p.get("adaptive_sync", "off") in ("on", "enable", "enabled", "yes", "true")
        c.enabled = p.get("enabled", "yes") == "yes"
        lay[key] = c
    return lay, notes


# --------------------------------------------------------------------------
# arranging (GUI drag): snap to edges, never overlap

Rect = tuple[int, int, int, int]


def _overlap(a: Rect, b: Rect) -> bool:
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def snap(others: list[Rect], w: int, h: int, x: int, y: int, threshold: int) -> tuple[int, int]:
    """Drop position for a w x h output dragged to (x, y): each axis snaps to
    the nearest edge/alignment of another output within `threshold`, then any
    overlap is pushed out along the shortest move. Returns (x, y)."""
    bx = by = None
    for ox, oy, ow, oh in others:
        for cand in (ox - w, ox + ow, ox, ox + ow - w):
            d = abs(cand - x)
            if d <= threshold and (bx is None or d < bx[0]):
                bx = (d, cand)
        for cand in (oy - h, oy + oh, oy, oy + oh - h):
            d = abs(cand - y)
            if d <= threshold and (by is None or d < by[0]):
                by = (d, cand)
    if bx:
        x = bx[1]
    if by:
        y = by[1]
    for _ in range(2 * len(others) + 2):
        hit = next((r for r in others if _overlap((x, y, w, h), r)), None)
        if hit is None:
            return x, y
        ox, oy, ow, oh = hit
        moves = [(ox - w - x, 0), (ox + ow - x, 0), (0, oy - h - y), (0, oy + oh - y)]
        moves.sort(key=lambda m: abs(m[0]) + abs(m[1]))
        for dx, dy in moves:
            if not any(_overlap((x + dx, y + dy, w, h), r) for r in others):
                return x + dx, y + dy
        x, y = x + moves[0][0], y + moves[0][1]
    return x, y


def _touch(a: Rect, b: Rect) -> bool:
    return a[0] <= b[0] + b[2] and b[0] <= a[0] + a[2] and a[1] <= b[1] + b[3] and b[1] <= a[1] + a[3]


def attach(others: list[Rect], w: int, h: int, x: int, y: int) -> tuple[int, int]:
    """Close the gap to the nearest output when the dropped one touches none
    (the pointer cannot cross a gap). Unchanged if that would overlap."""
    if not others or any(_touch((x, y, w, h), r) for r in others):
        return x, y
    best = None
    for ox, oy, ow, oh in others:
        dx = ox + ow - x if x > ox + ow else (ox - (x + w) if x + w < ox else 0)
        dy = oy + oh - y if y > oy + oh else (oy - (y + h) if y + h < oy else 0)
        cost = abs(dx) + abs(dy)
        if best is None or cost < best[0]:
            best = (cost, dx, dy)
    nx, ny = x + best[1], y + best[2]
    if any(_overlap((nx, ny, w, h), r) for r in others):
        return x, y
    return nx, ny


def reflow(rects: dict[str, Rect], key: str, new: Rect) -> dict[str, tuple[int, int]]:
    """Outputs that touched the right/bottom edge of `key` follow that edge when a scale,
    mode or transform change resizes it (chained), so the layout neither overlaps nor opens
    a gap. Live 2026-10-14: DP-1 4K at 1.5 -> 1.25 grew 2560 -> 3072 wide and slid under
    DP-2, which stayed at x 4663. Returns the new (x, y) of every output that moves."""
    old = rects[key]
    dx, dy = (new[0] + new[2]) - (old[0] + old[2]), (new[1] + new[3]) - (old[1] + old[3])
    moved: dict[str, tuple[int, int]] = {}
    queue = [(old, dx, dy)]
    while queue:
        src, mx, my = queue.pop()
        for k, r in rects.items():
            if k == key or k in moved:
                continue
            right = mx and r[0] == src[0] + src[2] and r[1] < src[1] + src[3] and src[1] < r[1] + r[3]
            below = my and r[1] == src[1] + src[3] and r[0] < src[0] + src[2] and src[0] < r[0] + r[2]
            if right or below:
                moved[k] = (r[0] + (mx if right else 0), r[1] + (my if below else 0))
                queue.append((r, mx if right else 0, my if below else 0))
    return moved


def normalize(layout: dict[str, OutputConf], sizes: dict[str, tuple[int, int]]) -> None:
    """Shift so no enabled output sits at a negative coordinate (X11 clients
    get confused by them); never moves a layout that is already >= 0."""
    on = [k for k, c in layout.items() if c.enabled and k in sizes]
    if not on:
        return
    mx = min(layout[k].x for k in on)
    my = min(layout[k].y for k in on)
    dx, dy = -mx if mx < 0 else 0, -my if my < 0 else 0
    if dx or dy:
        for c in layout.values():
            c.x += dx
            c.y += dy


# --------------------------------------------------------------------------
# live apply + pending/revert state machine

def resolve(spec: str, outs: list[Live], state=None) -> Live | None:
    """Connector, hardware id or role id."""
    for o in outs:
        if spec in (o.name, o.hw_id):
            return o
    if state is not None:
        m = state.monitor(spec)
        if m is not None:
            return next((o for o in outs if o.hw_id == m.criteria), None)
    return None


def commands_for(after: dict[str, OutputConf], before: dict[str, OutputConf], names: dict[str, str]) -> list[str]:
    """Live commands turning `before` into `after`; enables first so there is
    always an active output."""
    on, off = [], []
    for key, c in after.items():
        if c.same_layout(before.get(key)):
            continue
        (on if c.enabled else off).append(live_command(names.get(key) or key, c))
    return on + off


def run_commands(cmds: list[str]) -> list[dict[str, Any]]:
    res = []
    for cmd in cmds:
        try:
            swayipc.command(cmd)
            res.append({"command": cmd, "ok": True})
        except swayipc.SwayError as exc:
            res.append({"command": cmd, "ok": False, "error": str(exc)})
    return res


def check_layout(after: dict[str, OutputConf], outs: list[Live]) -> list[str]:
    probs = [f"{k}: {p}" for k, c in after.items() for p in c.problems()]
    if outs and not any((after[o.hw_id].enabled if o.hw_id in after else o.active) for o in outs):
        probs.append("refusing a layout with no enabled output")
    return probs


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
    os.replace(tmp, path)


def load_pending(path: Path | None = None) -> dict[str, Any] | None:
    try:
        return json.loads((path or pending_file()).read_text())
    except (OSError, ValueError):
        return None


def begin(before: dict[str, OutputConf], after: dict[str, OutputConf], names: dict[str, str], timeout: float,
          now: float | None = None, path: Path | None = None) -> dict[str, Any]:
    """Record a live-only change. A change on top of a pending one keeps the
    ORIGINAL `before` of every output (revert goes back to the saved state)."""
    path = path or pending_file()
    now = time.time() if now is None else now
    old = load_pending(path)
    b = {k: c.to_dict() for k, c in before.items()}
    a = {k: c.to_dict() for k, c in after.items()}
    if old:
        b.update(old.get("before") or {})
        a = {**(old.get("after") or {}), **a}
        names = {**(old.get("names") or {}), **names}
    rec = {"token": secrets.token_hex(8), "started": now, "deadline": now + float(timeout), "before": b, "after": a,
           "names": names, "sway": os.environ.get("SWAYSOCK", "")}
    _write_json(path, rec)
    return rec


def claim(token: str | None = None, path: Path | None = None) -> dict[str, Any] | None:
    """Take the pending record exactly once across processes (rename is atomic):
    whoever claims it (Keep, Revert, the guard) acts; everyone else is a no-op."""
    path = path or pending_file()
    rec = load_pending(path)
    if rec is None or (token and rec.get("token") != token):
        return None
    grabbed = path.with_name(f".{path.name}.claimed-{os.getpid()}-{secrets.token_hex(3)}")
    try:
        os.rename(path, grabbed)
    except FileNotFoundError:
        return None
    try:
        rec = json.loads(grabbed.read_text())
    finally:
        grabbed.unlink(missing_ok=True)
    if token and rec.get("token") != token:  # superseded between read and rename: put it back
        _write_json(path, rec)
        return None
    return rec


def guard_step(token: str, now: float | None = None, path: Path | None = None) -> str:
    """'exit' (kept, reverted or superseded) | 'wait' | 'revert' (deadline passed)."""
    rec = load_pending(path)
    if rec is None or rec.get("token") != token:
        return "exit"
    now = time.time() if now is None else now
    return "revert" if now >= float(rec["deadline"]) else "wait"


def revert_record(rec: dict[str, Any]) -> list[dict[str, Any]]:
    before = {k: OutputConf.from_dict(v) for k, v in (rec.get("before") or {}).items()}
    after = {k: OutputConf.from_dict(v) for k, v in (rec.get("after") or {}).items()}
    with log.action("displays.revert", outputs=len(before)) as res:
        out = run_commands(commands_for(before, after, rec.get("names") or {}))
        res["failed"] = sum(1 for r in out if not r["ok"])
    return out


def keep_record(state, rec: dict[str, Any], outs: list[Live] | None = None) -> dict[str, OutputConf]:
    """Persist what sway runs now for every output (the kept change included)
    into the profile layer. Caller writes/applies/commits."""
    outs = live() if outs is None else outs
    lay = layout_to_save(saved(state), outs, {k: OutputConf.from_dict(v) for k, v in (rec.get("after") or {}).items()})
    store(state, lay)
    return lay


def layout_to_save(saved_layout: dict[str, OutputConf], outs: list[Live], touched: dict[str, OutputConf]) -> dict[str, OutputConf]:
    """Saved layout + the touched outputs as sway runs them now + active outputs
    never saved before. Untouched saved entries stay as saved: X13's lid script
    disables eDP-1 at runtime, and that must never become the saved layout."""
    lay = dict(saved_layout)
    now = merged_with_live(saved_layout, outs)
    present = {o.hw_id for o in outs}
    for k, c in now.items():
        if k in touched or (k not in saved_layout and c.enabled):
            lay[k] = c
    for k, want in touched.items():
        if k not in present:
            lay[k] = want
        else:
            lay[k].scale_filter = want.scale_filter  # sway does not report it back
    return lay


def apply_pending(after: dict[str, OutputConf], timeout: float = DEFAULT_REVERT_SECONDS, guard: bool = True,
                  outs: list[Live] | None = None) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """Apply live and arm the revert. On a failed command the change is undone
    at once and no record is left. Returns (record, command results)."""
    outs = live() if outs is None else outs
    cur = {o.hw_id: o.conf for o in outs}
    names = {o.hw_id: o.name for o in outs}
    before = {k: cur[k] for k in after if k in cur}
    cmds = commands_for(after, before, names)
    if not cmds:
        return None, []
    with log.action("displays.apply_pending", outputs=len(cmds), timeout=timeout) as res:
        rec = begin(before, after, names, timeout)
        out = run_commands(cmds)
        res["failed"] = sum(1 for r in out if not r["ok"])
        if res["failed"]:
            mine = claim(rec["token"])
            if mine:
                revert_record(mine)
            return None, out
        if guard:
            spawn_guard(rec["token"])
    return rec, out


def spawn_guard(token: str) -> None:
    """Detached from the caller: survives a GUI crash. Runs this module with
    the caller's sys.path (the Nix wrapper's site dirs included)."""
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(p for p in sys.path if p)
    subprocess.Popen([sys.executable, "-c", "import sys; from sway_apps import displays; sys.exit(displays.guard_main(sys.argv[1]))", token],
                     env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True, close_fds=True)


def guard_main(token: str) -> int:
    log.setup(stderr=False)
    while True:
        step = guard_step(token)
        if step == "exit":
            return 0
        if step == "revert":
            rec = claim(token)
            if rec:
                _log.info("displays: no Keep before the deadline, reverting %s", ", ".join(rec.get("before") or {}))
                revert_record(rec)
            return 0
        rec = load_pending()
        time.sleep(max(0.05, min(0.5, float(rec["deadline"]) - time.time())) if rec else 0.05)


def discard_stale(now: float | None = None, path: Path | None = None) -> str:
    """Watch-daemon start: a record whose guard died. Same sway -> revert it;
    another sway (re-login) already runs the saved layout -> just drop it."""
    rec = load_pending(path)
    now = time.time() if now is None else now
    if rec is None or now < float(rec.get("deadline", 0)) + 5:
        return "none"
    rec = claim(rec.get("token"), path)
    if rec is None:
        return "none"
    if rec.get("sway") and rec.get("sway") == os.environ.get("SWAYSOCK") and swayipc.available():
        revert_record(rec)
        return "reverted"
    return "dropped"


RESCUE_DELAY = 1.0


def rescue_commands(outs: list[Live], saved_layout: dict[str, OutputConf]) -> list[str]:
    """No active output left (X13: lid script disabled eDP-1, then the dock
    went away): enable every connected output the saved layout does not keep
    off. kanshi's `output * enable` profile used to do this."""
    if any(o.active for o in outs):
        return []
    return [f"output {_quote(o.name)} enable" for o in outs
            if not o.active and (saved_layout.get(o.hw_id) is None or saved_layout[o.hw_id].enabled)]


def _rescue(ctx) -> None:
    from .state import State
    for cmd in rescue_commands(live(ctx.conn.outputs()), saved(State())):
        _log.info("displays: no active output, %s", cmd)
        ctx.command(cmd)


def setup_watch(reg) -> None:
    if owns():
        reg.schedule("displays.stale", 0, lambda _ctx: discard_stale())
        reg.on("output", lambda _ev, ctx: ctx.schedule("displays.rescue", RESCUE_DELAY, _rescue))


# --------------------------------------------------------------------------
# CLI

def register_cli(sub) -> None:
    d = sub.add_parser("displays", help="output layout: mode/position/scale/transform by hardware id (swayAppsOwnsOutputs)")
    ds = d.add_subparsers(dest="sub", required=True)

    def persist_flags(x) -> None:
        x.add_argument("--no-git", action="store_true", help="do not auto-commit")
        x.add_argument("--no-apply", action="store_true", help="save only; do not regenerate/reload")
        x.add_argument("--no-reload", action="store_true", help="regenerate but do not reload sway")

    ds.add_parser("list", help="live outputs and the saved layout").set_defaults(func=cmd_list)
    x = ds.add_parser("exact-scales", help="scales k/120 with an integral logical size")
    x.add_argument("output"); x.add_argument("--mode", help="WxH (default: current)"); x.add_argument("--transform", choices=TRANSFORMS)
    x.add_argument("--min", type=float, default=1.0); x.add_argument("--max", type=float, default=3.0)
    x.set_defaults(func=cmd_exact)
    x = ds.add_parser("set", help="change one output; persisted at once, or live-only with --revert-after N")
    x.add_argument("output", help="connector, hardware id or role")
    x.add_argument("--scale", type=float); x.add_argument("--force-scale", action="store_true", help="allow a non-exact scale")
    x.add_argument("--pos", help="X,Y"); x.add_argument("--mode", help="WxH[@RHz]"); x.add_argument("--transform", choices=TRANSFORMS)
    x.add_argument("--adaptive-sync", choices=["on", "off"]); x.add_argument("--scale-filter", choices=[f for f in SCALE_FILTERS if f])
    g = x.add_mutually_exclusive_group(); g.add_argument("--enable", action="store_true"); g.add_argument("--disable", action="store_true")
    x.add_argument("--revert-after", "--keep-after", dest="revert_after", type=float, metavar="N",
                   help="apply live only; revert after N s unless `sway-apps displays keep`")
    persist_flags(x); x.set_defaults(func=cmd_set)
    x = ds.add_parser("keep", help="keep the pending live change (persist + include + reload)"); persist_flags(x); x.set_defaults(func=cmd_keep)
    ds.add_parser("revert", help="revert the pending live change now").set_defaults(func=cmd_revert)
    ds.add_parser("pending", help="show the pending live change").set_defaults(func=cmd_pending)
    x = ds.add_parser("save-live", help="save what sway runs now as the layout"); persist_flags(x); x.set_defaults(func=cmd_save_live)
    x = ds.add_parser("import-nwg", help="one-time import of nwg-displays' ~/.config/sway/outputs (connector -> hardware id)")
    x.add_argument("--file", help="default: ~/.config/sway/outputs")
    x.add_argument("--map", action="append", default=[], metavar="CONN=HWID", help="connector mapping for outputs not connected now")
    x.add_argument("--force", action="store_true", help="import again over a saved layout"); x.add_argument("--dry-run", action="store_true")
    persist_flags(x); x.set_defaults(func=cmd_import)
    x = ds.add_parser("dpi", help="X11 DPI (xwayland_dpi): show | VALUE | default | suggest")
    x.add_argument("value", nargs="?", default="show"); persist_flags(x); x.set_defaults(func=cmd_dpi)
    ds.add_parser("render", help="print the include fragment").set_defaults(func=cmd_render)
    x = ds.add_parser("guard", help="internal: the revert-timer process"); x.add_argument("token"); x.set_defaults(func=lambda a: guard_main(a.token))


def _cli():
    from . import cli
    return cli


def _state():
    from .state import State
    return State()


def _row(key: str, c: OutputConf, o: Live | None, role: str) -> list[str]:
    size = c.size()
    lw = logical_size(*size, c.transform, c.scale) if size else None
    exact = "" if not size else ("" if is_exact(*size, c.scale) else " (forced)")
    return [o.name if o else (c.connector or "-"), "on" if c.enabled else "off", key, role or "-", c.mode or "preferred",
            f"{c.x},{c.y}", fmt_scale(c.scale) + exact, f"{lw[0]}x{lw[1]}" if lw else "-", c.transform,
            "on" if c.adaptive_sync else "off"]


def cmd_list(args) -> int:
    cli = _cli()
    st = _state()
    outs = live()
    lay = merged_with_live(saved(st), outs)
    by_hw = {o.hw_id: o for o in outs}
    sv = saved(st)
    data, rows = [], []
    for key, c in sorted(lay.items(), key=lambda kv: (kv[1].y, kv[1].x)):
        m = st.monitor_by_criteria(key)
        o = by_hw.get(key)
        data.append({"hw_id": key, "role": m.id if m else None, "connected": o is not None, **c.to_dict(),
                     "saved": key in sv, "differs_from_saved": key in sv and not sv[key].same_layout(c)})
        rows.append(_row(key, c, o, m.id if m else ""))
    dpi, src = effective_dpi(st)
    out = {"owns_outputs": owns(), "outputs": data, "xwayland_dpi": dpi, "xwayland_dpi_source": src, "pending": load_pending()}

    def human() -> None:
        cli._table(rows, ["conn", "on", "hardware id", "role", "mode", "pos", "scale", "logical", "xform", "vrr"])
        print(f"\nX11 DPI {dpi} ({src})" + ("" if owns() else " · owns_outputs OFF: the layout is NOT rendered on this machine"))
        if out["pending"]:
            print(f"pending live change, reverts in {max(0, out['pending']['deadline'] - time.time()):.0f} s (sway-apps displays keep|revert)")
    cli._out(args, out, human)
    return 0


def cmd_exact(args) -> int:
    cli = _cli()
    outs = live()
    o = resolve(args.output, outs, _state())
    if args.mode:
        pm = parse_mode(args.mode)
        if not pm:
            raise cli.CliError(f"bad mode {args.mode!r}")
        w, h = pm[0], pm[1]
    elif o is not None and o.native:
        w, h = o.native
    else:
        raise cli.CliError(f"{args.output}: not an active output (pass --mode WxH)")
    tr = args.transform or (o.conf.transform if o else "normal")
    cur = o.conf.scale if o else None
    rows = exact_scales(w, h, tr, args.min, args.max)
    data = [{"scale": s, "logical": [lw, lh], "current": cur is not None and abs(s - cur) < 1e-6} for s, lw, lh in rows]
    cli._out(args, {"native": [w, h], "transform": tr, "scales": data},
             lambda: [print(f"{fmt_scale(s):>9}  {lw}x{lh}" + ("   <- current" if cur is not None and abs(s - cur) < 1e-6 else "")) for s, lw, lh in rows])
    return 0


def cmd_set(args) -> int:
    cli = _cli()
    st = _state()
    outs = live()
    o = resolve(args.output, outs, st)
    if o is None:
        raise cli.CliError(f"{args.output}: no such output (connector, hardware id or role)")
    lay = merged_with_live(saved(st), outs)
    c = OutputConf(**asdict(lay[o.hw_id]))
    if args.mode:
        pm = parse_mode(args.mode)
        if not pm:
            raise cli.CliError(f"bad mode {args.mode!r}")
        if pm[2] == 0 and o.modes:
            pm = max((m for m in o.modes if m[:2] == pm[:2]), key=lambda m: m[2], default=pm)
        c.mode = fmt_mode(*pm)
    if args.pos:
        try:
            c.x, c.y = (int(v) for v in args.pos.replace(" ", ",").split(",") if v)
        except ValueError:
            raise cli.CliError("--pos must be X,Y")
    if args.transform:
        c.transform = args.transform
    if args.adaptive_sync:
        c.adaptive_sync = args.adaptive_sync == "on"
    if args.scale_filter:
        c.scale_filter = args.scale_filter
    if args.enable:
        c.enabled = True
    if args.disable:
        c.enabled = False
    if args.scale is not None:
        size = c.size() or o.native
        if size and not is_exact(*size, args.scale) and not args.force_scale:
            ex = ", ".join(fmt_scale(s) for s, _w, _h in exact_scales(*size, c.transform))
            raise cli.CliError(f"{fmt_scale(args.scale)} is not exact for {size[0]}x{size[1]}. Exact: {ex}. "
                               f"--force-scale to use it anyway: {FORCED_SCALE_WARNING}")
        c.scale = norm_scale(args.scale)
    after = {o.hw_id: c}
    probs = check_layout({**lay, **after}, outs)
    if probs:
        raise cli.CliError("; ".join(probs))
    if args.revert_after:
        rec, res = apply_pending(after, args.revert_after, outs=outs)
        bad = [r for r in res if not r["ok"]]
        if bad:
            raise RuntimeError(f"{bad[0]['command']}: {bad[0]['error']} (undone)")
        cli._out(args, {"pending": rec, "results": res},
                 lambda: print(f"applied live; reverts in {args.revert_after:g} s unless: sway-apps displays keep" if rec else "nothing to change"))
        return 0
    res = run_commands(commands_for(after, {o.hw_id: o.conf}, {o.hw_id: o.name})) if swayipc.available() and not args.no_apply else []
    bad = [r for r in res if not r["ok"]]
    if bad:
        raise RuntimeError(f"{bad[0]['command']}: {bad[0]['error']}")
    store(st, {**layout_to_save(saved(st), outs, after), o.hw_id: c})
    with log.action("displays.set", output=o.hw_id, **{k: v for k, v in c.to_dict().items() if k != "connector"}):
        out = cli._persist(args, st, f"displays: {o.name} {' '.join(c.sway_args())}", apply_rules=True)
    cli._out(args, {"output": o.hw_id, "conf": c.to_dict(), "live": res, **out},
             lambda: print(f"{o.name}: {' '.join(c.sway_args())} (saved)"))
    return 0


def _persist_kept(args, st, rec) -> dict[str, Any]:
    keep_record(st, rec)
    return _cli()._persist(args, st, "displays: keep layout " + ", ".join(rec.get("names", {}).get(k, k) for k in rec.get("after") or {}),
                           apply_rules=True)


def cmd_keep(args) -> int:
    cli = _cli()
    rec = claim()
    if rec is None:
        raise cli.CliError("nothing pending (already kept, reverted, or the timer ran out)")
    out = _persist_kept(args, _state(), rec)
    cli._out(args, out, lambda: print("kept and saved"))
    return 0


def cmd_revert(args) -> int:
    cli = _cli()
    rec = claim()
    if rec is None:
        raise cli.CliError("nothing pending")
    res = revert_record(rec)
    cli._out(args, {"results": res}, lambda: print("reverted"))
    return 0 if all(r["ok"] for r in res) else 1


def cmd_pending(args) -> int:
    rec = load_pending()
    _cli()._out(args, rec or {}, lambda: print(json.dumps(rec, indent=2) if rec else "nothing pending"))
    return 0


def cmd_save_live(args) -> int:
    cli = _cli()
    st = _state()
    outs = live()
    if not outs:
        raise cli.CliError("no sway outputs (is sway running?)")
    store(st, merged_with_live(saved(st), outs))
    out = cli._persist(args, st, "displays: save live layout", apply_rules=True)
    cli._out(args, out, lambda: print(f"saved {len(outs)} output(s)"))
    return 0


def cmd_import(args) -> int:
    cli = _cli()
    st = _state()
    path = Path(args.file).expanduser() if args.file else nwg_file()
    if (saved(st) or st.feature(SETTINGS_KEY).get("imported_from")) and not args.force and not args.dry_run:
        raise cli.CliError("a layout is already saved (imported once); --force to import again")
    try:
        text = path.read_text()
    except OSError as exc:
        raise cli.CliError(f"{path}: {exc}")
    cmap = connector_map()
    for m in args.map:
        conn, _, hw = m.partition("=")
        if not hw:
            raise cli.CliError(f"--map {m!r}: CONN=HWID")
        cmap[conn.strip()] = hw.strip()
    lay, notes = import_nwg(text, cmap)
    if not lay:
        raise cli.CliError(f"{path}: no output blocks")
    data = {"file": str(path), "outputs": {k: c.to_dict() for k, c in lay.items()}, "notes": notes}
    if args.dry_run:
        cli._out(args, data)
        return 0
    store(st, lay, imported_from=f"{path} @ {time.strftime('%Y-%m-%d')}")
    data.update(cli._persist(args, st, f"displays: import {path.name} ({len(lay)} outputs)", apply_rules=True))
    cli._out(args, data, lambda: (print(f"imported {len(lay)} output(s) from {path}"), [print("  note:", n) for n in notes]))
    return 0


def cmd_dpi(args) -> int:
    cli = _cli()
    st = _state()
    v = args.value
    if v in ("show", "suggest"):
        dpi, src = effective_dpi(st)
        prim = next((m for m in st.monitors() if m.primary), None)
        o = next((x for x in live() if prim and x.hw_id == prim.criteria), None)
        sug = suggest_dpi(o.conf.scale) if o else None
        cli._out(args, {"xwayland_dpi": dpi, "source": src, "suggested": sug, "primary": prim.id if prim else None,
                        "zero_scaling": "xwayland_zero_scaling" in paths.SWAY_FEATURES, "xwayland_running": xwayland_running()},
                 lambda: print(f"X11 DPI {dpi} ({src})" + (f"; primary {prim.id} at scale {fmt_scale(o.conf.scale)} suggests {sug}" if sug else "")))
        return 0
    if "xwayland_zero_scaling" not in paths.SWAY_FEATURES:
        raise cli.CliError("this sway has no xwayland_dpi (swayXwaylandZeroScaling is off)")
    if v == "default":
        dpi = 0
    else:
        try:
            dpi = int(v)
        except ValueError:
            raise cli.CliError("dpi: show | suggest | default | 1..1000")
        if not 1 <= dpi <= 1000:
            raise cli.CliError("dpi must be 1..1000")
    store(st, dpi=dpi)
    out = cli._persist(args, st, f"displays: xwayland_dpi {dpi or 'default'}", apply_rules=True)
    eff, src = effective_dpi(st)
    cli._out(args, {"xwayland_dpi": eff, "source": src, "xwayland_running": xwayland_running(), **out},
             lambda: print(f"X11 DPI {eff} ({src}). {DPI_LIFETIME_NOTE}" + (" Xwayland is running now." if xwayland_running() else "")))
    return 0


def cmd_render(args) -> int:
    text = render_include(_state())
    print(text if text else "# owns_outputs is off on this machine: nothing rendered")
    return 0
