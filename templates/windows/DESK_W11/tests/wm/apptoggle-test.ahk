#Requires AutoHotkey v2.0
#SingleInstance Force
; Hyper+<letter> (AppToggle) against Sway's app-toggle.sh decision table.
; Run: AutoHotkey64.exe apptoggle-test.ahk   -> %TEMP%\perf\apptoggle-test.txt
; Takes over two empty workspaces of the primary monitor and the pointer for
; ~90 s. Focus follows the mouse here, so every case walks the cursor to the
; window it wants focused (an injected teleport does not move the focus).
#Include ..\..\lib-window-state.ahk
#Include ..\..\lib-glaze.ahk
#Include ..\..\lib-app-toggle.ahk

DetectHiddenWindows true
SetWinDelay -1
flip := A_Temp "\perf\fliptest.exe"
out := "", fails := 0

Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
Note(msg) {
    global out
    out .= "     " msg "`n"
}
; Injected relative moves go through the pointer acceleration, so they land
; near the target and not on it: finish with an exact placement.
WalkCursorTo(x, y) {
    MouseGetPos &cx, &cy
    Loop 12 {
        dx := (x - cx) // 12, dy := (y - cy) // 12
        DllCall("mouse_event", "UInt", 0x0001, "Int", dx, "Int", dy, "UInt", 0, "Ptr", 0)
        Sleep 15
        MouseGetPos &cx, &cy
    }
    DllCall("SetCursorPos", "Int", x, "Int", y)
    Sleep 400
}
; The vertical monitor lives at virtualised coordinates (AHK is system-DPI
; aware), so reaching it needs MouseMove, not a raw SetCursorPos.
MoveCursorTo(x, y) {
    CoordMode "Mouse", "Screen"
    MouseMove x, y, 10
    Sleep 400
}
MonCenter(primary) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if ((MonitorGetPrimary() = A_Index) = primary)
            return [(l + r) // 2, (t + b) // 2]
    }
    return [100, 100]
}
StartFlip(x, y, w, h) {
    global flip
    Run(flip " 300 0 " x " " y " " w " " h " now", , , &pid)
    if !WinWait("ahk_pid " pid, , 10)
        return 0
    Sleep 1200                      ; let GlazeWM manage it
    return WinExist("ahk_pid " pid)
}
KillFlips() {
    for p in ["fliptest.exe", "charmap.exe", "notepad.exe"]
        try RunWait(A_ComSpec ' /c taskkill /F /IM ' p, , "Hide")
    Sleep 1500
}
WsOf(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w["ws"]
    return "unmanaged"
}
StateOf(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w["state"]
    return "unmanaged"
}
DisplayedWss() {
    names := ""
    for name, shown in GlazeWss()
        if shown
            names .= (names ? "," : "") name
    return names
}
; An empty workspace of the primary monitor (names 1x), so the user's own
; windows can never decide a focus assertion.
EmptyWs(skip := "") {
    used := Map()
    for w in GlazeWins()
        used[w["ws"]] := true
    Loop 9 {
        n := "1" A_Index
        if (n != skip && !used.Has(n))
            return n
    }
    return "1" (skip = "18" ? "9" : "8")
}
Park() {                            ; pointer on empty desktop, nothing focused
    WalkCursorTo(3600, 1900)
}
; Focus a workspace, but never ask for the one already focused: with
; toggle_workspace_on_refocus that jumps to the previous one instead.
FocusWs(ws) {   ; not GoTo(): that is an AHK control-flow keyword
    ; Ask by "is it displayed", not by "is it focused": with nothing focused
    ; (an empty workspace) the focused workspace reads empty, and asking for
    ; the workspace you are already on toggles to the previous one.
    wss := GlazeWss()
    if (!wss.Has(ws) || !wss[ws]) {
        Glaze("focus --workspace " ws)
        Sleep 1200
    }
}

; ---------------------------------------------------------------------------
KillFlips()
startWs := GlazeFocusedWs()
home := EmptyWs()
Glaze("focus --workspace " home)
Sleep 1200
other := EmptyWs(home)
Note("home workspace " home ", spare workspace " other ", started on " startWs)
Park()
FocusWs(home)                          ; the walk crosses the other monitor
Note("1 launching from workspace " GlazeFocusedWs())

