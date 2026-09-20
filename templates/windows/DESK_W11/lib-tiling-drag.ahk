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
    Dbg(Format("tiling {1} {2} hwnd {3} id {4}", mode, WinGetProcessName("ahk_id " hwnd), hwnd, id))
    btn := mode = "move" ? "LButton" : "RButton"
    left := (mx - wx) < (ww / 2), top := (my - wy) < (wh / 2)
    altDragGhost := ghost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")
    ghost.BackColor := "c4a7e7"
    WinSetTransparent 90, ghost
    while GetKeyState(btn, "P") {
        MouseGetPos &cx, &cy
        dx := cx - mx, dy := cy - my
        if (mode = "move")
            ghost.Show("NA x" (wx + dx) " y" (wy + dy) " w" ww " h" wh)
        else {
            nx := left ? wx + dx : wx, ny := top ? wy + dy : wy
            nw := left ? ww - dx : ww + dx, nh := top ? wh - dy : wh + dy
            if (nw > 100 && nh > 60)
                ghost.Show("NA x" nx " y" ny " w" nw " h" nh)
        }
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

; What a drop means for the layout, as a plain function of the gesture: the
; dominant direction for a move, and how far the grabbed edge travelled for a
; resize (dragging the left edge to the left makes the window wider). Empty
; when the gesture was too small to mean anything.
TilingDropCommand(mode, dx, dy, left, top) {
    if (mode = "move") {
        if (Abs(dx) < 40 && Abs(dy) < 40)
            return ""
        return "move --direction "
            . (Abs(dx) > Abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up"))
    }
    dw := left ? -dx : dx, dh := top ? -dy : dy
    args := ""
    if (Abs(dw) > 10)
        args .= " --width " dw "px"
    if (Abs(dh) > 10)
        args .= " --height " dh "px"
    return args = "" ? "" : "resize" args
}

