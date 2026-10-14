"""Live check of keypad profiles (SWAY-18): what keyd really sends for a Tartarus key under
each deployed profile, switched with `sudo -n keypad-profile set` (the GUI's Use now).

A fake Tartarus (uinput 1532:022b, name "sway-apps-fake-tartarus") is grabbed by keyd exactly
like the real one; its key goes through keyd's virtual keyboard to the focused window, so a
floating sink window (handtest.keypad) is focused and re-checked right before every press,
and a press is skipped when anything else has focus. Restores the live profile, closes only
its own windows. Ask Diego first (tests/live/README).

  python3 keypad_profiles.py [KEY_CODE=16 (q)]   -> one JSON line, exit 1 on a failed check"""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sway_features import OUT, Snapshot, c, spawn, until  # noqa: E402
from sway_apps import keypad as kp  # noqa: E402
from sway_apps.input.uinput import UInputKeyboard  # noqa: E402

DEV = "razer_tartarus"
CODE = int(sys.argv[1]) if len(sys.argv) > 1 else 16       # KEY_Q, keyd name "q"
NAME = {16: "q", 15: "tab", 2: "1"}.get(CODE, "q")


def focused_app() -> str | None:
    def walk(n):
        if n.get("focused"):
            return n.get("app_id")
        for ch in (n.get("nodes") or []) + (n.get("floating_nodes") or []):
            r = walk(ch)
            if r is not None:
                return r
        return None
    return walk(c.tree())


def typed(log: str, since: int) -> str:
    try:
        lines = open(log).read().splitlines()[since:]
    except OSError:
        return ""
    return "".join(eval(l[5:]) for l in lines if l.startswith("text "))   # noqa: S307 - our own repr()


def main() -> int:
    res: dict = {"key": NAME}
    built = sorted(os.listdir(f"/etc/keypad/{DEV}"))
    start = kp.live_profile(DEV)
    res["built"], res["live_before"] = built, start
    snap = Snapshot()
    log = os.path.join(OUT, "handtest.keypad.log")       # spawn() logs there
    open(log, "w").close()
    p, sid = spawn("handtest.keypad", "360x200")
    kb = None
    try:
        c.command(f"[con_id={sid}] focus")
        kb = UInputKeyboard(ids=(0x1532, 0x022B), name=b"sway-apps-fake-tartarus")
        res["grabbed_by_keyd"] = bool(until(lambda: kb.grabbed_by_other(), 3))
        cases = []
        for pid in built + [start]:
            if pid != kp.live_profile(DEV):
                r = subprocess.run(["sudo", "-n", kp.PROFILE_BIN, "set", DEV, pid], capture_output=True, text=True)
                if r.returncode:
                    cases.append({"profile": pid, "switch_error": (r.stdout + r.stderr).strip()})
                    continue
                until(lambda: kb.grabbed_by_other(), 3)        # keyd reload re-grabs the devices
                time.sleep(0.3)
            want = (kp.deployed(DEV, pid) or {}).get(NAME, NAME)
            c.command(f"[con_id={sid}] focus")
            if not until(lambda: focused_app() == "handtest.keypad", 2):
                cases.append({"profile": pid, "skipped": f"focus is {focused_app()}"})
                continue
            n0 = len(open(log).read().splitlines())
            kb.key(CODE, True); time.sleep(0.03); kb.key(CODE, False)
            got = until(lambda: typed(log, n0), 1.5) or ""
            cases.append({"profile": pid, "want": want, "got": got, "ok": got == want})
        res["cases"] = cases
        res["all_ok"] = bool(cases) and all(x.get("ok") for x in cases)
    finally:
        if kb is not None:
            kb.destroy()
        if kp.live_profile(DEV) != start and start:
            subprocess.run(["sudo", "-n", kp.PROFILE_BIN, "set", DEV, start], capture_output=True)
        res["live_after"] = kp.live_profile(DEV)
        p.terminate()
        time.sleep(0.4)
        res["restored"] = snap.restore()
    print(json.dumps(res))
    return 0 if res.get("all_ok") and res.get("grabbed_by_keyd") and res["live_after"] == start else 1


if __name__ == "__main__":
    sys.exit(main())