; --- 1. no window -> launch, and follow the new window ---------------------
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
Sleep 1500
h := WinExist("ahk_class FlipTestWnd")
Check("1 launch: a window appeared", h ? 1 : 0, 1)
Check("1 launch: it is focused", WinActive("ahk_id " h) ? 1 : 0, 1)
Check("1 launch: on the workspace we are on", WsOf(h), home)

; --- 2. one window, focused -> hide (minimise) -----------------------------
WalkCursorTo(700, 700)              ; hover it: with focus following the mouse,
Sleep 500                           ; a pointer on the desktop focuses the desktop
t := A_TickCount
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
hideMs := A_TickCount - t
Sleep 1200
Note("2 hide took " hideMs " ms")
Check("2 hiding is instant (no query)", hideMs < 300 ? 1 : 0, 1)
Check("2 focused -> minimised", WinGetMinMax("ahk_id " h), -1)
Check("2 GlazeWM agrees", StateOf(h), "minimized")

; --- 3. minimised -> comes to the workspace you are on, restored, focused --
FocusWs(other)
Park()
FocusWs(other)
t := A_TickCount
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
showMs := A_TickCount - t
Sleep 1500
Note("3 show took " showMs " ms")
Check("3 showing takes one query, not three", showMs < 900 ? 1 : 0, 1)
Check("3 minimised window restored", WinGetMinMax("ahk_id " h) = -1 ? "minimised" : "restored", "restored")
Check("3 it came to where we are", WsOf(h), other)
Check("3 and it has the focus", WinActive("ahk_id " h) ? 1 : 0, 1)

; --- 4. parked on another workspace -> we go to it, it does not move -------
FocusWs(home)
Park()
FocusWs(home)
Check("4 setup: window is away", InStr(DisplayedWss(), other) ? 1 : 0, 0)
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
Sleep 1500
Check("4 we moved to its workspace", WsOf(h), other)
Check("4 its workspace is displayed", InStr(DisplayedWss(), other) ? 1 : 0, 1)
t0 := A_TickCount
while (!IsOnScreen(h) && A_TickCount - t0 < 3000)
    Sleep 200
Note("4 after " (A_TickCount - t0) " ms: visible=" DllCall("IsWindowVisible", "Ptr", h) " cloaked=" Cloaked(h) " minmax=" WinGetMinMax("ahk_id " h) " glaze=" StateOf(h) "/" WsOf(h))
Check("4 the window is on screen", IsOnScreen(h) ? 1 : 0, 1)
Check("4 and focused", WinActive("ahk_id " h) ? 1 : 0, 1)

; --- 5. two windows, one focused -> cycle ----------------------------------
h2 := StartFlip(1500, 300, 900, 700)
Check("5 setup: second window", h2 ? 1 : 0, 1)
WalkCursorTo(1900, 700)             ; over the second window
Sleep 500
Check("5 setup: second window focused", WinActive("ahk_id " h2) ? 1 : 0, 1)
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
Sleep 1200
Check("5 cycles to the other window", WinActive("ahk_id " h) ? 1 : 0, 1)
Check("5 neither was minimised", (WinGetMinMax("ahk_id " h) = -1 || WinGetMinMax("ahk_id " h2) = -1) ? 1 : 0, 0)

; --- 6. two windows, none focused, one minimised -> the minimised one wins -
WinMinimize("ahk_id " h2)
Sleep 800
Park()
AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
Sleep 1500
Check("6 the hidden window is the one shown", WinActive("ahk_id " h2) ? 1 : 0, 1)
Check("6 restored", WinGetMinMax("ahk_id " h2) = -1 ? "minimised" : "restored", "restored")

; --- 7. a fullscreen window keeps the screen when an app is launched -------
KillFlips()
Sleep 1000
FocusWs(home)
Run(flip " 120 0 gamelike", , , &gpid)   ; borderless, covers the monitor
WinWait("ahk_pid " gpid, , 10)
Sleep 2500
game := WinExist("ahk_pid " gpid)
Check("7 setup: fullscreen state", StateOf(game), "fullscreen")
WalkCursorTo(1900, 1000)
Sleep 800
Check("7 setup: the game has the focus", WinActive("ahk_id " game) ? 1 : 0, 1)
AppToggle("notepad.exe", "notepad.exe")
Sleep 2000
cm := 0                             ; by process, not WinExist: with hidden
for w in GlazeWins()                ; windows on, WinExist finds helper windows
    if (StrLower(w["proc"]) = "notepad")
        cm := w["hwnd"]
