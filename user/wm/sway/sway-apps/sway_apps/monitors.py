"""Monitors: live outputs, hardware ids, workspace pins, geometry pinning.

Layering with the rest of the stack:
  - nwg-displays owns the PHYSICAL layout and writes ~/.config/sway/outputs
    keyed by connector (DP-1, HDMI-A-1). Connectors drift; hardware ids don't.
  - sway-apps owns the LOGICAL layer: role -> hardware id -> workspace decade,
    rendered as `workspace N output "<hw id>"` lines plus the
    (the hotplug snapshot/restore that used to consume a pins file was removed 2026-09-07).
  - Optionally (settings.pin_geometry) it re-emits nwg-displays' geometry
    keyed by hardware id so it survives connector renames.
"""
from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import log, paths, swayipc
from .state import Monitor, State

_log = log.get("monitors")

NWG_OUTPUTS_FILE = paths.XDG_CONFIG_HOME / "sway" / "outputs"
NWG_WORKSPACES_FILE = paths.XDG_CONFIG_HOME / "sway" / "workspaces"


@dataclass
class LiveOutput:
    name: str
    hw_id: str
    make: str
    model: str
    serial: str
    active: bool
    x: int
    y: int
    width: int
    height: int
    scale: float
    transform: str
    refresh: float
    current_workspace: str | None
    focused: bool

    def to_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def hw_id(o: dict[str, Any]) -> str:
    """Exactly what sway matches on: 'make model serial' (spaces preserved)."""
    return f"{o.get('make', '')} {o.get('model', '')} {o.get('serial', '')}"


def live_outputs() -> list[LiveOutput]:
    if not swayipc.available():
        return []
    out = []
    for o in swayipc.outputs():
        mode = o.get("current_mode") or {}
        rect = o.get("rect") or {}
        out.append(LiveOutput(
            name=o["name"], hw_id=hw_id(o), make=o.get("make", ""), model=o.get("model", ""), serial=o.get("serial", ""),
            active=bool(o.get("active")), x=rect.get("x", 0), y=rect.get("y", 0), width=mode.get("width") or rect.get("width", 0),
            height=mode.get("height") or rect.get("height", 0), scale=float(o.get("scale") or 1.0), transform=str(o.get("transform") or "normal"),
            refresh=(mode.get("refresh") or 0) / 1000.0, current_workspace=o.get("current_workspace"), focused=bool(o.get("focused")),
        ))
    return out


def connector_of(criteria: str) -> str | None:
    for o in live_outputs():
        if o.hw_id == criteria and o.active:
            return o.name
    return None


# --------------------------------------------------------------------------
# auto-adoption of unknown outputs (settings.auto_adopt, e.g. a laptop dock)

ROLE_ORDER = ["main", "second", "third", "fourth"]


def adopt_unknown(state: State) -> list[Monitor]:
    """Give every unknown active output a role (first missing of ROLE_ORDER,
    else monN) and the lowest free decade. Returns the monitors created."""
    known = {m.criteria for m in state.monitors()}
    used_groups = {m.group for m in state.monitors() if m.group}
    roles = {m.id for m in state.monitors()}
    created: list[Monitor] = []
    for o in live_outputs():
        if not o.active or o.hw_id in known or o.name.startswith("HEADLESS"):
            continue
        role = next((r for r in ROLE_ORDER if r not in roles), None) or f"mon{len(roles) + 1}"
        group = next((g for g in range(1, 10) if g not in used_groups), 0)
        m = Monitor(id=role, criteria=o.hw_id, group=group, name=f"{o.make} {o.model}".strip() or o.name,
                    primary=not roles, notes=f"auto-adopted {o.name} on first sight", scope="profile")
        state.save_monitor(m, "profile")
        known.add(o.hw_id); roles.add(role); used_groups.add(group)
        created.append(m)
        _log.info("adopted %s (%s) as role %s group %s", o.name, o.hw_id, role, group)
    return created


# --------------------------------------------------------------------------
# "always connected": DRM connector force via the sudo helper

FORCE_HELPER = "sway-connector-force"
FORCED_FILE = paths.LOCAL_STATE_DIR / "forced-connectors.json"


