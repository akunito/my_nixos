import json, os, subprocess, sys, time
SP=os.environ.get("LIVE_OUT", "/tmp")
E2E=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "e2e")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from sway_apps import ipc
PY=os.environ["E2E_PYTHON"]
c=ipc.Connection(os.environ["SWAYSOCK"])
def state():
    return json.loads(subprocess.run(["sway-apps","--json","overview","state"],capture_output=True,text=True).stdout or "{}")
def node(pred):
    def walk(n):
        if pred(n): return n
        for ch in n.get("nodes",[])+n.get("floating_nodes",[]):
            r=walk(ch)
            if r: return r
    return walk(c.tree())
focused=lambda: (lambda f: (f.get("id"), f.get("app_id") or (f.get("window_properties") or {}).get("class")))(node(lambda n: n.get("focused")))
res={"focus_before": focused()}
safe=subprocess.Popen([PY, f"{E2E}/client.py","--app-id","handtest.safe","--size","300x150","--title","handtest (safe keyboard sink)"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
kb=None
try:
    for _ in range(100):
        if node(lambda n: n.get("app_id")=="handtest.safe"): break
        time.sleep(0.05)
    c.command('[app_id="^handtest.safe$"] floating enable, move position center, focus')
    time.sleep(0.3)
    assert focused()[1]=="handtest.safe", f"safe window not focused: {focused()}"
    kb=subprocess.Popen([PY, f"{E2E}/vkeyboard.py"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=E2E)
    assert kb.stdout.readline().strip()=="ready"
    def k(line):
        kb.stdin.write(line+"\n"); kb.stdin.flush(); kb.stdout.readline()
    def k_if_open(line):
        if state().get("open"): k(line); return True
        return False
    t=time.time(); k("mods 76"); k("key Tab"); k("mods 0")
    for _ in range(40):
        if state().get("open"): break
        time.sleep(0.05)
    res["open"]=state().get("open"); res["open_wait_ms"]=int((time.time()-t)*1000)
    time.sleep(0.3)
    subprocess.run(["grim","-s","0.5",os.path.join(SP, "ov1.png")])
    st=state(); res["latency_ms"]=st.get("latency_ms"); res["thumbs"]=len(st.get("thumbs") or []); res["selected_start"]=st.get("selected")
    k_if_open("key Right"); time.sleep(0.2); res["selected_after_right"]=state().get("selected")
    sel=res["selected_after_right"]
    if k_if_open("key Return"):
        time.sleep(0.6)
        res["closed_after_enter"]=not state().get("open"); res["focus_after_enter"]=focused(); res["focused_is_selected"]=focused()[0]==sel
    # back to the safe window, reopen, close with Escape
    c.command('[app_id="^handtest.safe$"] focus'); time.sleep(0.3)
    k("mods 76"); k("key Tab"); k("mods 0"); time.sleep(0.5); res["reopened"]=state().get("open")
    k_if_open("key Escape"); time.sleep(0.4); res["closed_by_esc"]=not state().get("open")
finally:
    if kb: 
        try:
            kb.stdin.write("mods 0\n"); kb.stdin.flush()
        except Exception: pass
        kb.terminate()
    subprocess.run(["sway-apps","overview","hide"],capture_output=True)
    safe.terminate()
    time.sleep(0.4)
    c.command("[con_id=7] focus")
    res["focus_restored"]=focused()
print(json.dumps(res))
