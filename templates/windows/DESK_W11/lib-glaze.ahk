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
    if FileExist(A_Temp "\hyper-debug.on")
        FileAppend A_Now " " msg "`n", A_Temp "\altdrag.log"
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
    tmp := A_Temp "\glazewm-query-" DllCall("GetCurrentProcessId") "-" (seq += 1) ".json"
    RunWait(A_ComSpec ' /c ""' glazeExe '" query ' what ' > "' tmp '""', , "Hide")
    j := ""
    try j := FileRead(tmp, "UTF-8")
    try FileDelete(tmp)
    return j
}

; ---- Parsed views ---------------------------------------------------------
; Windows, each tagged with the workspace it lives in. Read from the
; `workspaces` query, not from `windows`: that one is a flat list whose
; parentId is the immediate parent, which for a tiled window is a split
; container, not the workspace.
GlazeWins() {
    j := GlazeQuery("workspaces"), out := [], ws := "", pos := 1
    pat := '"type":"workspace","id":"[^"]+","name":"([^"]+)"'
    pat .= '|"type":"window","id":"([^"]+)","parentId":"([^"]+)","hasFocus":(true|false)'
    pat .= '.*?"state":\{"type":"([a-z]+)".*?"displayState":"([a-z]+)"'
    ; The sticky flag only exists in our fork build: keep it optional so the
    ; whole record still parses against an upstream GlazeWM.
    pat .= '(?:,"sticky":(true|false))?'
    pat .= '.*?"handle":(-?\d+),"title":"((?:[^"\\]|\\.)*)","className":"((?:[^"\\]|\\.)*)","processName":"([^"]*)"'
    while pos := RegExMatch(j, pat, &m, pos) {
        if (m[1] != "")
            ws := m[1]
        else
            out.Push(Map("id", m[2], "focus", m[4] = "true", "state", m[5],
                "display", m[6], "sticky", m[7] = "true", "hwnd", m[8] + 0,
                "title", JsonUnescape(m[9]), "class", m[10], "proc", m[11],
                "ws", ws))
        pos += StrLen(m[0])
    }
    return out
}

; Workspace name -> isDisplayed. The non-greedy jump is safe: only workspaces
; carry an "isDisplayed" field, so the first one after a name is its own.
GlazeWss() {
    j := GlazeQuery("workspaces"), out := Map(), pos := 1
    while pos := RegExMatch(j, '"type":"workspace","id":"[^"]+","name":"([^"]+)"[\s\S]*?"isDisplayed":(true|false)', &m, pos) {
        out[m[1]] := m[2] = "true"
        pos += StrLen(m[0])
    }
    return out
}

; The workspace you are on: the one holding the focused window, or the focused
; workspace itself when it is empty.
GlazeFocusedWs() {
    j := GlazeQuery("focused")
    if RegExMatch(j, '"focused":\{"type":"workspace","id":"[^"]+","name":"([^"]+)"', &m)
        return m[1]
    if RegExMatch(j, '"focused":\{"type":"window","id":"([^"]+)"', &m) {
        for w in GlazeWins()
            if (w["id"] = m[1])
                return w["ws"]
    }
    return ""
}

JsonUnescape(s) => StrReplace(StrReplace(StrReplace(s, '\"', '"'), "\\/", "/"), "\\\\", "\\")
