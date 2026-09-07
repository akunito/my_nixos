"""Cross-profile view, copy and snapshots.

All state files live in the repo (common.json + one JSON per profile), so
"seeing DESK's config from X13" is reading a sibling file. Copying moves
id-keyed items between profile layers; every write is preceded by a
snapshot (a dated copy of all state files under apps/snapshots/) that can be
restored whole or per section.
"""
from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from typing import Any

from . import log, paths
from .state import State, _read, _write

_log = log.get("profiles")

SECTIONS = ("rules", "startup", "shortcuts", "tools", "monitors", "nodes")
SNAP_DIR = paths.STATE_DIR / "snapshots"
KEEP = 30


def profile_files() -> dict[str, Path]:
    """{profile: path} for every layer in the state dir (common included)."""
    out = {}
    for p in sorted(paths.STATE_DIR.glob("*.json")):
        out[p.stem] = p
    return out


def layer(profile: str) -> dict[str, Any]:
    p = paths.STATE_DIR / f"{profile}.json"
    return _read(p) if p.exists() else _read(p)  # _read returns an empty layer when missing


def _by_id(items: list[dict]) -> dict[str, dict]:
    return {x["id"]: x for x in items if "id" in x}


def _strip(d: dict) -> dict:
    return {k: v for k, v in d.items() if k not in ("updated_at",)}


def label(section: str, item: dict) -> str:
    if section == "rules":
        from .rules import Rule
        return Rule.from_dict(item).render() if item.get("criteria") else item.get("name", item["id"])
    if section == "shortcuts":
        return f"{item.get('keys', '?')} → {item.get('name') or item.get('command', '')}"
    if section == "startup":
        return f"{item.get('name', '')} ({item.get('command', '')})"
    if section == "monitors":
        return f"{item.get('id')} = {item.get('criteria', '')} (group {item.get('group', 0)})"
    if section == "nodes":
        return f"{item.get('id')} {item.get('ssh') or 'local'}"
    return item.get("name") or item.get("id", "?")


def diff(a: str, b: str, section: str) -> dict[str, list[dict]]:
    """Items of `section` only in a, only in b, or in both but different
    (ignoring updated_at). Overrides in a profile layer may be partial
    dicts (only the fields that override common)."""
    la, lb = _by_id(layer(a).get(section, [])), _by_id(layer(b).get(section, []))
    only_a = [la[i] for i in la if i not in lb]
    only_b = [lb[i] for i in lb if i not in la]
    changed = [{"a": la[i], "b": lb[i]} for i in la if i in lb and _strip(la[i]) != _strip(lb[i])]
    same = [la[i] for i in la if i in lb and _strip(la[i]) == _strip(lb[i])]
    return {"only_a": only_a, "only_b": only_b, "changed": changed, "same": same}


def summary(a: str, b: str) -> dict[str, dict[str, int]]:
    return {s: {k: len(v) for k, v in diff(a, b, s).items()} for s in SECTIONS}


# --------------------------------------------------------------------------
# snapshots

def snapshot(reason: str) -> Path:
    SNAP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in reason)[:40].strip("-") or "manual"
    d = SNAP_DIR / f"{stamp}-{paths.profile_name()}-{safe}"
    n = 1
    while d.exists():  # two snapshots in the same second
        n += 1
        d = SNAP_DIR / f"{stamp}-{n}-{paths.profile_name()}-{safe}"
    d.mkdir()
    for p in paths.STATE_DIR.glob("*.json"):
        shutil.copy2(p, d / p.name)
    (d / "META.json").write_text(json.dumps({"reason": reason, "profile": paths.profile_name(), "time": int(time.time()),
                                              "files": sorted(p.name for p in paths.STATE_DIR.glob("*.json"))}, indent=2) + "\n")
    _log.info("snapshot %s (%s)", d.name, reason)
    prune()
    return d


def prune(keep: int = KEEP) -> list[str]:
    snaps = sorted(p for p in SNAP_DIR.glob("*") if p.is_dir()) if SNAP_DIR.exists() else []
    removed = []
    for old in snaps[:-keep] if len(snaps) > keep else []:
        shutil.rmtree(old, ignore_errors=True)
        removed.append(old.name)
    return removed


