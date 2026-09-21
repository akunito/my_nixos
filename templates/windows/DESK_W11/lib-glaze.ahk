; Shared GlazeWM CLI plumbing (hyper-desktops.ahk and tests/wm both include it).
; GlazeWM has no keybindings of its own here: every gesture shells out to
; `glazewm command ...`, and every decision is taken from `glazewm query ...`.
; ASCII only, no BOM: AHK reads a BOM-less file as ANSI.
#Requires AutoHotkey v2.0

; Which window manager answers. AkuWM ships a drop-in CLI that speaks the same
; words and returns the same JSON, so switching the desk over is a matter of
; pointing this at it -- no gesture in this file changes.
;
; The path comes from a file rather than an environment variable because this
; script is already running when the desk is switched: a variable set now would
; not reach it, and akuwm-switch.ps1 restarts the script anyway. A file is one
; less thing that can be half-applied.
global glazeExe := WmCli()

WmCli() {
    marker := EnvGet("LOCALAPPDATA") "\akuwm\wm-cli.txt"
    if FileExist(marker) {
        try {
            ; Chr(0xFEFF) first: a marker written by Set-Content -Encoding UTF8
            ; carries a BOM, and a path with three invisible bytes in front of
            ; it fails FileExist and sends the hotkeys silently back to GlazeWM.
            path := Trim(FileRead(marker, "UTF-8"), " `t`r`n" Chr(0xFEFF))
            if (path != "" && FileExist(path))
                return path
        }
    }
    return A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"
}

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

; ---- AkuWM's pipe ---------------------------------------------------------
; The shim works, and it is the compatibility path for anything that shells
; out. A gesture must not use it: it is a 68 MB self-contained .NET process per
; call, measured at 109 ms on this desk against GlazeWM's CLI at 47 ms, and
; essentially ALL of it is runtime startup -- loose files instead of single
; file saved 3 ms and ReadyToRun made it worse (2026-09-21). So when AkuWM is
; the one running, talk to its pipe and spawn nothing at all.
global wmPipe := InStr(glazeExe, "akuwm") || InStr(glazeExe, "AkuWM")

WmPipeAsk(request) {
    static RW := 0xC0000000, OPEN_EXISTING := 3, PIPE_BUSY := 231
    name := "\\.\pipe\akuwm"
    h := -1

    Loop 3 {
        h := DllCall("CreateFileW", "Str", name, "UInt", RW, "UInt", 0, "Ptr", 0,
                     "UInt", OPEN_EXISTING, "UInt", 0, "Ptr", 0, "Ptr")
        if (h != -1 && h != 0)
            break
        ; Every instance is answering somebody else; anything else is fatal.
        if (A_LastError != PIPE_BUSY)
            return ""
        DllCall("WaitNamedPipeW", "Str", name, "UInt", 200)
    }
    if (h = -1 || h = 0)
        return ""

    try {
        line := request "`n"
        size := StrPut(line, "UTF-8") - 1
        out := Buffer(size)
        StrPut(line, out, size, "UTF-8")
        if !DllCall("WriteFile", "Ptr", h, "Ptr", out, "UInt", size, "UInt*", &wrote := 0, "Ptr", 0)
            return ""

        answer := "", chunk := Buffer(65536)
        Loop 64 {
            if !DllCall("ReadFile", "Ptr", h, "Ptr", chunk, "UInt", chunk.Size, "UInt*", &read := 0, "Ptr", 0)
                break
            if (read = 0)
                break
            answer .= StrGet(chunk, read, "UTF-8")
            if InStr(answer, "`n")
                break
        }
        return answer
    } finally {
        DllCall("CloseHandle", "Ptr", h)
    }
}

Glaze(args) {
    global glazeExe, wmPipe
    t := A_TickCount
    if (wmPipe && WmPipeAsk("compat command " args) != "") {
        Dbg(Format("glaze {1} ({2} ms, pipe)", args, A_TickCount - t))
        return
    }
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
    ; The pipe first when AkuWM is running: no process, no temp file, no cmd.
    ; The answer carries the same envelope inside an outer one, and every
    ; pattern below scans the raw text, so they match either way.
    global wmPipe
    if (wmPipe) {
        j := WmPipeAsk("compat query " what)
        if (j != "") {
            Dbg(Format("query {1} ({2} ms, pipe, {3} bytes)", what, A_TickCount - t, StrLen(j)))
            return j
        }
    }

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
    return Map("wins", GlazeWinsFrom(j), "wss", GlazeWssFrom(j), "ok", GlazeAnswered(j))
}

GlazeWins() => GlazeWinsFrom(GlazeQuery("workspaces"))

; Whether GlazeWM answered at all. A query that fails (the WM restarting, the
; IPC server not up yet) comes back empty, and an empty window list reads
; exactly like "this app is not running" -- which would launch a second copy.
GlazeAnswered(j) => InStr(j, '"clientMessage"') > 0
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

; ---- AHK's coordinates are not AkuWM's --------------------------------------
; This script is system-DPI aware: every rectangle it sees is expressed as if
; the whole desktop ran at the PRIMARY monitor's scale. AkuWM is per-monitor
; aware and speaks physical pixels. On the main monitor (150%, the primary)
; the two agree exactly; on the vertical one (125%) they differ by 150/125 =
; 1.2, which is why ahk-space.ahk measured that monitor at 4608..6336 where it
; physically starts at 3840.
;
; So a number crossing from here into a `position` or `size` command has to be
; divided by that ratio, and one coming back multiplied by it. Measured
; 2026-09-21 by tests/wm: the repair asked for 1440x1080 and the window came
; back 1728x1296, which is exactly 1.2.
;
; Only when AkuWM is the one listening. GlazeWM was written to whatever space
; it uses, and this script was built against it.
; The ratio for the monitor a point is on: this process's system DPI over that
; monitor's real DPI. 144/144 = 1 on the primary, 144/120 = 1.2 on the
; vertical one, which is exactly the error tests/wm measured.
WmScaleOf(x, y) {
    global wmPipe
    if (!wmPipe)
        return 1.0

    mon := DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 2, "Ptr")

    ; Asked with per-monitor awareness and put straight back. To a process that
    ; only understands the system DPI -- this one -- Windows answers with the
    ; system DPI for EVERY monitor, so the plain call returns 144 on both
    ; screens of this desk and the ratio comes out 1 (measured 2026-09-21,
    ; which is why the first version of this changed nothing). -4 is
    ; PER_MONITOR_AWARE_V2.
    previous := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    dpiX := 0, dpiY := 0
    hr := DllCall("Shcore\GetDpiForMonitor", "Ptr", mon, "Int", 0, "UInt*", &dpiX, "UInt*", &dpiY)
    if (previous)
        DllCall("SetThreadDpiAwarenessContext", "Ptr", previous, "Ptr")

    if (hr != 0 || !dpiX)
        return 1.0

    return A_ScreenDPI / dpiX
}

; An AHK rectangle in the physical pixels AkuWM works in.
WmPhysical(x, y, w, h) {
    s := WmScaleOf(x, y)
    if (s = 1.0)
        return Map("x", x, "y", y, "w", w, "h", h)
    return Map("x", Round(x / s), "y", Round(y / s), "w", Round(w / s), "h", Round(h / s))
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