Check("7 the app did open", cm ? 1 : 0, 1)
Check("7 the game kept the foreground", WinActive("ahk_id " game) ? 1 : 0, 1)
Check("7 the app is on the same workspace", WsOf(cm), home)

; --- 7b. asking for that app by its key lifts it over the game -------------
if (cm && game) {
    AppToggle("notepad.exe", "notepad.exe")
    Sleep 1500
    top := 0, x := DllCall("GetTopWindow", "Ptr", 0, "Ptr")
    while (x && !top) {
        if (x = cm)
            top := "app"
        else if (x = game)
            top := "game"
        x := DllCall("GetWindow", "Ptr", x, "UInt", 2, "Ptr")
    }
    Check("7b asking for it by name lifts it over the game", top, "app")
}

; --- 8. the same for a TILED app: it must come back tiled, where you are ---
KillFlips()
Sleep 800
FocusWs(home)
Run("notepad.exe")
np := 0, deadline := A_TickCount + 15000
while (A_TickCount < deadline && !np) {
    for w in GlazeWins()
        if (StrLower(w["proc"]) = "notepad")
            np := w
    Sleep 300
}
; Windows 11 Notepad brings back every window it had when it was killed:
; after a taskkill it can come up as four. The case is about ONE window of a
; tiled app, so the extras go, and the last one standing is the subject.
extra := 0
if np
    for w in GlazeWins()
        if (StrLower(w["proc"]) = "notepad" && w["hwnd"] != np["hwnd"]) {
            try WinClose("ahk_id " w["hwnd"])
            extra++
        }
if extra {
    Sleep 1500
    Note("8 closed " extra " extra Notepad window(s) the app restored")
}
Check("8 setup: notepad tiles", np ? np["state"] : "missing", "tiling")
if np {
    WalkCursorTo(1200, 900)         ; hover it so it is really focused
    Sleep 600
    AppToggle("notepad.exe", "notepad.exe")
    Sleep 1200
    Check("8 focused -> minimised", WinGetMinMax("ahk_id " np["hwnd"]), -1)
    FocusWs(other)
    Park()
    FocusWs(other)
    AppToggle("notepad.exe", "notepad.exe")
    Sleep 1800
    rec := 0
    for w in GlazeWins()
        if (w["hwnd"] = np["hwnd"])
            rec := w
    Note("8 after show: ws=" (rec ? rec["ws"] : "?") " state=" (rec ? rec["state"] : "?"))
    Check("8 came to the workspace we are on", rec ? rec["ws"] : "?", other)
    Check("8 and tiles again", rec ? rec["state"] : "?", "tiling")
    try RunWait(A_ComSpec ' /c taskkill /F /IM notepad.exe', , "Hide")
}

; --- 9. a hidden window comes back to the monitor the POINTER is on --------
; Sway's focused output is the one under the pointer, so `scratchpad show`
; puts the window there. Taking the focused window's workspace instead sent it
; to the other monitor whenever something there still held the focus.
KillFlips()
Sleep 800
FocusWs(home)
main := MonCenter(true), vert := MonCenter(false)
h3 := StartFlip(300, 300, 900, 700)
if h3 {
    WalkCursorTo(700, 700)              ; hover it, then hide it
    Sleep 500
    AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
    Sleep 1200
    Check("9 setup: minimised on the main monitor", WinGetMinMax("ahk_id " h3), -1)
    MoveCursorTo(vert[1], vert[2])      ; now point at the other monitor
    AppToggle("fliptest.exe", flip " 300 0 300 300 900 700 now")
    Sleep 1800
    rec := 0
    for w in GlazeWins()
        if (w["hwnd"] = h3)
            rec := w
    Note("9 came back to workspace " (rec ? rec["ws"] : "?"))
    Check("9 it came to the monitor the pointer is on",
        rec ? String(WsGroup(rec["ws"])) : "?", "2")
    MoveCursorTo(main[1], main[2])
}

; ---------------------------------------------------------------------------
KillFlips()
if (startWs != "")
    Glaze("focus --workspace " startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\apptoggle-test.txt")
FileAppend(out, A_Temp "\perf\apptoggle-test.txt")
ExitApp
