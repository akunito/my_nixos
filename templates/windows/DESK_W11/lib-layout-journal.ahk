; The layout journal: where each window lives and how big it is ON EACH
; MONITOR (AutoHotkey v2).
;
; A monitor that goes to sleep takes its workspaces and windows with it, and
; what comes back is not what left: sizes between monitors cannot be
; extrapolated (150% vs 125% here, 3840x2160 vs 1440x2560), and Windows itself
; hands apps back a restore rectangle the size of their title bar -- Telegram
; came back as 219x30 twice this week. So the geometry each window had on each
; monitor is written down while things are healthy, and the repair puts it back
; from that record instead of guessing.
;
;   journal   %LOCALAPPDATA%\akuwm\layout.tsv, one line per window and monitor
;   snapshot  every minute, and before the machine suspends
;   repair    automatic after a display change, or Hyper+F5 for a full pass
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\lib-glaze.ahk
#Include %A_LineFile%\..\lib-workspaces.ahk

global JournalFile := EnvGet("LOCALAPPDATA") "\akuwm\layout.tsv"

; A window is "broken" when it is too small to be a real window, or when
; almost none of it is on a screen. Telegram's title-bar-sized 219x30 and a
; window parked at -32000 are both this.
global JournalMinW := 300, JournalMinH := 200

; --- the file ---------------------------------------------------------------
; key \t device \t ws \t state \t sticky \t x \t y \t w \t h \t areaL \t areaT \t areaW \t areaH \t stamp
; The work area is stored with the geometry: without it a record cannot be
; scaled onto a monitor it was never seen on.
JournalRead() {
    global JournalFile
    out := Map()
    if !FileExist(JournalFile)
        return out
    for line in StrSplit(FileRead(JournalFile, "UTF-8"), "`n", "`r") {
        f := StrSplit(line, "`t")
        if (f.Length < 14)
            continue
        key := f[1], device := f[2]
        if !out.Has(key)
            out[key] := Map()
        out[key][device] := Map("ws", f[3], "state", f[4], "sticky", f[5] = "1",
            "x", f[6] + 0, "y", f[7] + 0, "w", f[8] + 0, "h", f[9] + 0,
            "areaL", f[10] + 0, "areaT", f[11] + 0, "areaW", f[12] + 0,
            "areaH", f[13] + 0, "stamp", f[14])
    }
    return out
}

JournalWrite(entries) {
    global JournalFile
    dir := RegExReplace(JournalFile, "\\[^\\]+$")
    if !DirExist(dir)
        DirCreate(dir)
    text := ""
    for key, byDevice in entries
        for device, r in byDevice
            text .= key "`t" device "`t" r["ws"] "`t" r["state"] "`t" (r["sticky"] ? 1 : 0)
                . "`t" r["x"] "`t" r["y"] "`t" r["w"] "`t" r["h"]
                . "`t" r["areaL"] "`t" r["areaT"] "`t" r["areaW"] "`t" r["areaH"]
                . "`t" r["stamp"] "`n"
    tmp := JournalFile ".tmp"
    try {
        if FileExist(tmp)
            FileDelete(tmp)
        FileAppend(text, tmp, "UTF-8")
        if FileExist(JournalFile)
            FileDelete(JournalFile)
        FileMove(tmp, JournalFile)
    }
}

; Windows of the same app are told apart by their class; the handle changes
; every run, so it can never be the key.
JournalKey(proc, cls) => StrLower(proc) "|" cls

; --- monitors ---------------------------------------------------------------
MonitorIndexOfDevice(device) {
    Loop MonitorGetCount() {
        if (MonitorGetName(A_Index) = device)
            return A_Index
    }
    return 0
}
MonitorWorkArea(device, &l, &t, &r, &b) {
    i := MonitorIndexOfDevice(device)
    if !i
        return false
    MonitorGetWorkArea(i, &l, &t, &r, &b)
    return true
}
; How much of a window is on a screen, as a fraction of its own area.
WindowOnScreenFraction(x, y, w, h) {
    if (w <= 0 || h <= 0)
        return 0
    best := 0
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        ox := Max(0, Min(x + w, r) - Max(x, l))
        oy := Max(0, Min(y + h, b) - Max(y, t))
        best := Max(best, (ox * oy) / (w * h))
    }
    return best
}
; Off the screen is broken for anybody. Being small is only broken when the
; window is known to have been much bigger -- some windows are just small, and
; resizing a calculator to 60% of the screen is not a repair.
JournalIsBroken(x, y, w, h, wasBigger := true) {
    global JournalMinW, JournalMinH
    if (WindowOnScreenFraction(x, y, w, h) < 0.1)
        return true
    return wasBigger && (w < JournalMinW || h < JournalMinH)
}

