#Requires AutoHotkey v2.0
disc := WinExist("ahk_exe Discord.exe")
WinGetPos &wx, &wy, &ww, &wh, "ahk_id " disc
out := "start " wx "," wy " " ww "x" wh "`n"
Simulate(label, x0, x1, y) {
    global ww, wh, disc
    changes := 0, lastw := ww, lasth := wh, t0 := A_TickCount, slow := 0, sizes := ""
    Loop 60 {
        x := x0 + (x1 - x0) * A_Index // 60
        ts := A_TickCount
        WinMove x, y, , , "ahk_id " disc          ; position only, NO size fixes in the loop
        if (A_TickCount - ts > 30)
            slow++
        Sleep 8
        WinGetPos , , &nw, &nh, "ahk_id " disc
        if (nw != lastw || nh != lasth) {
            changes++, lastw := nw, lasth := nh, sizes .= " " nw "x" nh
        }
    }
    tloop := A_TickCount - t0
    WinMove , , ww, wh, "ahk_id " disc              ; one restore at "release"
    Sleep 400
    WinGetPos &fx, &fy, &fw, &fh, "ahk_id " disc
    return label ": loop " tloop " ms, slow moves=" slow ", size changes=" changes " [" sizes " ], final " fw "x" fh (fw = ww && fh = wh ? "  OK" : "  DRIFT") "`n"
}
Loop 3 {
    out .= Simulate("run " A_Index " mon1->mon2", wx, 4300, 200)
    out .= Simulate("run " A_Index " mon2->mon1", 4300, wx, wy)
}
FileAppend out, A_Temp "\live-cross2.txt", "UTF-8"
