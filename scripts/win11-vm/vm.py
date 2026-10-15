#!/usr/bin/env python3
# Tiny QMP driver for the win11 guest: type text, send key combos, click (usb-tablet abs), screenshot.
import json, subprocess, sys, time
DOM = "win11"
def qmp(cmd):
    return subprocess.run(["sudo","-n","virsh","qemu-monitor-command",DOM,json.dumps(cmd)],capture_output=True,text=True).stdout
def events(evs):
    return qmp({"execute":"input-send-event","arguments":{"events":evs}})
QCODE = {' ':'spc','-':'minus','=':'equal','[':'bracket_left',']':'bracket_right',';':'semicolon',"'":'apostrophe','`':'grave_accent','\\':'backslash',',':'comma','.':'dot','/':'slash','\n':'ret','\t':'tab'}
SHIFTED = {'!':'1','@':'2','#':'3','$':'4','%':'5','^':'6','&':'7','*':'8','(':'9',')':'0','_':'-','+':'=','{':'[','}':']',':':';','"':"'",'~':'`','|':'\\','<':',','>':'.','?':'/'}
DEAD = set("'\"`^~")  # US-International layout: dead keys, follow with space to emit the literal char
def keyev(q, down): return {"type":"key","data":{"down":down,"key":{"type":"qcode","data":q}}}
def char_events(c):
    shift = False
    if c in SHIFTED: shift, c = True, SHIFTED[c]
    elif c.isalpha() and c.isupper(): shift, c = True, c.lower()
    q = QCODE.get(c, c)
    ev = []
    if shift: ev.append(keyev('shift',True))
    ev += [keyev(q,True), keyev(q,False)]
    if shift: ev.append(keyev('shift',False))
    return ev
def type_text(s, chunk=1):  # PS/2 keyboard FIFO is 16 bytes: >1 char per QMP call drops keys (measured 2026-10-15)
    buf=[]
    for c in s:
        buf += char_events(c)
        if c in DEAD: buf += char_events(' ')
        if len(buf) >= chunk*2:
            events(buf); buf=[]; time.sleep(0.03)
    if buf: events(buf)
def combo(keys):  # e.g. ['meta_l','x']
    events([keyev(k,True) for k in keys] + [keyev(k,False) for k in reversed(keys)])
def click(x, y, w, h, button="left", double=False):
    ax, ay = int(x*32767/w), int(y*32767/h)
    mv = [{"type":"abs","data":{"axis":"x","value":ax}},{"type":"abs","data":{"axis":"y","value":ay}}]
    events(mv); time.sleep(0.05)
    press = [{"type":"btn","data":{"down":True,"button":button}},{"type":"btn","data":{"down":False,"button":button}}]
    events(press)
    if double: time.sleep(0.08); events(press)
def shot(path):
    subprocess.run(["sudo","-n","virsh","screenshot",DOM,path+".ppm"],capture_output=True)
    subprocess.run(["sudo","-n","chown",str(__import__('os').getuid()),path+".ppm"])
    subprocess.run(["magick",path+".ppm","-resize","50%",path+".png"])
    return path+".png"
if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0]=="type": type_text(a[1])
    elif a[0]=="key": combo(a[1].split('+'))
    elif a[0]=="click": click(int(a[1]),int(a[2]),int(a[3]),int(a[4]),a[5] if len(a)>5 else "left")
    elif a[0]=="shot": print(shot(a[1]))
    elif a[0]=="sleep": time.sleep(float(a[1]))
