#Requires AutoHotkey v2.0
#SingleInstance Force
; The sudo askpass of NixOS-WSL is a native Windows box (system/security/
; windows-password-box.ps1) because WSLg on this desk paints only the first
; Linux window of a boot: every later zenity was an empty surface with AkuWM's
; border round it (2026-10-02). The box must be PAINTED, small, whole on the
; monitor the pointer is on, and hand back exactly what was typed.
; Run: AutoHotkey64.exe askpass-test.ahk -> %TEMP%\perf\askpass-test.txt
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
SetTitleMatchMode 3
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
MonOf(x, y) {
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return 0
}
Samples(cx, cy) {
    a := []
    Loop 4 {
        row := A_Index
        Loop 4
            a.Push(PixelGetColor(cx - 150 + A_Index * 60, cy - 60 + row * 24))
    }
    return a
}
script := EnvGet("USERPROFILE") "\.dotfiles\system\security\windows-password-box.ps1"
Check("0 setup: the askpass script is in the Windows clone", FileExist(script) ? 1 : 0, 1)
Scenario(label, px, py, secret) {
    global out, script
    result := A_Temp "\perf\askpass-" label ".out"
    try FileDelete result
    DllCall("SetCursorPos", "Int", px, "Int", py)
    Sleep 300
    mon := MonOf(px, py)
    MonitorGetWorkArea mon, &l, &t, &r, &b
    before := Samples((l + r) // 2, (t + b) // 2)
    Run A_ComSpec ' /c powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' script '" -Prompt "[sudo] password for test:" > "' result '"', , "Hide"
    hwnd := WinWait("sudo ahk_exe powershell.exe", , 12)
    Check(label ": the box appeared", hwnd ? 1 : 0, 1)
    if !hwnd
        return
    MouseGetPos &hx, &hy
    if (Abs(hx - px) > 4 || Abs(hy - py) > 4) {
        out .= Format("     {1}: DISTURBED -- the pointer was left at {2},{3} and is at {4},{5}; scenario not judged`n", label, px, py, hx, hy)
        try WinClose "ahk_id " hwnd
        return
    }
    Sleep 1500
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    out .= Format("     {1}: box {2},{3} {4}x{5}; pointer monitor {6} work area [{7},{8} {9}x{10}]`n", label, x, y, w, h, mon, l, t, r - l, b - t)
    Check(label ": it is small", (w <= 900 && h <= 450) ? 1 : 0, 1)
    Check(label ": it is whole on the monitor the pointer is on", (x >= l && y >= t && x + w <= r && y + h <= b) ? 1 : 0, 1)
    after := Samples((l + r) // 2, (t + b) // 2), changed := 0
    Loop 16
        changed += (before[A_Index] != after[A_Index]) ? 1 : 0
    out .= Format("     {1}: {2} of 16 sampled pixels changed when the box appeared`n", label, changed)
    Check(label ": it is painted", changed >= 8 ? 1 : 0, 1)
    ; Through its own controls, never global keystrokes: nothing can land in
    ; whatever else has the focus.
    editCtl := "", okBtn := ""
    for ctl in WinGetControls("ahk_id " hwnd) {
        if InStr(ctl, "EDIT")
            editCtl := ctl
        else if (InStr(ctl, "BUTTON") && ControlGetText(ctl, "ahk_id " hwnd) = "OK")
            okBtn := ctl
    }
    Check(label ": it has a field and an OK button", (editCtl != "" && okBtn != "") ? 1 : 0, 1)
    if (editCtl = "" || okBtn = "") {
        try WinClose "ahk_id " hwnd
        return
    }
    ControlSetText secret, editCtl, "ahk_id " hwnd
    Sleep 150
    ControlClick okBtn, "ahk_id " hwnd
    WinWaitClose "ahk_id " hwnd, , 5
    Sleep 500
    got := ""
    try got := RTrim(FileRead(result, "UTF-8"), "`r`n")
    Check(label ": it hands back exactly what was typed", got = secret ? 1 : 0, 1)
    try FileDelete result
}
MonitorGet 1, &L1, &T1, &R1, &B1
Scenario("main", L1 + (R1 - L1) // 3, T1 + (B1 - T1) // 3, "hunter2-ñ€")
if (MonitorGetCount() >= 2) {
    MonitorGet 2, &L2, &T2, &R2, &B2
    Scenario("second", L2 + (R2 - L2) // 2, T2 + (B2 - T2) // 3, 'a "b" $c')
}
DllCall("SetCursorPos", "Int", L1 + (R1 - L1) // 2, "Int", T1 + (B1 - T1) // 2)
FileAppend out, A_Temp "\perf\askpass-test.txt"
ExitApp fails ? 1 : 0
