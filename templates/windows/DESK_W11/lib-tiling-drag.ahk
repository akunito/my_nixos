; Alt+drag on a TILED window (AutoHotkey v2). Needs lib-glaze.ahk.
;
; GlazeWM turns a tiling window that something repositions into a floating one,
; so the old free-form drag cost a tiled window its place in the layout and its
; size on the first pixel of movement. Here the real window is never touched:
; an outline follows the cursor and, on release, GlazeWM is asked to move the
; container one step in the direction of the drag or to resize it by how far
; the grabbed edge travelled -- what the same gesture does in sway.
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\lib-glaze.ahk

TilingDrag(mode, hwnd, id, mx, my, wx, wy, ww, wh) {
    global altDragGhost, altDragPhase, altDragExp
    altDragPhase := "drag", altDragExp := "(tiling " mode ")"
    Dbg(Format("tiling {1} {2} hwnd {3} id {4}", mode, ExeOf(hwnd), hwnd, id))
    btn := mode = "move" ? "LButton" : "RButton"
    left := (mx - wx) < (ww / 2), top := (my - wy) < (wh / 2)
    altDragGhost := ghost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")
    ghost.BackColor := "c4a7e7"
    WinSetTransparent 90, ghost

    if (mode = "move") {
        ; The real window never moves: it is still in its tile, and the layout
        ; it came from does not close the gap until the drop, so a drag thought
        ; better of leaves the desk exactly as it was. What follows the cursor
        ; is the rectangle the window would TAKE -- the half of the tile under
        ; the pointer -- which the window manager works out, because that is
        ; where the rule lives and where the drop will be decided again.
        asked := 0, lastX := -99999, lastY := -99999, shown := ""
        while GetKeyState(btn, "P") {
            MouseGetPos &cx, &cy
            ; Not on every tick. 60 ms and 8 px is under anyone's notice and an
            ; order of magnitude fewer round trips than the 8 ms loop.
            if (A_TickCount - asked > 60 && (Abs(cx - lastX) > 8 || Abs(cy - lastY) > 8)) {
                asked := A_TickCount, lastX := cx, lastY := cy
                r := TilingDropTarget(id, cx, cy)
                if (r && r != shown) {
                    p := StrSplit(r, ",")
                    ghost.Show("NA x" p[1] " y" p[2] " w" p[3] " h" p[4])
                    shown := r
                }
            }
            Sleep 8
        }
        altDragPhase := "release"
        try ghost.Destroy()
        altDragGhost := ""
        MouseGetPos &cx, &cy
        ; Dropped against the top edge of the screen. AkuWM owns what that
        ; means (layout.drag_to_top), so this only reports the gesture.
        if TouchesTopEdge(cx, cy) {
            Dbg(Format("tiling move -> drag-to-top at {1},{2}", cx, cy))
            GlazeOn(id, "drag-to-top")
            return
        }
        Dbg(Format("tiling move -> drag-tile at {1},{2}", cx, cy))
        GlazeOn(id, "drag-tile --x " cx " --y " cy)
        return
    }

    while GetKeyState(btn, "P") {
        MouseGetPos &cx, &cy
        dx := cx - mx, dy := cy - my
        nx := left ? wx + dx : wx, ny := top ? wy + dy : wy
        nw := left ? ww - dx : ww + dx, nh := top ? wh - dy : wh + dy
        if (nw > 100 && nh > 60)
            ghost.Show("NA x" nx " y" ny " w" nw " h" nh)
        Sleep 8
    }
    altDragPhase := "release"
    try ghost.Destroy()
    altDragGhost := ""
    MouseGetPos &cx, &cy
    dx := cx - mx, dy := cy - my
    cmd := TilingDropCommand(mode, dx, dy, left, top)
    if (cmd = "") {
        Dbg(Format("tiling {1}: too short ({2},{3}), left alone", mode, dx, dy))
        return
    }
    Dbg(Format("tiling {1} -> {2} ({3},{4})", mode, cmd, dx, dy))
    GlazeOn(id, cmd)
}

; The rectangle a drop at this point would produce, as "x,y,w,h". Empty when
; the manager says the point means nothing -- the gap between two tiles, or the
; window's own tile.
TilingDropTarget(id, x, y) {
    j := GlazeQuery("drop-target --id " id " --x " x " --y " y)
    if !RegExMatch(j, '"dropTarget"\s*:\s*\{\s*"x"\s*:\s*(-?\d+)\s*,\s*"y"\s*:\s*(-?\d+)\s*,\s*"width"\s*:\s*(\d+)\s*,\s*"height"\s*:\s*(\d+)', &m)
        return ""
    return m[1] "," m[2] "," m[3] "," m[4]
}

; How far the grabbed edge travelled, for a RESIZE: dragging the left edge to
; the left makes the window wider. Empty when the gesture was too small to mean
; anything.
;
; A move used to come through here too, as the dominant direction of the drag
; -- one step in the layout, never looking at what was under the cursor. It
; goes to the window manager as a point now (2026-09-21), which is the same
; rule on its own monitor and on any other.
TilingDropCommand(mode, dx, dy, left, top) {
    dw := left ? -dx : dx, dh := top ? -dy : dy
    args := ""
    if (Abs(dw) > 10)
        args .= " --width " dw "px"
    if (Abs(dh) > 10)
        args .= " --height " dh "px"
    return args = "" ? "" : "resize" args
}


; The top edge of whatever screen the cursor is on. A band rather than the
; exact row: a pointer flung upwards stops a pixel or two short, and the
; monitors here start at different y (the vertical one at -408).
TouchesTopEdge(x, y, band := 10) {
    mon := MonitorAt(x, y)
    return y - mon.t <= band
}
