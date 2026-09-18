#Requires AutoHotkey v2.0
#SingleInstance Force
out := ""
loop MonitorGetCount() {
    MonitorGet(A_Index, &l, &t, &r, &b)
    out .= "monitor " A_Index " [" l "," t " " (r-l) "x" (b-t) "]`n"
    DetectHiddenWindows false
    for hwnd in WinGetList() {
        try {
            exe := WinGetProcessName("ahk_id " hwnd)
            if (exe = "zebar.exe" || exe = "explorer.exe")
                continue
            if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
                continue
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                continue
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if (cloaked)
                continue
            WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
            if (wx <= l && wy <= t && wx + ww >= r && wy + wh >= b)
                out .= "   covered by " exe " '" SubStr(WinGetTitle("ahk_id " hwnd), 1, 30) "' [" wx "," wy " " ww "x" wh "]`n"
        }
    }
}
try FileDelete(A_Temp "\perf\covering-ahk.txt")
FileAppend(out, A_Temp "\perf\covering-ahk.txt")
ExitApp