def snapshots() -> list[dict[str, Any]]:
    out = []
    if not SNAP_DIR.exists():
        return out
    for d in sorted(p for p in SNAP_DIR.glob("*") if p.is_dir()):
        try:
            meta = json.loads((d / "META.json").read_text())
        except (OSError, ValueError):
            meta = {}
        out.append({"id": d.name, "path": str(d), **meta})
    return out


def snapshot_dir(snap_id: str) -> Path:
    d = SNAP_DIR / snap_id
    if not d.is_dir():
        cands = [p for p in SNAP_DIR.glob(f"*{snap_id}*") if p.is_dir()] if SNAP_DIR.exists() else []
        if len(cands) == 1:
            return cands[0]
        raise FileNotFoundError(f"no snapshot {snap_id!r}")
    return d


def restore(snap_id: str, files: list[str] | None = None, sections: list[str] | None = None) -> list[str]:
    """Restore whole files (default: all) or only some sections of them.
    A snapshot of the current state is taken first."""
    d = snapshot_dir(snap_id)
    snapshot(f"before-restore-{d.name[:15]}")
    touched = []
    for src in sorted(d.glob("*.json")):
        if src.name == "META.json" or (files and src.name not in files):
            continue
        dst = paths.STATE_DIR / src.name
        if sections:
            cur = _read(dst) if dst.exists() else _read(dst)
            old = _read(src)
            for sec in sections:
                cur[sec] = old.get(sec, [])
            _write(dst, cur)
        else:
            shutil.copy2(src, dst)
        touched.append(src.name)
    _log.info("restored %s from %s (%s)", touched, d.name, sections or "whole files")
    return touched


def diff_snapshot(snap_id: str) -> dict[str, dict[str, dict[str, int]]]:
    """Per file and section: counts of items that differ between the snapshot and now."""
    d = snapshot_dir(snap_id)
    out: dict[str, dict[str, dict[str, int]]] = {}
    for src in sorted(d.glob("*.json")):
        if src.name == "META.json":
            continue
        old = _read(src); cur = _read(paths.STATE_DIR / src.name) if (paths.STATE_DIR / src.name).exists() else _read(paths.STATE_DIR / src.name)
        per: dict[str, dict[str, int]] = {}
        for sec in SECTIONS:
            o, c = _by_id(old.get(sec, [])), _by_id(cur.get(sec, []))
            per[sec] = {"only_snapshot": len(set(o) - set(c)), "only_now": len(set(c) - set(o)),
                        "changed": sum(1 for i in set(o) & set(c) if _strip(o[i]) != _strip(c[i]))}
        out[src.name] = per
    return out


# --------------------------------------------------------------------------
# copy between layers

def copy_items(src_profile: str, dst_profile: str, section: str, ids: list[str] | None = None,
               replace: bool = False) -> dict[str, Any]:
    """Copy `section` items (all, or the given ids) from one layer to another.
    Items are id-keyed: an existing id in the destination is overwritten,
    other destination items are kept unless replace=True. Snapshot first."""
    if section not in SECTIONS:
        raise ValueError(f"section must be one of {SECTIONS}")
    src = layer(src_profile)
    dst_path = paths.STATE_DIR / f"{dst_profile}.json"
    dst = _read(dst_path) if dst_path.exists() else _read(dst_path)
    items = src.get(section, [])
    if ids is not None:
        items = [x for x in items if x.get("id") in ids]
    snap = snapshot(f"copy-{section}-{src_profile}-to-{dst_profile}")
    now = int(time.time())
    if replace:
        new_list = [dict(x, updated_at=now) for x in items]
    else:
        merged = _by_id(dst.get(section, []))
        for x in items:
            merged[x["id"]] = dict(x, updated_at=now)
        new_list = list(merged.values())
    dst[section] = new_list
    _write(dst_path, dst)
    _log.info("copied %d %s from %s to %s (replace=%s)", len(items), section, src_profile, dst_profile, replace)
    return {"copied": [x["id"] for x in items], "section": section, "from": src_profile, "to": dst_profile,
            "snapshot": snap.name, "destination_total": len(new_list)}


def copied_files() -> list[Path]:
    """State files + snapshots, for the git commit."""
    files = [p for p in paths.STATE_DIR.glob("*.json")]
    if SNAP_DIR.exists():
        files.append(SNAP_DIR)
    return files