def sysfs_connector(output_name: str) -> str | None:
    """sway output 'DP-1' -> DRM sysfs name 'card1-DP-1' (prefers a connected one)."""
    import glob
    cands = sorted(glob.glob(f"/sys/class/drm/card*-{output_name}"))
    if not cands:
        return None
    for c in cands:
        try:
            if (Path(c) / "status").read_text().strip() == "connected":
                return Path(c).name
        except OSError:
            pass
    return Path(cands[0]).name


def connector_status(sysfs_name: str) -> str | None:
    try:
        return (Path("/sys/class/drm") / sysfs_name / "status").read_text().strip()
    except OSError:
        return None


def _load_forced() -> dict[str, str]:
    try:
        return json.loads(FORCED_FILE.read_text())
    except (OSError, ValueError):
        return {}


def _save_forced(d: dict[str, str]) -> None:
    FORCED_FILE.parent.mkdir(parents=True, exist_ok=True)
    FORCED_FILE.write_text(json.dumps(d, indent=2, sort_keys=True) + "\n")


def set_connector_force(sysfs_name: str, mode: str) -> tuple[bool, str]:
    """mode: 'on' (always connected) | 'detect' (kernel decides). Runs the
    NOPASSWD sudo helper installed by nix (system/wm/sway-connector-force.nix)."""
    if mode not in ("on", "detect"):
        return False, f"bad mode {mode!r}"
    cmd = ["sudo", "-n", FORCE_HELPER, sysfs_name, mode]
    with log.action("monitors.connector_force", connector=sysfs_name, mode=mode) as res:
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        except FileNotFoundError:
            return False, "sudo not found"
        out = (proc.stdout + proc.stderr).strip()
        res["rc"] = proc.returncode
        if proc.returncode != 0:
            _log.warning("connector force failed: %s", out)
            return False, out or f"{FORCE_HELPER} exit {proc.returncode} (sudo rule missing? needs swayAppsEnable on the SYSTEM side)"
        forced = _load_forced()
        if mode == "on":
            forced[sysfs_name] = "on"
        else:
            forced.pop(sysfs_name, None)
        _save_forced(forced)
    return True, out or f"{sysfs_name}: {mode}"


def apply_force(state: State) -> list[dict[str, Any]]:
    """Reconcile every present monitor's connector with its always_connected
    flag; release connectors we forced earlier whose flag went off."""
    results: list[dict[str, Any]] = []
    live = {o.hw_id: o for o in live_outputs()}
    wanted: dict[str, Monitor] = {}
    for m in state.monitors():
        o = live.get(m.criteria)
        if o is None:
            if m.always_connected:
                results.append({"role": m.id, "skipped": "monitor not present right now; forced when it is"})
            continue
        sysfs = sysfs_connector(o.name)
        if sysfs is None:
            results.append({"role": m.id, "error": f"no sysfs connector for {o.name}"})
            continue
        if m.always_connected:
            wanted[sysfs] = m
    forced = _load_forced()
    for sysfs, m in wanted.items():
        ok, msg = set_connector_force(sysfs, "on")
        results.append({"role": m.id, "connector": sysfs, "mode": "on", "ok": ok, "detail": msg})
    for sysfs in list(forced):
        if sysfs not in wanted:
            ok, msg = set_connector_force(sysfs, "detect")
            results.append({"connector": sysfs, "mode": "detect", "ok": ok, "detail": msg})
    return results


def force_status(state: State) -> list[dict[str, Any]]:
    live = {o.hw_id: o for o in live_outputs()}
    forced = _load_forced()
    out = []
    for m in state.monitors():
        o = live.get(m.criteria)
        sysfs = sysfs_connector(o.name) if o else None
        out.append({"role": m.id, "always_connected": m.always_connected, "present": o is not None,
                    "connector": sysfs, "status": connector_status(sysfs) if sysfs else None,
                    "forced_now": bool(sysfs and forced.get(sysfs) == "on")})
    return out


# --------------------------------------------------------------------------
# rendering

def render_pins(state: State) -> str:
    lines = []
    mons = [m for m in state.monitors() if m.enabled and m.group]
    if not mons:
        return ""
    lines.append(f"\n# ---- Workspace pins ({len(mons)} monitors, hardware-id based)")
    for m in mons:
        lines.append(f"# {m.id}: {m.name or m.criteria} -> workspaces {m.group * 10 + 1}-{m.group * 10 + 10}")
        for n in m.workspaces():
            lines.append(f'workspace {n} output "{m.criteria}"')
    return "\n".join(lines) + "\n"


