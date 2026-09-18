param([string]$Proc = "notepad++")
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class P { [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f); }
"@
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq $Proc
$h = [IntPtr]$w.handle
# Leave fullscreen and shrink it in the same breath: GlazeWM re-promotes any
# window whose frame still exceeds the workspace.
& $glaze command --id $w.id set-floating | Out-Null
for ($i = 0; $i -lt 12; $i++) {
  [void][P]::SetWindowPos($h, [IntPtr]::Zero, 200, 100, 1200, 900, 0x4000 -bor 0x10)
  Start-Sleep -Milliseconds 120
}
Start-Sleep 2
$w2 = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq $Proc
$r2 = [W]::Rect($h)
"now: state=$($w2.state.type) glaze[$($w2.x),$($w2.y) $($w2.width)x$($w2.height)] real[$($r2.L),$($r2.T) $($r2.Rt-$r2.L)x$($r2.B-$r2.T)]"
