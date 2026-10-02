#Requires AutoHotkey v2.0
#SingleInstance Force
; A light-dismiss popup -- the "Open with" dialog (OpenWith.exe, class "Open
; With": WS_POPUP, topmost, tool window, no owner) -- closes the moment it is
; deactivated, and Windows' native focus-follows-mouse activated whatever the
; pointer crossed on the way to it: the dialog was gone before the pointer
; arrived (2026-10-02). The daemon pauses the native tracking while such a
; popup has the foreground and resumes it when the foreground moves on.
; Run: AutoHotkey64.exe openwith-test.ahk -> %TEMP%\perf\openwith-test.txt
SendLevel 1
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
; AutoHotkey's WinExist/WinGetList do not enumerate this dialog (visible,
; foreground, class "Open With" -- and absent from the list, 2026-10-02), so
; it is found as the ACTIVE window and watched through IsWindow directly.
Alive(hwnd) => hwnd && DllCall("IsWindow", "Ptr", hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd)
OpenWithInFront() {
    fg := WinExist("A")
    if !fg
        return 0
    try return WinGetClass("ahk_id " fg) = "Open With" ? fg : 0
    return 0
}
Tracking() {
    buf := Buffer(4, 0)
    DllCall("SystemParametersInfo", "UInt", 0x1000, "UInt", 0, "Ptr", buf, "UInt", 0)
    return NumGet(buf, 0, "Int") ? 1 : 0
}
Check("0 setup: native focus-follows-mouse is on", Tracking(), 1)
; a window to cross: Notepad on the main monitor, left side
Run "notepad.exe"
if !WinWait("ahk_exe notepad.exe", , 8) {
    out .= "FAIL 0 setup: notepad did not open`n"
    FileAppend out, A_Temp "\perf\openwith-test.txt"
    ExitApp 1
}
np := WinExist("ahk_exe notepad.exe")
Sleep 1200
; 1. the dialog opens (on the main monitor, where the pointer is)
MouseMove 1900, 1000, 0
Sleep 300
; An unassociated extension: Windows answers with "How do you want to open
; this file?", the same OpenWith.exe dialog Diego met opening an image.
; (rundll32 OpenAs_RunDLL showed it once and then never again, 2026-10-02.)
probe := A_Temp "\openwith-probe." A_TickCount ".akuwmtest"
FileAppend "probe", probe
try Run(probe)
; Watch it come and (maybe) go: a dialog that dies within a second says
; something moved the pointer; where the pointer was at that moment says who.
dlg := 0, seenAt := 0, goneAt := 0, goneOver := ""
t0 := A_TickCount
Loop 160 {
    Sleep 50
    if (!dlg) {
        dlg := OpenWithInFront()
        if dlg
            seenAt := A_TickCount - t0
    } else if !Alive(dlg) {
        goneAt := A_TickCount - t0
        MouseGetPos &gx, &gy, &gunder
        goneOver := Format("{1},{2} over {3}", gx, gy, gunder ? WinGetProcessName("ahk_id " gunder) : "nothing")
        break
    } else if (A_TickCount - t0 > 2500) {
        break
    }
}
out .= Format("     dialog seen after {1} ms{2}; test pointer was left at 1900,1000`n", seenAt, goneAt ? Format(", GONE at {1} ms with the pointer at {2}", goneAt, goneOver) : ", still there")
if !dlg {
    DetectHiddenWindows true
    n := WinGetList("ahk_exe OpenWith.exe").Length
    DetectHiddenWindows false
    fg := WinExist("A")
    out .= Format("     (no dialog: OpenWith.exe windows incl. hidden={1}; foreground={2} [{3}] '{4}'; probe file exists={5})`n", n, fg ? WinGetProcessName("ahk_id " fg) : "-", fg ? WinGetClass("ahk_id " fg) : "-", fg ? WinGetTitle("ahk_id " fg) : "-", FileExist(probe) ? 1 : 0)
}
Check("1 the Open-with dialog opened", dlg ? 1 : 0, 1)
Check("1 and stayed while nothing moved", (dlg && !goneAt) ? 1 : 0, 1)
if goneAt
    dlg := 0
if dlg {
    Sleep 800
    Check("1 it has the foreground", WinActive("ahk_id " dlg) ? 1 : 0, 1)
    Check("1 native tracking is paused while it is in front", Tracking(), 0)
    WinGetPos &x, &y, &w, &h, "ahk_id " dlg
    ; 2. the pointer parks over Notepad (another window), then walks to the dialog
    WinGetPos &nx, &ny, &nw, &nh, "ahk_id " np
    MouseMove nx + nw // 2, ny + nh // 2, 0
    ; Windows' tracking acts on MOVEMENT over the window, so a hand that
    ; rests there still trembles: a few pixels back and forth.
    Loop 4 {
        MouseMove nx + nw // 2 + (A_Index & 1 ? 6 : -6), ny + nh // 2 + (A_Index & 2 ? 6 : -6), 0
        Sleep 120
    }
    Sleep 500
    Check("2 parked over another window: the dialog is still there", Alive(dlg) ? 1 : 0, 1)
    Check("2 and still has the foreground", WinActive("ahk_id " dlg) ? 1 : 0, 1)
    cx := x + w // 2, cy := y + h // 2
    Loop 30 {
        MouseMove nx + nw // 2 + (cx - nx - nw // 2) * A_Index // 30, ny + nh // 2 + (cy - ny - nh // 2) * A_Index // 30, 0
        Sleep 30
    }
    Sleep 500
    Check("2 reached: the dialog is still there", Alive(dlg) ? 1 : 0, 1)
    ; 3. a click elsewhere dismisses it, as Windows means it to, and tracking comes back
    MouseMove nx + nw // 2, ny + nh // 2, 0
    Sleep 200
    Click
    Sleep 1200
    Check("3 a click elsewhere dismisses it", Alive(dlg) ? 1 : 0, 0)
    Check("3 native tracking is back on", Tracking(), 1)
    if Alive(dlg)
        try WinClose "ahk_id " dlg
}
try WinClose "ahk_id " np
try FileDelete probe
Sleep 300
try RunWait(A_ComSpec ' /c taskkill /F /IM notepad.exe', , "Hide")
FileAppend out, A_Temp "\perf\openwith-test.txt"
ExitApp fails ? 1 : 0
