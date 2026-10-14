"""Overview cost per GSK renderer on a GPU-backed nested sway (WLR_RENDERER=gles2) with
DESK-like outputs: paint latency, RSS, and the process's VRAM/GTT from DRM fdinfo.
Not collected by run.py (no test_ prefix): `$E2E_PYTHON perf_overview.py [renderer…]`."""
from __future__ import annotations

import json
import os
import statistics
import sys
import time

import test_70_overview as t70
from harness import Nested
from test_70_overview import Overview

OUTS = [(3840, 2160), (1440, 2560)]
SCALES = [1.5, 1.25]
BIND = t70.BIND.replace("HEADLESS-2", "HEADLESS-2")


def drm_mem(pid: int) -> dict[str, int]:
    seen, tot = set(), {"vram": 0, "gtt": 0}
    d = f"/proc/{pid}/fdinfo"
    for f in os.listdir(d):
        try:
            txt = open(f"{d}/{f}").read()
        except OSError:
            continue
        if "drm-client-id" not in txt:
            continue
        cid = next(l.split()[1] for l in txt.splitlines() if l.startswith("drm-client-id"))
        if cid in seen:
            continue
        seen.add(cid)
        for l in txt.splitlines():
            for k in ("vram", "gtt"):
                if l.startswith(f"drm-memory-{k}:"):
                    tot[k] += int(l.split()[1])
    return tot


def rss_kb(pid: int) -> int:
    for l in open(f"/proc/{pid}/status"):
        if l.startswith("VmRSS"):
            return int(l.split()[1])
    return 0


def run(renderer: str) -> dict:
    with Nested(outputs=OUTS, scales=SCALES, config=t70.BIND, env={"WLR_RENDERER": "gles2"}) as s:
        for i, app in enumerate(("e2e.a", "e2e.b", "e2e.c", "e2e.d", "e2e.e")):
            s.client(app)
        orig = s.spawn
        s.spawn = lambda argv, env=None, **kw: orig(argv, {**(env or {}), "GSK_RENDERER": renderer}, **kw)
        o = Overview(s)
        s.spawn = orig
        pid = o.proc.pid
        if os.environ.get("LIVE") is not None:
            (o.base / "state" / "E2E.json").write_text(json.dumps(
                {"version": 1, "settings": {"overview": {"live_capture_ms": int(os.environ["LIVE"])}}}))
        time.sleep(1.0)
        res = {"renderer": renderer, "live_ms": os.environ.get("LIVE", "default"), "startup_ms": o.startup_ms, "idle": {"rss_kb": rss_kb(pid), **drm_mem(pid)}}
        lat = []
        for _ in range(6):
            t0 = time.monotonic()
            o.ctl("show")
            st = o.wait_open()
            lat.append(round(1000 * (st["painted_at"] - st["t0"]), 1) if "t0" in st else st["latency_ms"]["painted"])
            if _ == 0:
                time.sleep(0.5)
                res["open"] = {"rss_kb": rss_kb(pid), **drm_mem(pid)}
            o.ctl("hide")
            o.wait_closed()
            time.sleep(0.2)
        time.sleep(1.0)
        res["after_hide"] = {"rss_kb": rss_kb(pid), **drm_mem(pid)}
        res["painted_ms"] = lat
        res["painted_median"] = statistics.median(lat)
        return res


if __name__ == "__main__":
    for r in sys.argv[1:] or ["ngl", "vulkan", "gl", "cairo"]:
        try:
            print(json.dumps(run(r)), flush=True)
        except Exception as exc:
            print(json.dumps({"renderer": r, "error": str(exc)[:300]}), flush=True)
