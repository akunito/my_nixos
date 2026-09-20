; Putting the desktop back together after a monitor went away (AutoHotkey v2).
;
; What breaks, measured on this machine: a monitor sleeps, GlazeWM moves its
; workspaces onto the survivor, and when it comes back only the workspaces
; bound to the *new* monitor return -- so every sleep cycle mixes them further
; (ws 21 on the main monitor, ws 11 on the vertical one, and Hyper+W jumping
; from 12 to 17). Meanwhile Windows hands per-monitor-DPI apps a restore
; rectangle the size of their title bar (Telegram: 219x30).
;
; The repair is the other half of lib-layout-journal.ahk: workspaces go back to
; the monitor their number says, and windows get the geometry the journal saw
; them with ON THAT MONITOR.
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\lib-layout-journal.ahk

; Workspace 1x belongs to the main monitor, 2x to the vertical one -- the same
; convention as the GlazeWM config's `bind_to_monitor`.
RepairGroupDevice(group) {
    primary := MonitorGetPrimary()
    Loop MonitorGetCount() {
        isPrimary := (A_Index = primary)
        if ((group = 1) = isPrimary)
            return MonitorGetName(A_Index)
    }
    return MonitorGetName(primary)
}

; Move every workspace that sits on the wrong monitor back. `move-workspace`
; only knows directions, so the direction is taken from where the monitors are.
RepairWorkspaces() {
    moved := 0
    for mon in GlazeMonitors() {
        if (mon["device"] = "")
            continue
        for wsEntry in mon["wss"] {
            group := SubStr(wsEntry["name"], 1, 1) = "2" ? 2 : 1
            want := RepairGroupDevice(group)
            if (want = "" || want = mon["device"])
                continue
            dir := MonitorDeviceIsLeftOf(want, mon["device"]) ? "left" : "right"
            Dbg("repair: workspace " wsEntry["name"] " is on " mon["device"] ", moving " dir " to " want)
            id := GlazeWsId(wsEntry["name"])
            if (id != "") {
                GlazeOn(id, "move-workspace --direction " dir)
                moved++
                Sleep 400
            }
        }
    }
    return moved
}
MonitorDeviceIsLeftOf(a, b) {
    ia := MonitorIndexOfDevice(a), ib := MonitorIndexOfDevice(b)
    if (!ia || !ib)
        return false
    MonitorGet(ia, &al), MonitorGet(ib, &bl)
    return al < bl
}
; A workspace's container id, for `--id`.
GlazeWsId(name) {
    j := GlazeQuery("workspaces"), pos := 1
    while pos := RegExMatch(j, '"type":"workspace","id":"([^"]+)","name":"([^"]+)"', &m, pos) {
        if (m[2] = name)
            return m[1]
        pos += StrLen(m[0])
    }
    return ""
}

; Give a window a rectangle. A tiling window has no rectangle of its own --
; the layout decides it -- so only its workspace is restored, and GlazeWM
; redraws the rest.
RepairPlaceWindow(w, place) {
    if (w["state"] = "tiling")
        return false
    ; `position` + `size`, not `set-floating --x-pos ...`: the state commands
    ; return early when the window is already in that state, so a floating
    ; window simply ignored them (measured -- the "damage" of the test never
    ; even happened).
    GlazeOn(w["id"], Format("position --x-pos {1} --y-pos {2}", place["x"], place["y"]))
    Sleep 150
    GlazeOn(w["id"], Format("size --width {1}px --height {2}px", place["w"], place["h"]))
    Sleep 250
    return true
}

; The repair itself.
;   full = false  only what is broken, plus windows that ended up on another
;                 monitor than the journal remembers
;   full = true   also re-apply the recorded geometry to healthy windows
RepairLayout(full := false) {
    t0 := A_TickCount
    entries := JournalRead()
    fixed := 0, notes := []
    moved := RepairWorkspaces()
    if moved
        Sleep 800

    for w in GlazeWins() {
        if (w["state"] = "minimized" || w["display"] != "shown")
            continue
        try {
            WinGetPos(&x, &y, &ww, &wh, "ahk_id " w["hwnd"])
        } catch
            continue
        key := JournalKey(w["proc"], w["class"])
        broken := JournalIsBroken(x, y, ww, wh)
        ; Where does the journal say this window lives?
        homeDevice := ""
        if entries.Has(key) {
            newest := 0
            for d, r in entries[key]
                if (!newest || r["stamp"] > newest["stamp"])
                    newest := r, homeDevice := d
        }
        ; A broken window has no meaningful monitor of its own (Windows parks
        ; it at -32000, or leaves it the size of its title bar), so it goes
        ; home; only when nothing was ever recorded does the pointer decide.
        device := broken
            ? (homeDevice != "" ? homeDevice : CursorDevice())
            : MonitorDeviceAt(x + ww // 2, y + wh // 2)
        if (device = "")
            device := CursorDevice()
        wandered := (homeDevice != "" && homeDevice != device && !broken)
        if (!broken && !wandered && !full)
            continue
        target := wandered ? homeDevice : device
        place := JournalPlacement(entries, key, target)
        if (!place && broken)
            place := JournalDefaultPlacement(target)
        if !place
            continue
        why := broken ? "broken " ww "x" wh : (wandered ? "wandered from " homeDevice : "full pass")
        notes.Push(w["proc"] " (" why ") -> " target " " place["x"] "," place["y"] " " place["w"] "x" place["h"]
            . (place["exact"] ? "" : " (scaled)"))
        if RepairPlaceWindow(w, place)
            fixed++
    }
    Glaze("wm-redraw")                  ; tiled windows get their sizes back
    for note in notes
        Dbg("repair: " note)
    Dbg(Format("repair: {1} workspace(s) moved, {2} window(s) placed, {3} ms", moved, fixed, A_TickCount - t0))
    return Map("workspaces", moved, "windows", fixed, "notes", notes)
}