; --- taking a snapshot ------------------------------------------------------
; Only while the desktop is healthy: recording a layout with a monitor missing
; would memorise exactly the damage the repair is supposed to undo.
JournalSnapshot(force := false) {
    entries := JournalRead()
    known := Map()
    for key, byDevice in entries
        for device, r in byDevice
            known[device] := true
    if (!force && known.Count > MonitorGetCount()) {
        Dbg("journal: skipped, " MonitorGetCount() " monitor(s) and the journal knows " known.Count)
        return false
    }
    saved := 0
    for w in GlazeWins() {
        if (w["state"] = "minimized" || w["display"] != "shown")
            continue
        try {
            WinGetPos(&x, &y, &ww, &wh, "ahk_id " w["hwnd"])
        } catch
            continue
        device := MonitorDeviceAt(x + ww // 2, y + wh // 2)
        if (device = "" || !MonitorWorkArea(device, &al, &at, &ar, &ab))
            continue
        key := JournalKey(w["proc"], w["class"])
        ; Known to have been much bigger on this monitor? Then this size is
        ; damage, not news, and the record is left alone. A window that was
        ; always small is recorded as it is.
        known := (entries.Has(key) && entries[key].Has(device)) ? entries[key][device] : 0
        wasBigger := known && (known["w"] > ww * 1.5 || known["h"] > wh * 1.5)
        if JournalIsBroken(x, y, ww, wh, wasBigger)
            continue
        if !entries.Has(key)
            entries[key] := Map()
        entries[key][device] := Map("ws", w["ws"], "state", w["state"],
            "sticky", w["sticky"], "x", x, "y", y, "w", ww, "h", wh,
            "areaL", al, "areaT", at, "areaW", ar - al, "areaH", ab - at,
            "stamp", A_Now)
        saved++
    }
    JournalWrite(entries)
    Dbg("journal: " saved " window(s) recorded")
    return true
}

; --- reading a record back --------------------------------------------------
; The record for this monitor if there is one; otherwise the newest record from
; another monitor, scaled by work area -- a window that filled 60% of the width
; there should fill 60% here, because the pixels do not carry over.
JournalPlacement(entries, key, device) {
    if (!entries.Has(key) || !MonitorWorkArea(device, &al, &at, &ar, &ab))
        return 0
    byDevice := entries[key]
    if byDevice.Has(device) {
        r := byDevice[device]
        ; Only if the monitor still has the work area the record was written
        ; against. A record whose area no longer matches is from another screen
        ; in all but name -- a resolution change, or, on this desk, every row
        ; written before the scripts and the window manager shared one
        ; coordinate space (the vertical monitor was recorded 1.2x too big
        ; until 2026-09-21). Putting those pixels back verbatim is what sent a
        ; window to the other monitor or halfway between the two, so they go
        ; down the scaling path below instead, which is self-healing: the next
        ; snapshot records the window where it actually is.
        if (r["areaL"] = al && r["areaT"] = at
            && r["areaW"] = ar - al && r["areaH"] = ab - at)
            return Map("x", r["x"], "y", r["y"], "w", r["w"], "h", r["h"],
                "ws", r["ws"], "state", r["state"], "exact", true)
    }
    best := 0
    for other, r in byDevice
        if (!best || r["stamp"] > best["stamp"])
            best := r
    if (!best || best["areaW"] <= 0 || best["areaH"] <= 0)
        return 0
    aw := ar - al, ah := ab - at
    nw := Min(Round(best["w"] * aw / best["areaW"]), aw)
    nh := Min(Round(best["h"] * ah / best["areaH"]), ah)
    ; Keep the same relative spot, then pull it inside the work area.
    nx := al + Round((best["x"] - best["areaL"]) * aw / best["areaW"])
    ny := at + Round((best["y"] - best["areaT"]) * ah / best["areaH"])
    nx := Min(Max(nx, al), ar - nw), ny := Min(Max(ny, at), ab - nh)
    return Map("x", nx, "y", ny, "w", nw, "h", nh,
        "ws", best["ws"], "state", best["state"], "exact", false)
}

; Last resort when nothing was ever recorded: 60% of the work area, centred.
JournalDefaultPlacement(device) {
    if !MonitorWorkArea(device, &al, &at, &ar, &ab)
        return 0
    w := Round((ar - al) * 0.6), h := Round((ab - at) * 0.6)
    return Map("x", al + ((ar - al) - w) // 2, "y", at + ((ab - at) - h) // 2,
        "w", w, "h", h, "ws", "", "state", "floating", "exact", false)
}
