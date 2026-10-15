"""Live check of the mouse mic button: a fake DeathAdder V3 (uinput 1532:00b2, grabbed by keyd's
razer_mouse config like the real one) sends what the side button's firmware sends, Hyper+M
(leftctrl+leftalt+leftmeta+m). keyd must turn it into Hyper+Shift+F12, sway runs mic-toggle:
the default source mutes (a real capture is all zeros), a "Micro MUTED" notification goes out,
and Mission Center (the keyboard's Hyper+M) does not open. Pressed twice, so the mic ends as it
started. A floating sink window (handtest.micbtn) holds focus in case keyd lets a key through.

  python3 mic_button.py   -> one JSON line, exit 1 on a failed check"""
import array, json, math, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sway_features import OUT, Snapshot, c, spawn, until  # noqa: E402
from sway_apps.input.uinput import UInputKeyboard  # noqa: E402

CHORD = (29, 56, 125, 50)       # KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTMETA, KEY_M
SRC = "@DEFAULT_AUDIO_SOURCE@"


def muted() -> bool:
    return "MUTED" in subprocess.run(["wpctl", "get-volume", SRC], capture_output=True, text=True).stdout


def peak() -> int:
    r = subprocess.run(["timeout", "1.2", "pw-record", "--target", SRC, "--format", "s16", "--rate", "48000",
                        "--channels", "1", "-"], capture_output=True)
    d = r.stdout[len(r.stdout) // 4:]          # skip the stream's start
    a = array.array("h", d[:len(d) // 2 * 2])
    return max(map(abs, a)) if a else -1


def missioncenter() -> list[int]:
    out = []
    stack = [c.tree()]
    while stack:
        n = stack.pop()
        if n.get("app_id") == "io.missioncenter.MissionCenter":
            out.append(n["id"])
        stack += (n.get("nodes") or []) + (n.get("floating_nodes") or [])
    return out


def press(kb: UInputKeyboard) -> None:
    for k in CHORD:
        kb.key(k, True); time.sleep(0.01)
    time.sleep(0.03)
    for k in reversed(CHORD):
        kb.key(k, False); time.sleep(0.01)


def main() -> int:
    res: dict = {}
    start = muted()
    res["muted_before"] = start
    mc0 = missioncenter()
    snap = Snapshot()
    nlog = os.path.join(OUT, "mic_button.notify.log")
    mon = subprocess.Popen(["dbus-monitor", "--session", "interface='org.freedesktop.Notifications',member='Notify'"],
                           stdout=open(nlog, "w"), stderr=subprocess.DEVNULL)
    p, sid = spawn("handtest.micbtn", "360x200")
    kb = None
    try:
        kb = UInputKeyboard(ids=(0x1532, 0x00B2), name=b"sway-apps-fake-deathadder")
        res["grabbed_by_keyd"] = bool(until(lambda: kb.grabbed_by_other(), 3))
        time.sleep(0.3)
        steps = []
        for i in range(2):
            c.command(f"[con_id={sid}] focus")
            want = not muted()
            t0 = time.monotonic()
            press(kb)
            ok = bool(until(lambda: muted() == want, 2))
            step = {"want_muted": want, "ok": ok, "ms": round((time.monotonic() - t0) * 1000)}
            if ok and want:
                step["capture_peak"] = peak()
                step["silent"] = step["capture_peak"] == 0
            steps.append(step)
        res["steps"] = steps
        time.sleep(0.5)
        notes = [l.split('"')[1] for l in open(nlog).read().splitlines() if l.strip().startswith('string "Micro')]
        res["notifications"] = notes
        res["missioncenter_opened"] = [x for x in missioncenter() if x not in mc0]
        res["all_ok"] = (res["grabbed_by_keyd"] and all(s["ok"] and s.get("silent", True) for s in steps)
                         and "Micro MUTED" in notes and "Micro ON" in notes and not res["missioncenter_opened"])
    finally:
        if kb is not None:
            kb.destroy()
        mon.terminate()
        if muted() != start:
            subprocess.run(["wpctl", "set-mute", SRC, "1" if start else "0"])
        res["muted_after"] = muted()
        for cid in res.get("missioncenter_opened", []):
            c.command(f"[con_id={cid}] kill")
        p.terminate()
        time.sleep(0.4)
        subprocess.run(["sway-apps", "placement", "journal", "forget", "handtest.micbtn"], capture_output=True)
        res["restored"] = snap.restore()
    print(json.dumps(res))
    return 0 if res.get("all_ok") and res["muted_after"] == start else 1


if __name__ == "__main__":
    sys.exit(main())
