#Requires AutoHotkey v2.0
#SingleInstance Force
; A WSLg dialog -- the sudo askpass (zenity through msrdc, class RAIL_WINDOW)
; -- must show up small, whole, and on the monitor the pointer is on. AkuWM
; tiled it to the whole portrait monitor ("place msrdc -> 3840,-373
; 1440x2525") and Diego never saw the password box: a deploy waited on sudo
; for five minutes, three times (2026-10-02). Rule `msrdc -> center`.
; Run: AutoHotkey64.exe wslg-test.ahk -> %TEMP%\perf\wslg-test.txt
SendLevel 1
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
Zenity(title) {
    Run 'wsl.exe -d NixOS -- bash -lc "setsid -f zenity --password --title=' title ' < /dev/null > /dev/null 2>&1"', , "Hide"
}
KillZenity() {
    try RunWait('wsl.exe -d NixOS -- bash -lc "pkill -f [z]enity.*akuwm-wslg"', , "Hide")
    Sleep 800
}
Case(label, px, py) {
    global out
    title := "akuwm-wslg-" label
    MouseMove px, py, 0
    Sleep 300
    Zenity(title)
    SetTitleMatchMode 2
    hwnd := WinWait(title " ahk_class RAIL_WINDOW", , 10)
    Check(label ": the window appeared", hwnd ? 1 : 0, 1)
    if !hwnd
        return
    Sleep 2500   ; the daemon's placement, and WSLg following it
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    want := MonOf(px, py)
    MonitorGet want, &l, &t, &r, &b
    out .= Format("     {1}: window {2},{3} {4}x{5}; pointer monitor {6} [{7},{8} {9}x{10}]`n", label, x, y, w, h, want, l, t, r - l, b - t)
    Check(label ": it is small (its own size, not a tile)", (w <= 900 && h <= 700) ? 1 : 0, 1)
    Check(label ": it is whole on the monitor the pointer is on", (x >= l && y >= t && x + w <= r && y + h <= b) ? 1 : 0, 1)
    cx := x + w // 2, cy := y + h // 2
    Check(label ": and near its centre", (Abs(cx - (l + r) // 2) < 200 && Abs(cy - (t + b) // 2) < 200) ? 1 : 0, 1)
    KillZenity()
}
KillZenity()
MonitorGet 1, &L1, &T1, &R1, &B1
Case("main", L1 + (R1 - L1) // 3, T1 + (B1 - T1) // 3)
if (MonitorGetCount() >= 2) {
    MonitorGet 2, &L2, &T2, &R2, &B2
    Case("second", L2 + (R2 - L2) // 2, T2 + (B2 - T2) // 3)
}
MouseMove L1 + (R1 - L1) // 2, T1 + (B1 - T1) // 2, 0
FileAppend out, A_Temp "\perf\wslg-test.txt"
ExitApp fails ? 1 : 0
