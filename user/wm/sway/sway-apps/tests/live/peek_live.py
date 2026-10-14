"""Live peek check on the real session: temp workspace, red tile, blue float on top,
hold left button on the visible part of the tile, sample the overlap pixel."""
import json, os, subprocess, sys, time
E2E = "/home/akunito/.dotfiles/user/wm/sway/sway-apps/tests/e2e"
sys.path.insert(0, "/home/akunito/.dotfiles/user/wm/sway/sway-apps")
from sway_apps import ipc
PY = os.environ["E2E_PYTHON"]
c = ipc.Connection(os.environ["SWAYSOCK"])
prev = next(w["name"] for w in c.workspaces() if w["focused"])
procs = []

def node(app):
    def walk(n):
        if n.get("app_id") == app: return n
        for ch in n.get("nodes", []) + n.get("floating_nodes", []):
            r = walk(ch)
            if r: return r
    return walk(c.tree())

def wait(f, what, t=5):
    end = time.time() + t
    while time.time() < end:
        v = f()
        if v: return v
        time.sleep(0.03)
    raise SystemExit(f"timeout: {what}")

def pixel(x, y):
    out = subprocess.run(["grim", "-g", f"{x},{y} 1x1", "-t", "ppm", "-"], capture_output=True, check=True).stdout
    return tuple(out[-3:])

def name(px):
    r, g, b = px
    return "red" if r > 150 and b < 100 else "blue" if b > 150 and r < 100 else f"other{px}"

vp = subprocess.Popen([PY, f"{E2E}/vpointer.py"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
procs.append(vp)
assert vp.stdout.readline().strip() == "ready"
outs = [o["rect"] for o in c.outputs() if o["active"]]
EW, EH = max(r["x"] + r["width"] for r in outs), max(r["y"] + r["height"] for r in outs)
def vpc(line):
    vp.stdin.write(line + "\n"); vp.stdin.flush(); assert vp.stdout.readline().strip() == "ok"
try:
    c.command("workspace peek-test")
    procs.append(subprocess.Popen([PY, f"{E2E}/client.py", "--app-id", "peek.tile", "--color", "ff0000"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    wait(lambda: node("peek.tile"), "tile mapped")
    procs.append(subprocess.Popen([PY, f"{E2E}/client.py", "--app-id", "peek.float", "--color", "0000ff"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    wait(lambda: node("peek.float"), "float mapped")
    c.command("[app_id=peek.float] floating enable, resize set 500 500, move position center")
    time.sleep(0.4)
    f = node("peek.float")["rect"]; t = node("peek.tile")["rect"]
    ox, oy = f["x"] + f["width"] // 2, f["y"] + f["height"] // 2          # overlap sample (centre of the float)
    px, py = t["x"] + 60, t["y"] + 60                                        # visible part of the tile
    res = {"before": name(pixel(ox, oy))}
    vpc(f"abs {px} {py} {EW} {EH}"); vpc("press left"); time.sleep(0.25)
    res["held_left"] = name(pixel(ox, oy))
    vpc("release left"); time.sleep(0.25)
    res["after_left"] = name(pixel(ox, oy))
    vpc("press right"); time.sleep(0.25)
    res["held_right"] = name(pixel(ox, oy))
    vpc("release right"); time.sleep(0.25)
    res["after_right"] = name(pixel(ox, oy))
    print(json.dumps(res))
finally:
    for p in procs:
        p.terminate()
    time.sleep(0.3)
    c.command(f"workspace {prev}")
