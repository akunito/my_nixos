#Requires AutoHotkey v2.0
#SingleInstance Force
; What every gesture costs. Each operation is timed several times and reported
; as best/median/worst, so an optimisation can be checked instead of believed.
; Run: AutoHotkey64.exe bench.ahk   -> %TEMP%\perf\bench.txt
#Include ..\..\lib-repair.ahk
#Include ..\..\lib-app-toggle.ahk
#Include ..\..\lib-tiling-drag.ahk

out := ""
Bench(name, fn, times := 5) {
    global out
    runs := []
    Loop times {
        t := A_TickCount
        fn()
        runs.Push(A_TickCount - t)
    }
    sorted := runs.Clone()
    Loop sorted.Length - 1
        Loop sorted.Length - A_Index
            if (sorted[A_Index] > sorted[A_Index + 1]) {
                tmp := sorted[A_Index], sorted[A_Index] := sorted[A_Index + 1], sorted[A_Index + 1] := tmp
            }
    ; AHK's Format takes a printf-style spec after a colon ({1:-38s}), not the
    ; .NET comma form -- with a comma the placeholder is left as written.
    pad := name
    while (StrLen(pad) < 38)
        pad .= " "
    out .= pad " best " sorted[1] " ms   median " sorted[(sorted.Length + 1) // 2]
        . " ms   worst " sorted[sorted.Length] " ms`n"
}

Bench("query windows (raw)", () => GlazeQuery("windows"))
Bench("query workspaces (raw)", () => GlazeQuery("workspaces"))
Bench("query monitors (raw)", () => GlazeQuery("monitors"))
Bench("GlazeWins()  parse", () => GlazeWins())
Bench("GlazeSnapshot() windows+workspaces", () => GlazeSnapshot())
Bench("GlazeMonitors()", () => GlazeMonitors())
Bench("CurrentWs(1) cold (queries GlazeWM)", () => (WsCacheDrop(1), CurrentWs(1)))
Bench("CurrentWs(1) warm (cached)", () => CurrentWs(1))
Bench("GlazeTilingIdOf (Alt+drag start)", () => GlazeTilingIdOf(WinExist("A")))
Bench("AppWindows('fliptest.exe')", () => AppWindows("fliptest.exe"))
Bench("AppRawCount('WindowsTerminal.exe')", () => AppRawCount("WindowsTerminal.exe"))
Bench("AppFocusedRawWindow (fast path)", () => AppFocusedRawWindow("WindowsTerminal.exe"))
Bench("JournalRead()", () => JournalRead())
Bench("JournalSnapshot()", () => JournalSnapshot(true), 3)
Bench("Glaze('wm-redraw') (a command)", () => Glaze("wm-redraw"), 3)
; What the shell around a query costs: the same call without cmd.exe, output
; thrown away (so it measures the spawn + the IPC round trip, nothing else).
Bench("CLI spawn only (no cmd.exe)", () => RunWait('"' glazeExe '" query windows', , "Hide"))
; Win32-only work that runs on EVERY focus change.
Bench("enumerate all top-level windows", () => WinGetList())
Bench("window list of one process", () => WinGetList("ahk_exe WindowsTerminal.exe"))

try FileDelete(A_Temp "\perf\bench.txt")
FileAppend(out, A_Temp "\perf\bench.txt")
ExitApp
