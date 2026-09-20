; Shared GlazeWM CLI plumbing (hyper-desktops.ahk and tests/wm both include it).
; GlazeWM has no keybindings of its own here: every gesture shells out to
; `glazewm command ...`, and every decision is taken from `glazewm query ...`.
; ASCII only, no BOM: AHK reads a BOM-less file as ANSI.
#Requires AutoHotkey v2.0

global glazeExe := A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"

; ---- Debug trace (opt-in) -------------------------------------------------
; %TEMP%\hyper-debug.on present -> every gesture and every GlazeWM command is
; appended to %TEMP%\altdrag.log with timings.
Dbg(msg) {
    if !FileExist(A_Temp "\hyper-debug.on")
        return
    ; The running script and the test suites write this log at the same time.
    ; A sharing violation must never reach the user as an error dialog (it
    ; froze a suite until it timed out, 2026-09-20): retry, then give up.
    Loop 3 {
        try {
            FileAppend A_Now " " msg "`n", A_Temp "\altdrag.log"
            return
        }
        Sleep 40
    }
}

Glaze(args) {
    global glazeExe
    t := A_TickCount
    RunWait('"' glazeExe '" command ' args, , "Hide")
    Dbg(Format("glaze {1} ({2} ms)", args, A_TickCount - t))
}

; Same, but aimed at one container instead of whatever has the focus. Without
; --id every command acts on the focused container, which is why a plain
; `move --workspace N` never moved the window we meant.
GlazeOn(id, args) => Glaze('--id ' id ' ' args)

; Each call gets its own file: the suite and the running script query at the
; same time, and a shared name truncates one read while the other writes.
GlazeQuery(what) {
    global glazeExe
    static seq := 0
    t := A_TickCount
    ; Through a hidden cmd.exe, NOT WScript.Shell.Exec: Exec cannot hide the
    ; console it creates, so every query flashed a console window that took the
    ; focus -- which GlazeWM then followed, and the focus assertions of the
    ; suites started failing for no reason (measured 2026-09-20). The cost is
    ; the same; the win came from taking ONE query per gesture instead of three.
    tmp := A_Temp "\glazewm-query-" DllCall("GetCurrentProcessId") "-" (seq += 1) ".json"
    RunWait(A_ComSpec ' /c ""' glazeExe '" query ' what ' > "' tmp '""', , "Hide")
    j := ""
    try j := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)
    Dbg(Format("query {1} ({2} ms, {3} bytes)", what, A_TickCount - t, StrLen(j)))
    return j
}

; ---- Parsed views ---------------------------------------------------------
; Windows, each tagged with the workspace it lives in. Read from the
; `workspaces` query, not from `windows`: that one is a flat list whose
; parentId is the immediate parent, which for a tiled window is a split
; container, not the workspace.
; One query, everything a gesture needs: the windows (each tagged with its
; workspace) and which workspace is displayed on each monitor group. A query
; costs ~200 ms, so a gesture takes ONE and passes the result around.
GlazeSnapshot() {
    j := GlazeQuery("workspaces")
    return Map("wins", GlazeWinsFrom(j), "wss", GlazeWssFrom(j))
}

GlazeWins() => GlazeWinsFrom(GlazeQuery("workspaces"))
GlazeWss() => GlazeWssFrom(GlazeQuery("workspaces"))

