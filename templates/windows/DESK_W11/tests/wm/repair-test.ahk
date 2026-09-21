#Requires AutoHotkey v2.0
#SingleInstance Force
; The layout journal and the repair: what happens after a monitor takes a nap.
; The damage is reproduced by hand instead of by unplugging a screen -- a
; window shrunk to its title bar, a window parked off the desktop, a window
; dragged to the other monitor, a workspace attached to the wrong monitor --
; because that is exactly what a sleep cycle leaves behind, and it can be
; undone without touching the hardware.
; Run: AutoHotkey64.exe repair-test.ahk   -> %TEMP%\perf\repair-test.txt
#Include ..\..\lib-repair.ahk
#Include ..\..\lib-app-toggle.ahk

DetectHiddenWindows true
flip := A_Temp "\perf\fliptest.exe"
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
CheckNear(name, got, want, tol) {
    global out, fails
    ok := Abs(got - want) <= tol
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want " +-" tol ")`n"
    if !ok
        fails++
}
Note(msg) {
    global out
    out .= "     " msg "`n"
}
Rec(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w
    return Map("id", "", "state", "unmanaged", "ws", "?", "proc", "", "class", "",
               "focus", false, "display", "-", "sticky", false, "hwnd", 0, "title", "-")
}
WRect(hwnd) {                            ; plain rect, as the journal sees it
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
    return Map("x", x, "y", y, "w", w, "h", h)
}
Rs(hwnd) {
    r := WRect(hwnd)
    return r["x"] "," r["y"] " " r["w"] "x" r["h"]
}
StartFlip(args, &pid) {
    global flip
    Run(flip " " args, , , &pid)
    WinWait("ahk_pid " pid, , 10)
    Sleep 1800
    return WinExist("ahk_pid " pid)
}
KillFlips() {
    try RunWait(A_ComSpec ' /c taskkill /F /IM fliptest.exe', , "Hide")
    Sleep 1200
}
EmptyWs(prefix) {
    used := Map()
    for w in GlazeWins()
        used[w["ws"]] := true
    Loop 9 {
        n := prefix A_Index
        if (!used.Has(n))
            return n
    }
    return prefix "9"
}
FocusWs(name) {
    wss := GlazeWss()
    if (!wss.Has(name) || !wss[name]) {
        Glaze("focus --workspace " name)
        Sleep 1200
    }
}

