#Requires AutoHotkey v2.0
CoordMode "Mouse", "Screen"
disc := WinExist("ahk_exe Discord.exe")
MonitorGetWorkArea 1, &al, &at, &ar, &ab
Poison() {
    global disc
    WinMove 1900, 300, 1667, 8946, "ahk_id " disc
    Sleep 400
    WinMaximize "ahk_id " disc
    Sleep 400
}
Prep(&mx, &my, &fx, &fy) {
    global disc
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " disc
    mx := wx + Round(ww * 0.5), my := wy + 20
    MouseMove mx, my, 0
    fx := (mx - wx) / ww, fy := (my - wy) / wh
}
WaitStable() {
    global disc
    lw := -1, lh := -1, stable := 0
    Loop 80 {
        Sleep 5
        WinGetPos , , &rw, &rh, "ahk_id " disc
        if (WinGetMinMax("ahk_id " disc) = 0 && rw = lw && rh = lh) {
            if (++stable >= 3)
                return
        } else
            stable := 0
        lw := rw, lh := rh
    }
}
Run(label, variant) {
    global disc, al, at, ar, ab
    Poison()
    Prep(&mx, &my, &fx, &fy)
    nw := Round((ar - al) * 0.8), nh := Round((ab - at) * 0.8)
    t0 := A_TickCount
    WinRestore "ahk_id " disc
    WaitStable()
    tx := Round(mx - fx * nw), ty := Round(my - fy * nh)
    if (ty < at)
        ty := at
    if (variant = 1) {
        WinMove tx, ty, nw, nh, "ahk_id " disc
    } else if (variant = 2) {
        WinMove , , nw, nh, "ahk_id " disc
        Sleep 100
        WinMove tx, ty, , , "ahk_id " disc
    } else {
        WinMove , , nw, nh, "ahk_id " disc
        WaitStable()
        WinMove tx, ty, , , "ahk_id " disc
        WaitStable()
        WinGetPos , , &cw, &ch, "ahk_id " disc
        if (cw != nw || ch != nh)
            WinMove , , nw, nh, "ahk_id " disc
    }
    dt := A_TickCount - t0
    Sleep 700
    WinGetPos &x, &y, &w, &h, "ahk_id " disc
    return label ": target " tx "," ty " " nw "x" nh " -> " x "," y " " w "x" h " (" dt " ms)" ((w = nw && h = nh) ? "  OK" : "  DRIFT") "`n"
}
out := ""
Loop 2 {
    out .= Run("V1 one call        #" A_Index, 1)
    out .= Run("V2 size,100ms,pos  #" A_Index, 2)
    out .= Run("V3 size,stable,pos,verify #" A_Index, 3)
}
WinMove 1900, 300, 1406, 1171, "ahk_id " disc
FileAppend out, A_Temp "\heal-variants.txt", "UTF-8"