def pins_conf_text(state: State) -> str:
    """group|criteria per line (kept for tooling/tests; no runtime consumer since 2026-09-07)."""
    return "".join(f"{m.group}|{m.criteria}\n" for m in state.monitors() if m.enabled and m.group)


_BLOCK_RX = re.compile(r'output\s+"?([^"\s{]+)"?\s*\{([^}]*)\}', re.S)


def parse_nwg_outputs(text: str) -> dict[str, dict[str, str]]:
    """{connector: {mode:.., pos:.., transform:.., scale:.., ...}} from the
    block syntax nwg-displays writes."""
    out: dict[str, dict[str, str]] = {}
    for m in _BLOCK_RX.finditer(text):
        name, body = m.group(1), m.group(2)
        props: dict[str, str] = {}
        for line in body.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition(" ")
            props[k.strip()] = v.strip()
        out[name] = props
    return out


def render_geometry(state: State) -> tuple[str, list[str]]:
    """Geometry lines keyed by hardware id. Returns (text, notes)."""
    notes: list[str] = []
    if not state.settings().get("pin_geometry"):
        return "", notes
    try:
        text = NWG_OUTPUTS_FILE.read_text()
    except OSError:
        notes.append(f"{NWG_OUTPUTS_FILE} not found; nothing to pin")
        return "", notes
    blocks = parse_nwg_outputs(text)
    live = {o.name: o for o in live_outputs()}
    lines = [f"\n# ---- Output geometry pinned to hardware ids (source: {NWG_OUTPUTS_FILE})"]
    for conn, props in blocks.items():
        o = live.get(conn)
        mon = state.monitor_by_criteria(o.hw_id) if o else None
        if o is None and mon is None:
            # Unknown connector right now: try a monitor whose remembered connector matches
            notes.append(f"{conn}: not connected and no monitor maps to it; kept by connector name")
            key = conn
        else:
            key = o.hw_id
        parts = []
        for k in ("mode", "pos", "transform", "scale", "scale_filter", "adaptive_sync", "dpms"):
            if k in props:
                v = props[k].strip()
                if k == "dpms":
                    parts.append(f"power {'on' if v == 'on' else 'off'}")
                else:
                    parts.append(f"{k} {v}")
        if parts:
            lines.append(f'output "{key}" ' + " ".join(parts))
    return "\n".join(lines) + "\n", notes


# --------------------------------------------------------------------------
# live application

def apply_live(state: State) -> list[dict[str, Any]]:
    """Move existing workspaces onto their pinned monitor (present ones only)
    and register the pins with the running compositor."""
    hits: list[dict[str, Any]] = []
    if not swayipc.available():
        return hits
    live = {o.hw_id: o for o in live_outputs() if o.active}
    ws = swayipc.workspaces()
    with log.action("monitors.apply_live") as res:
        for m in state.monitors():
            if not (m.enabled and m.group):
                continue
            o = live.get(m.criteria)
            for n in m.workspaces():
                try:
                    swayipc.command(f'workspace {n} output "{m.criteria}"')
                except swayipc.SwayError as exc:
                    hits.append({"workspace": n, "ok": False, "error": str(exc)})
                    continue
            if o is None:
                continue
            for w in ws:
                if w.get("num") in m.workspaces() and w.get("output") != o.name:
                    try:
                        swayipc.command(f'[workspace="^{w["name"]}$"] move workspace to output {o.name}')
                        hits.append({"workspace": w["name"], "ok": True, "moved_to": o.name})
                    except swayipc.SwayError as exc:
                        hits.append({"workspace": w["name"], "ok": False, "error": str(exc)})
        res["moved"] = sum(1 for h in hits if h.get("ok"))
    return hits


