"""`sway-apps watch`: react to sway output events.

Runs as a user service bound to sway-session.target. On every change of the
active monitor set (debounced) it:
  1. adopts unknown outputs when settings.auto_adopt is on (laptop dock),
  2. registers the workspace pins with the compositor and moves existing
     workspaces of a returning monitor home (`monitors.apply_live`),
  3. re-applies the "always connected" connector forces.
It never touches window geometry or focus: placement is sway's own
`workspace N output` behaviour.
"""
from __future__ import annotations

import json
import select
import subprocess
import time

from . import generate, gitsync, log, monitors as mon, paths, swayipc
from .state import State

_log = log.get("watch")


def signature() -> str:
    return "||".join(sorted(o.hw_id for o in mon.live_outputs() if o.active and not o.name.startswith("HEADLESS")))


def reconcile(reason: str) -> dict:
    st = State()
    out: dict = {"reason": reason}
    with log.action("watch.reconcile", reason=reason) as res:
        if st.settings().get("auto_adopt"):
            created = mon.adopt_unknown(st)
            if created:
                st.write()
                try:
                    generate.apply(st, reload=False)
                    sha = gitsync.commit(st.files(), "adopt monitor " + ", ".join(m.id for m in created))
                    if sha and gitsync.auto_sync_enabled():
                        gitsync.sync()
                except Exception as exc:  # keep reconciling even if git/network is down
                    _log.warning("adopt persist/sync failed: %s", exc)
                out["adopted"] = [m.to_dict() for m in created]
                res["adopted"] = len(created)
        if swayipc.available():
            live = mon.apply_live(st)
            res["moved"] = sum(1 for h in live if h.get("ok"))
        out["force"] = mon.apply_force(st)
    return out


def run(once: bool = False, debounce: float = 1.5) -> int:
    log.setup(stderr=False)
    if not swayipc.available():
        print("sway IPC not reachable", flush=True)
        return 0
    last = signature()
    reconcile("start")
    if once:
        return 0
    swayipc._ensure_socket()
    proc = subprocess.Popen([paths.SWAYMSG_BIN, "-t", "subscribe", "-m", json.dumps(["output"])],
                            stdout=subprocess.PIPE, text=True)
    assert proc.stdout is not None
    try:
        for _line in proc.stdout:
            time.sleep(debounce)  # let the burst settle
            while True:           # drain whatever queued meanwhile
                r, _, _ = select.select([proc.stdout], [], [], 0)
                if not r or proc.stdout.readline() == "":
                    break
            sig = signature()
            if sig != last:
                last = sig
                try:
                    reconcile("output-change")
                except Exception as exc:
                    _log.exception("reconcile failed: %s", exc)
    finally:
        proc.terminate()
    return 0