; --- 0. a healthy window is written down, with its monitor's work area -----
KillFlips()
home := EmptyWs("1")
FocusWs(home)
MouseMove(400, 600, 0)
Sleep 400
hwnd := StartFlip("300 0 400 300 1200 900 now", &pid)
Check("0 setup: a window on the main monitor", Rec(hwnd)["state"], "floating")
good := WRect(hwnd)
Note("0 window at " Rs(hwnd))
JournalSnapshot(true)
entries := JournalRead()
key := JournalKey(Rec(hwnd)["proc"], Rec(hwnd)["class"])
device := MonitorDeviceAt(good["x"] + good["w"] // 2, good["y"] + good["h"] // 2)
Check("0 the journal knows this window", entries.Has(key) ? 1 : 0, 1)
Check("0 ... on this monitor", (entries.Has(key) && entries[key].Has(device)) ? 1 : 0, 1)
if (entries.Has(key) && entries[key].Has(device)) {
    r := entries[key][device]
    Check("0 with the size it has", r["w"] "x" r["h"], good["w"] "x" good["h"])
    Check("0 and the monitor's work area", r["areaW"] > 1000 ? 1 : 0, 1)
}

; --- 1. a window shrunk to its title bar comes back ------------------------
WinMove(900, 500, 219, 30, "ahk_id " hwnd)     ; Telegram's 219x30 after a nap
Sleep 1500
Note("1 shrunk to " Rs(hwnd))
Check("1 setup: it is broken", JournalIsBroken(WRect(hwnd)["x"], WRect(hwnd)["y"], WRect(hwnd)["w"], WRect(hwnd)["h"]) ? 1 : 0, 1)
RepairLayout(false)
Sleep 1200
Note("1 after the repair: " Rs(hwnd))
Check("1 restored to the recorded size", WRect(hwnd)["w"] "x" WRect(hwnd)["h"], good["w"] "x" good["h"])
CheckNear("1 and the recorded position", WRect(hwnd)["x"], good["x"], 20)

; --- 2. a window parked off the desktop comes back ------------------------
WinMove(-31900, -31900, 1200, 900, "ahk_id " hwnd)   ; parked off the desktop
Sleep 1500
Note("2 parked at " Rs(hwnd))
Check("2 setup: it is off screen", JournalIsBroken(WRect(hwnd)["x"], WRect(hwnd)["y"], WRect(hwnd)["w"], WRect(hwnd)["h"]) ? 1 : 0, 1)
RepairLayout(false)
Sleep 1200
Note("2 after the repair: " Rs(hwnd))
Check("2 back on a screen", WindowOnScreenFraction(WRect(hwnd)["x"], WRect(hwnd)["y"], WRect(hwnd)["w"], WRect(hwnd)["h"]) > 0.9 ? 1 : 0, 1)
Check("2 with its size", WRect(hwnd)["w"] "x" WRect(hwnd)["h"], good["w"] "x" good["h"])

; --- 3. a size from another monitor is scaled, not copied ------------------
vert := ""
Loop MonitorGetCount() {
    if (A_Index != MonitorGetPrimary())
        vert := MonitorGetName(A_Index)
}
if (vert != "") {
    MonitorWorkArea(device, &pl, &pt, &pr, &pb)
    MonitorWorkArea(vert, &vl, &vt, &vr, &vb)
    ; A synthetic record, not the live journal: the journal is persistent, so
    ; after the first run it has seen the vertical monitor too and would
    ; return an exact record -- right in real life, useless for checking the
    ; scaling that happens when a monitor was never seen.
    fake := Map(key, Map(device, Map("ws", home, "state", "floating", "sticky", false,
        "x", good["x"], "y", good["y"], "w", good["w"], "h", good["h"],
        "areaL", pl, "areaT", pt, "areaW", pr - pl, "areaH", pb - pt, "stamp", A_Now)))
    place := JournalPlacement(fake, key, vert)
    Note("3 main work area " (pr - pl) "x" (pb - pt) ", vertical " (vr - vl) "x" (vb - vt))
    Note("3 " good["w"] "x" good["h"] " on the main monitor -> " (place ? place["w"] "x" place["h"] : "?") " on the vertical one")
    Check("3 there is a placement for a monitor it never saw", place ? 1 : 0, 1)
    if place {
        Check("3 it is marked as scaled, not exact", place["exact"] ? 1 : 0, 0)
        CheckNear("3 same fraction of the width", Round(place["w"] * 1000 / (vr - vl)),
            Round(good["w"] * 1000 / (pr - pl)), 30)
        Check("3 it fits on that monitor", (place["w"] <= (vr - vl) && place["h"] <= (vb - vt)) ? 1 : 0, 1)
    }
}

; --- 4. a workspace attached to the wrong monitor goes back ---------------
; (what a sleep cycle leaves: ws 21 on the main monitor, ws 11 on the vertical)
wsId := GlazeWsId(home)
Check("4 setup: the test workspace exists", wsId != "" ? 1 : 0, 1)
before := ""
for mon in GlazeMonitors()
    for wsEntry in mon["wss"]
        if (wsEntry["name"] = home)
            before := mon["device"]
GlazeOn(wsId, "move-workspace --direction right")
Sleep 1500
after := ""
for mon in GlazeMonitors()
    for wsEntry in mon["wss"]
        if (wsEntry["name"] = home)
            after := mon["device"]
Note("4 workspace " home ": " before " -> " after)
if (after != before) {
    RepairWorkspaces()
    Sleep 1500
    back := ""
    for mon in GlazeMonitors()
        for wsEntry in mon["wss"]
            if (wsEntry["name"] = home)
                back := mon["device"]
    Note("4 after the repair: " back)
    Check("4 the workspace is back on its monitor", back, before)
} else {
    Note("4 the workspace did not move (one monitor?), skipped")
}

; --- 5. the guards: what the repair must NOT do ---------------------------
; A window that is simply small is not broken (a calculator is 320x500).
Check("5 a small window with no history is left alone",
    JournalIsBroken(100, 100, 250, 180, false) ? 1 : 0, 0)
Check("5 the same size IS broken when it was much bigger",
    JournalIsBroken(100, 100, 250, 180, true) ? 1 : 0, 1)
Check("5 off the screen is broken for anybody",
    JournalIsBroken(-31900, -31900, 1200, 900, false) ? 1 : 0, 1)

; A fullscreen window (a game) never gets a rectangle from the repair.
game := StartFlip("40 0 gamelike", &pg)
Sleep 2500
gameRec := Rec(game)                 ; not `rec`: Rec() is a function here
Check("5 setup: the game is fullscreen", gameRec["state"], "fullscreen")
gameRect := Rs(game)
Check("5 the repair refuses to place a fullscreen window",
    RepairPlaceWindow(gameRec, Map("x", 100, "y", 100, "w", 800, "h", 600)) ? 1 : 0, 0)
Check("5 so the game is untouched", Rs(game), gameRect)
; And it does not even run while one is in front.
res := RepairLayout(true)
Note("5 repair with the game in front: " res["workspaces"] " workspace(s), " res["windows"] " window(s)")
Check("5 the whole repair is skipped with a game in front", res["windows"], 0)
try ProcessClose(pg)
Sleep 1500

; --- 6. GlazeWM not answering must never look like "no windows" -----------
Check("6 an answer is recognised", GlazeAnswered(GlazeQuery("workspaces")) ? 1 : 0, 1)
Check("6 an empty answer is not", GlazeAnswered("") ? 1 : 0, 0)
Check("6 nor is a truncated one", GlazeAnswered('{"data":{}}') ? 1 : 0, 0)

KillFlips()
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\repair-test.txt")
FileAppend(out, A_Temp "\perf\repair-test.txt")
ExitApp
