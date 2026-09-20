#Requires AutoHotkey v2.0
#SingleInstance Force
; The window rules ported from sway (swayfx-config.nix): the apps that float
; and follow you between workspaces there must do the same here, and the ones
; that tile there must tile here.
; Run: AutoHotkey64.exe rules-test.ahk   -> %TEMP%\perf\rules-test.txt
#Include ..\..\lib-window-state.ahk
#Include ..\..\lib-glaze.ahk
#Include ..\..\lib-app-toggle.ahk

DetectHiddenWindows true
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
ByProc(proc) {
    for w in GlazeWins()
        if (StrLower(w["proc"]) = StrLower(proc))
            return w
    return 0
}
WaitProc(proc, timeoutMs := 15000) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if (w := ByProc(proc))
            return w
        Sleep 300
    }
    return 0
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
Kill(name) {
    try RunWait(A_ComSpec ' /c taskkill /F /IM ' name, , "Hide")
}

startWs := GlazeFocusedWs()
home := EmptyWs("1")
Glaze("focus --workspace " home)
Sleep 1200
Note("home " home ", started on " startWs)

; --- the calculator: sway floats it and makes it sticky --------------------
Kill("CalculatorApp.exe")
Sleep 800
Run("calc")
w := 0
deadline := A_TickCount + 15000
while (A_TickCount < deadline && !w) {
    for x in GlazeWins()                        ; a store app: the process is
        if (x["class"] = "ApplicationFrameWindow"   ; ApplicationFrameHost for
            && InStr(x["title"], "Calculator"))     ; all of them, so match the title
            w := x
    Sleep 300
}
Check("1 the calculator is managed", w ? 1 : 0, 1)
if w {
    Note("1 " w["proc"] " state=" w["state"] " sticky=" (w["sticky"] ? 1 : 0) " ws=" w["ws"])
    Check("1 it floats (sway: floating enable)", w["state"], "floating")
    Check("1 and is sticky (sway: sticky enable)", w["sticky"] ? 1 : 0, 1)
}

; --- a file manager window: sway floats Dolphin and makes it sticky --------
Run("explorer.exe shell:MyComputerFolder")
ex := 0
deadline := A_TickCount + 15000
while (A_TickCount < deadline && !ex) {
    for x in GlazeWins()
        if (x["class"] = "CabinetWClass" && x["ws"] = home)
            ex := x
    Sleep 300
}
Check("2 the file manager window is managed", ex ? 1 : 0, 1)
if ex {
    Note("2 explorer state=" ex["state"] " sticky=" (ex["sticky"] ? 1 : 0))
    Check("2 it floats (sway: org.kde.dolphin)", ex["state"], "floating")
    Check("2 and is sticky", ex["sticky"] ? 1 : 0, 1)
    WinClose("ahk_id " ex["hwnd"])
}

; --- the terminals: sway floats and sticks kitty and Alacritty -------------
for term in [["WindowsTerminal", "wt.exe"], ["alacritty", A_ProgramFiles "\Alacritty\alacritty.exe"]] {
    t := ByProc(term[1])
    if !t {
        try Run term[2]
        t := WaitProc(term[1])
        opened := true
    }
    Check("2b " term[1] " is managed", t ? 1 : 0, 1)
    if t {
        Note("2b " term[1] " state=" t["state"] " sticky=" (t["sticky"] ? 1 : 0))
        Check("2b " term[1] " floats (sway: kitty/Alacritty)", t["state"], "floating")
        Check("2b " term[1] " is sticky", t["sticky"] ? 1 : 0, 1)
    }
}

; --- an app with no rule tiles, like everything else in sway ---------------
Kill("notepad.exe")
Sleep 800
Run("notepad.exe")
np := WaitProc("Notepad")
Check("3 a window with no rule is managed", np ? 1 : 0, 1)
if np {
    Note("3 notepad state=" np["state"] " sticky=" (np["sticky"] ? 1 : 0))
    Check("3 it tiles (sway: default layout)", np["state"], "tiling")
    Check("3 and is not sticky", np["sticky"] ? 1 : 0, 0)
}

Kill("notepad.exe")
Kill("CalculatorApp.exe")
Sleep 500
if (startWs != "")
    Glaze("focus --workspace " startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\rules-test.txt")
FileAppend(out, A_Temp "\perf\rules-test.txt")
ExitApp
