import json, os, subprocess, sys, time
E2E=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "e2e")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from sway_apps import ipc
PY=os.environ["E2E_PYTHON"]; c=ipc.Connection(os.environ["SWAYSOCK"])
st=lambda: json.loads(subprocess.run(["sway-apps","--json","overview","state"],capture_output=True,text=True).stdout or "{}")
def node(pred):
    def walk(n):
        if pred(n): return n
        for ch in n.get("nodes",[])+n.get("floating_nodes",[]):
            r=walk(ch)
            if r: return r
    return walk(c.tree())
res={}
safe=subprocess.Popen([PY,f"{E2E}/client.py","--app-id","handtest.safe","--size","300x150","--log",os.path.join(os.environ.get("LIVE_OUT", "/tmp"), "safe.log")],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
kb=None
try:
    for _ in range(100):
        if node(lambda n: n.get("app_id")=="handtest.safe"): break
        time.sleep(0.05)
    c.command('[app_id="^handtest.safe$"] floating enable, move position center, focus'); time.sleep(0.3)
    res["focused"]=node(lambda n: n.get("focused")).get("app_id")
    kb=subprocess.Popen([PY,f"{E2E}/vkeyboard.py"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,cwd=E2E); kb.stdout.readline()
    k=lambda l:(kb.stdin.write(l+"\n"),kb.stdin.flush(),kb.stdout.readline())
    subprocess.run(["sway-apps","overview","show"],capture_output=True); time.sleep(0.6)
    res["open"]=st().get("open"); res["sel0"]=st().get("selected")
    if st().get("open"): k("key Down"); time.sleep(0.3); res["sel_after_down"]=st().get("selected")
    if st().get("open"): k("key Escape"); time.sleep(0.4); res["closed_by_esc"]=not st().get("open")
finally:
    if kb: kb.terminate()
    subprocess.run(["sway-apps","overview","hide"],capture_output=True); safe.terminate(); time.sleep(0.3); c.command("[con_id=7] focus")
    res["focus_restored"]=node(lambda n: n.get("focused")).get("app_id")
print(json.dumps(res))
