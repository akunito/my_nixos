# Free a window stuck in GlazeWM's fullscreen state: pause the WM, shrink the
# window inside the monitor, let the WM pick it up again as floating.
param([string]$Proc = "notepad++")
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class P { [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f); }
"@
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq $Proc
if (-not $w) { "no window"; exit 1 }
$h = [IntPtr]$w.handle
& $glaze command wm-toggle-pause | Out-Null
Start-Sleep 1
$r = [W]::Rect($h)
# Park it on the primary monitor at a modest size: the window grew past the
# vertical monitor (system-DPI aware app at 150% on a 125% monitor), and while
# it exceeds the workspace GlazeWM keeps promoting it back to fullscreen.
$nx = 200; $ny = 100; $nw = 1200; $nh = 900
"moving to [$nx,$ny $nw x $nh]: $([P]::SetWindowPos($h, [IntPtr]::Zero, $nx, $ny, $nw, $nh, 0x4000 -bor 0x10))"
Start-Sleep 1
& $glaze command wm-toggle-pause | Out-Null
Start-Sleep 2
$w2 = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq $Proc
$r2 = [W]::Rect($h)
"now: state=$($w2.state.type) real[$($r2.L),$($r2.T) $($r2.Rt-$r2.L)x$($r2.B-$r2.T)]"
