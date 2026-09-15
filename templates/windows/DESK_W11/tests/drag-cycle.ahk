#Requires AutoHotkey v2.0
; Replays the cross-monitor part of AltDrag exactly as in hyper-desktops.ahk and times it.
disc := WinExist("ahk_exe Discord.exe")
WinGetPos &wx, &wy, &ww, &wh, "ahk_id " disc
out := "start " wx "," wy " " ww "x" wh "`n"
Loop 3 {
    t0 := A_TickCount
    WinMove 4300, 200, , , "ahk_id " disc
    Loop 60 {
        Sleep 5
        WinGetPos , , &nw, &nh, "ahk_id " disc
        if (nw != ww || nh != wh)
            break
    }
    Sleep 15
    WinMove , , ww, wh, "ahk_id " disc
    t1 := A_TickCount - t0
    Sleep 500
    WinGetPos &x, &y, &w, &h, "ahk_id " disc
    out .= "to mon2: routine " t1 " ms; 500 ms later " x "," y " " w "x" h (w = ww && h = wh ? "  OK" : "  DRIFT") "`n"
    t0 := A_TickCount
    WinMove wx, wy, , , "ahk_id " disc
    Loop 60 {
        Sleep 5
        WinGetPos , , &nw, &nh, "ahk_id " disc
        if (nw != ww || nh != wh)
            break
    }
    Sleep 15
    WinMove , , ww, wh, "ahk_id " disc
    t1 := A_TickCount - t0
    Sleep 500
    WinGetPos &x, &y, &w, &h, "ahk_id " disc
    out .= "back:    routine " t1 " ms; 500 ms later " x "," y " " w "x" h (w = ww && h = wh ? "  OK" : "  DRIFT") "`n"
}
FileAppend out, A_Temp "\drag-cycle.txt", "UTF-8"