GlazeWinsFrom(j) {
    out := [], wsName := "", pos := 1
    pat := '"type":"workspace","id":"[^"]+","name":"([^"]+)"'
    pat .= '|"type":"window","id":"([^"]+)","parentId":"([^"]+)","hasFocus":(true|false)'
    pat .= '.*?"state":\{"type":"([a-z]+)".*?"displayState":"([a-z]+)"'
    ; The sticky flag only exists in our fork build: keep it optional so the
    ; whole record still parses against an upstream GlazeWM.
    pat .= '(?:,"sticky":(true|false))?'
    pat .= '.*?"handle":(-?\d+),"title":"((?:[^"\\]|\\.)*)","className":"((?:[^"\\]|\\.)*)","processName":"([^"]*)"'
    while pos := RegExMatch(j, pat, &m, pos) {
        if (m[1] != "")
            wsName := m[1]
        else
            out.Push(Map("id", m[2], "focus", m[4] = "true", "state", m[5],
                "display", m[6], "sticky", m[7] = "true", "hwnd", m[8] + 0,
                "title", JsonUnescape(m[9]), "class", m[10], "proc", m[11],
                "ws", wsName))
        pos += StrLen(m[0])
    }
    return out
}

; Workspace name -> isDisplayed. The non-greedy jump is safe: only workspaces
; carry an "isDisplayed" field, so the first one after a name is its own.
GlazeWssFrom(j) {
    out := Map(), pos := 1
    while pos := RegExMatch(j, '"type":"workspace","id":"[^"]+","name":"([^"]+)"[\s\S]*?"isDisplayed":(true|false)', &m, pos) {
        out[m[1]] := m[2] = "true"
        pos += StrLen(m[0])
    }
    return out
}

; The workspace you are on: the one holding the focused window. Read from the
; window list (one query) instead of matching the id from `query focused`
; against it -- that pairing kept coming back empty, and it cost a second
; query. Empty when no window has the focus (an empty workspace, or the
; desktop): the caller decides, and for "bring a window to me" the answer is
; the monitor under the pointer, not this (see lib-workspaces.ahk).
GlazeFocusedWs(wins := 0) {
    if !wins
        wins := GlazeWins()
    for w in wins
        if (w["focus"])
            return w["ws"]
    return ""
}

; The monitors, each with the workspaces attached to it and which one it is
; showing. Read from `query monitors`, where a monitor's own fields come AFTER
; its children, so the device name closes the block.
GlazeMonitors() {
    j := GlazeQuery("monitors"), out := [], cur := 0, pos := 1
    pat := '"type":"monitor"'
    pat .= '|"type":"workspace","id":"[^"]+","name":"([^"]+)"'
    pat .= '|"isDisplayed":(true|false)'
    pat .= '|"deviceName":"((?:[^"\\]|\\.)*)"'
    while pos := RegExMatch(j, pat, &m, pos) {
        hit := m[0]
        if (InStr(hit, '"type":"monitor"')) {
            cur := Map("device", "", "wss", [])
            out.Push(cur)
        } else if (m[1] != "" && cur) {
            cur["wss"].Push(Map("name", m[1], "displayed", false))
        } else if (m[2] != "" && cur && cur["wss"].Length) {
            ; A workspace's own isDisplayed comes after its children, so it
            ; belongs to the last workspace seen on this monitor.
            cur["wss"][cur["wss"].Length]["displayed"] := (m[2] = "true")
        } else if (m[3] != "" && cur && cur["device"] = "") {
            cur["device"] := StrReplace(m[3], "\\", "\")
        }
        pos += StrLen(m[0])
    }
    return out
}

; Windows change state rarely between two gestures, and a query costs ~200 ms:
; a short cache keeps Alt+drag from stalling before it starts.
GlazeWinsCached(maxAgeMs := 1000) {
    static at := 0, cached := []
    if (A_TickCount - at > maxAgeMs) {
        cached := GlazeWins()
        at := A_TickCount
    }
    return cached
}

; The GlazeWM id of a window while it is TILED, or "" (floating, fullscreen,
; minimised, or not managed at all).
GlazeTilingIdOf(hwnd) {
    for w in GlazeWinsCached()
        if (w["hwnd"] = hwnd)
            return w["state"] = "tiling" ? w["id"] : ""
    return ""
}

JsonUnescape(s) => StrReplace(StrReplace(StrReplace(s, '\"', '"'), "\\/", "/"), "\\\\", "\\")
