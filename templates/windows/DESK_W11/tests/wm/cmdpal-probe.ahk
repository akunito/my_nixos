#Requires AutoHotkey v2.0
#SingleInstance Force
; What does the Command Palette actually list? Opens it, types a query, and
; leaves a screenshot in %TEMP%\perf so a "this app does not show up" report can
; be checked instead of guessed. Never types unless the palette really opened:
; the keystrokes would otherwise land in whatever window has the focus.
;   AutoHotkey64.exe cmdpal-probe.ahk vesktop
query := A_Args.Length ? A_Args[1] : "vesktop"
out := A_Temp "\perf\cmdpal-" query ".png"
logFile := A_Temp "\perf\cmdpal-probe.txt"
try FileDelete(logFile)

; Launch it by its package id: the process runs in the tray all the time, so
; waiting for "a window of that process" proves nothing, and the hotkey does
; not always reach it from another script.
Run 'explorer.exe shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App'
pal := 0, deadline := A_TickCount + 8000
DetectHiddenWindows false
while (A_TickCount < deadline && !pal) {
    for hwnd in WinGetList("ahk_exe Microsoft.CmdPal.UI.exe") {
        WinGetPos(&px, &py, &pw, &ph, "ahk_id " hwnd)
        if (pw > 400 && ph > 200) {
            pal := hwnd
            break
        }
    }
    Sleep 200
}
if !pal {
    FileAppend "palette did not open`n", logFile
    ExitApp 1
}
WinGetPos(&px, &py, &pw, &ph, "ahk_id " pal)
FileAppend "palette at " px "," py " " pw "x" ph "`n", logFile
WinActivate "ahk_id " pal
Sleep 700
SendText query
Sleep 2000

; Screenshot of the whole virtual desktop: the palette can open on either
; monitor, and a primary-monitor grab showed an empty desktop.
vx := DllCall("GetSystemMetrics", "Int", 76), vy := DllCall("GetSystemMetrics", "Int", 77)
w := DllCall("GetSystemMetrics", "Int", 78), h := DllCall("GetSystemMetrics", "Int", 79)
hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
hbm := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbm)
DllCall("gdi32\BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h,
        "Ptr", hdcScreen, "Int", vx, "Int", vy, "UInt", 0x00CC0020)
pToken := 0, si := Buffer(24, 0), NumPut("UInt", 1, si)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)
pBitmap := 0
DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBitmap)
clsid := Buffer(16, 0)
DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)  ; PNG
DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", out, "Ptr", clsid, "Ptr", 0)
DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
DllCall("gdi32\DeleteObject", "Ptr", hbm), DllCall("gdi32\DeleteDC", "Ptr", hdcMem)
DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

Send "{Esc}"
FileAppend "saved " out "`n", logFile
ExitApp
