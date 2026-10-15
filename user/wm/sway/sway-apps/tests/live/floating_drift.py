"""Live check of patches/sway-floating-gaps-drift.patch: restart waybar N times (what every
deploy does) and measure every floating window's net movement. Before the patch (DESK
2026-10-15): -4,-4 per restart on DP-1 (4K@1.5), +-2 on DP-2. With it: 0. Needs a session
started with the patched sway (relogin after deploying). Opens one handtest float per output,
restores anything that moved (sticky ones too).

  python3 floating_drift.py [ROUNDS=3]   -> one JSON line, exit 1 if anything drifted"""
import json, subprocess, sys, time
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sway_features import Snapshot, c, spawn, windows  # noqa: E402

ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 3


def floats() -> dict[int, tuple]:
    return {k: w["rect"] for k, w in windows().items() if w["floating"]}


def main() -> int:
    snap = Snapshot()
    outs = [o for o in c.outputs() if o.get("active")]
    procs = []
    for i, o in enumerate(outs):
        p, cid = spawn(f"handtest.drift{i}", "400x240")
        r = o["rect"]
        c.command(f"[con_id={cid}] move absolute position {r['x'] + r['width'] // 3} {r['y'] + r['height'] // 2}")
        procs.append(p)
    time.sleep(0.6)
    before = floats()
    try:
        for _ in range(ROUNDS):
            subprocess.run(["systemctl", "--user", "restart", "waybar"], check=False)
            time.sleep(3.0)
        after = floats()
        drift = {str(k): [a - b for a, b in zip(after[k], before[k])] for k in before if k in after and after[k] != before[k]}
        res = {"rounds": ROUNDS, "floats": len(before), "drift": drift, "ok": not drift}
    finally:
        for p in procs:
            p.terminate()
        time.sleep(0.5)
        for i in range(len(outs)):
            subprocess.run(["sway-apps", "placement", "journal", "forget", f"handtest.drift{i}"], capture_output=True)
        moved = {k: r for k, r in before.items() if k in floats() and floats()[k] != r}
        for k, (x, y, _w, _h) in moved.items():       # sticky windows too (Snapshot skips them)
            c.command(f"[con_id={k}] move absolute position {x} {y}")
        snap.restore()
    res["restored"] = sorted(moved)
    print(json.dumps(res))
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