def fix_orphans(state: State) -> dict[str, Any]:
    """Migrate group-0 workspaces (1-10) into the pinned decade of the output
    they sit on (digit preserved: "3" -> "13"; rename when the target is free,
    else move the windows).
    Empty orphans are simply left to sway's auto-removal unless focused, in
    which case focus is moved to the decade's first workspace."""
    if not swayipc.available():
        return {"ok": False, "error": "no sway socket"}
    live = {o.name: o for o in live_outputs()}
    base_for_output: dict[str, int] = {}
    for m in state.monitors():
        if m.enabled and m.group:
            for name, o in live.items():
                if o.hw_id == m.criteria:
                    base_for_output[name] = m.group * 10
    ws = swayipc.workspaces()
    tree_windows = swayipc.windows()
    actions: list[dict[str, Any]] = []
    with log.action("monitors.fix_orphans") as res:
        for w in ws:
            num = w.get("num")
            if not isinstance(num, int) or not 1 <= num <= 10:
                continue
            base = base_for_output.get(w.get("output", ""))
            if base is None:
                # no pin for this output: lowest existing decade on it
                decades = [x["num"] // 10 * 10 for x in ws if x.get("output") == w.get("output") and isinstance(x.get("num"), int) and x["num"] >= 11]
                base = min(decades) if decades else None
            if base is None:
                actions.append({"workspace": w["name"], "skipped": "no pinned decade for output " + str(w.get("output"))})
                continue
            target = base + num
            wins = [x for x in tree_windows if x.workspace == w["name"]]
            exists = any(x.get("num") == target for x in ws)
            try:
                if not wins:
                    if w.get("focused"):
                        swayipc.command(f"workspace number {base + 1}")
                        actions.append({"workspace": w["name"], "action": f"focus moved to {base + 1} (empty orphan auto-removes)"})
                    else:
                        actions.append({"workspace": w["name"], "action": "empty, left to auto-remove"})
                elif not exists and w["name"] == str(num):
                    swayipc.command(f'rename workspace "{w["name"]}" to "{target}"')
                    actions.append({"workspace": w["name"], "action": f"renamed to {target}", "windows": len(wins)})
                else:
                    for x in wins:
                        swayipc.command(f"[con_id={x.id}] move container to workspace number {target}")
                    actions.append({"workspace": w["name"], "action": f"{len(wins)} window(s) moved to {target}"})
            except swayipc.SwayError as exc:
                actions.append({"workspace": w["name"], "error": str(exc)})
        res["actions"] = len(actions)
    return {"ok": all("error" not in a for a in actions), "actions": actions}


def orphans() -> list[dict[str, Any]]:
    """Workspaces 1-10 (group 0) currently alive."""
    if not swayipc.available():
        return []
    return [{"name": w["name"], "num": w.get("num"), "output": w.get("output"), "focused": w.get("focused")}
            for w in swayipc.workspaces() if isinstance(w.get("num"), int) and 1 <= w["num"] <= 10]


def workspace_map(state: State) -> list[dict[str, Any]]:
    """Per monitor: its 10 slots with assigned apps (rules) and open windows."""
    live = {o.hw_id: o for o in live_outputs()}
    windows = swayipc.windows() if swayipc.available() else []
    rules = state.resolved_rules()
    out = []
    for m in state.monitors():
        o = live.get(m.criteria)
        slots = []
        for i in range(1, 11):
            n = m.group * 10 + i if m.group else None
            slot_rules = [r for r in rules if n is not None and r.enabled and r.workspace_number() == n]
            slot_windows = [w for w in windows if n is not None and w.workspace_num == n]
            slots.append({"slot": i, "workspace": n,
                          "rules": [{"id": r.id, "name": r.name, "kind": r.kind, "criteria": r.criteria} for r in slot_rules],
                          "windows": [{"id": w.id, "label": w.label, "title": w.title} for w in slot_windows]})
        out.append({"monitor": m.to_dict(), "connected": o is not None and o.active, "connector": o.name if o else None, "slots": slots})
    # Windows on workspaces nobody pins (group 0 or an unpinned decade)
    pinned = {n for m in state.monitors() for n in m.workspaces()}
    stray = [w for w in windows if w.workspace_num is not None and w.workspace_num not in pinned]
    if stray:
        out.append({"monitor": None, "connected": None, "connector": None,
                    "slots": [{"slot": None, "workspace": w.workspace_num, "rules": [], "windows": [{"id": w.id, "label": w.label, "title": w.title}]} for w in stray]})
    return out
