#!/usr/bin/env python3
# Tiny QMP driver for the win11 guest: type text, send key combos, click (usb-tablet abs), screenshot.
import json, subprocess, sys, time
DOM = "win11"
def qmp(cmd):
    return subprocess.run(["sudo","-n","virsh","qemu-monitor-command",DOM,json.dumps(cmd)],capture_output=True,text=True).stdout
import os
def events(evs, dev=None):
    # QEMU routes untargeted events to the highest-priority handler (the virtio keyboard/tablet); target the
    # PS/2 keyboard (input3) / USB tablet (input1) explicitly when VM_KEYDEV / VM_PTRDEV are set.
    args={"events":evs}
    if dev: args["device"]=dev
    return qmp({"execute":"input-send-event","arguments":args})
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
LINUX = {'spc':'SPACE','minus':'MINUS','equal':'EQUAL','bracket_left':'LEFTBRACE','bracket_right':'RIGHTBRACE','semicolon':'SEMICOLON','apostrophe':'APOSTROPHE','grave_accent':'GRAVE','backslash':'BACKSLASH','comma':'COMMA','dot':'DOT','slash':'SLASH','ret':'ENTER','tab':'TAB','shift':'LEFTSHIFT','ctrl':'LEFTCTRL','alt':'LEFTALT','meta_l':'LEFTMETA','esc':'ESC','backspace':'BACKSPACE','up':'UP','down':'DOWN','left':'LEFT','right':'RIGHT','delete':'DELETE','home':'HOME','end':'END','pgup':'PAGEUP','pgdn':'PAGEDOWN'}
def sendkey(qcodes):
    names = ['KEY_' + LINUX.get(q, q.upper()) for q in qcodes]
    subprocess.run(["sudo","-n","virsh","send-key",DOM] + names, capture_output=True)
def type_text(s, chunk=1):  # PS/2 keyboard FIFO is 16 bytes: >1 char per QMP call drops keys (measured 2026-10-15)
    for c in s:
        shift=False
        if c in SHIFTED: shift, c = True, SHIFTED[c]
        elif c.isalpha() and c.isupper(): shift, c = True, c.lower()
        q = QCODE.get(c, c)
        sendkey((['shift'] if shift else []) + [q]); time.sleep(0.02)
        if c in DEAD or (shift and c in ("'", '`')): sendkey(['spc'])
def combo(keys):  # e.g. ['meta_l','x']
    sendkey(keys)
def click(x, y, w, h, button="left", double=False):
    ax, ay = int(x*32767/w), int(y*32767/h)
    mv = [{"type":"abs","data":{"axis":"x","value":ax}},{"type":"abs","data":{"axis":"y","value":ay}}]
    events(mv); time.sleep(0.4)  # the guest needs ~0.3 s after the move before the button (measured 2026-10-16)
    # QMP btn events never reach the guest here (measured 2026-10-16); HMP mouse_button on the current (tablet) mouse does.
    mask = {"left":1,"middle":2,"right":4}[button]
    def hmp(c): subprocess.run(["sudo","-n","virsh","qemu-monitor-command",DOM,"--hmp",c],capture_output=True)
    hmp("mouse_button %d" % mask); time.sleep(0.15); hmp("mouse_button 0")
    if double: time.sleep(0.08); hmp("mouse_button %d" % mask); time.sleep(0.15); hmp("mouse_button 0")
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
