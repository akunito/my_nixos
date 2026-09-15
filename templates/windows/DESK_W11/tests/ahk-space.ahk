#Requires AutoHotkey v2.0
CoordMode "Mouse", "Screen"
out := "A_ScreenDPI=" A_ScreenDPI " monitors=" MonitorGetCount() "`n"
Loop MonitorGetCount() {
    MonitorGet A_Index, &l, &t, &r, &b
    MonitorGetWorkArea A_Index, &wl, &wt, &wr, &wb
    out .= "monitor " A_Index ": " l "," t " - " r "," b " (work " wl "," wt " - " wr "," wb ")`n"
}
MouseMove 4700, 300, 0
Sleep 100
MouseGetPos &mx, &my
out .= "mouse asked 4700,300 -> reads " mx "," my "`n"
MouseMove 3850, 300, 0
Sleep 100
MouseGetPos &mx, &my
out .= "mouse asked 3850,300 -> reads " mx "," my "`n"
disc := WinExist("ahk_exe Discord.exe")
WinGetPos &wx, &wy, &ww, &wh, "ahk_id " disc
MonitorGet 2, &l2, &t2
tx := l2 + 40, ty := t2 + 60
WinMove tx, ty, , , "ahk_id " disc
Loop 60 {
    Sleep 5
    WinGetPos , , &nw, &nh, "ahk_id " disc
    if (nw != ww || nh != wh)
        break
}
Sleep 15
WinMove , , ww, wh, "ahk_id " disc
Sleep 400
WinGetPos &fx, &fy, &fw, &fh, "ahk_id " disc
out .= "jump to monitor2 origin+40,60 = " tx "," ty " -> " fx "," fy " " fw "x" fh ((fx = tx && fy = ty) ? "  EXACT" : "  OFF") "`n"
WinMove wx, wy, , , "ahk_id " disc
Sleep 300
WinMove , , ww, wh, "ahk_id " disc
FileAppend out, A_Temp "\ahk-space.txt", "UTF-8"
