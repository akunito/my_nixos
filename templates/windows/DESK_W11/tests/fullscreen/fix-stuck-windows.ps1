# Stop GlazeWM, give oversized windows a sane rect on the primary monitor, start
# GlazeWM again so it classifies them afresh (a window bigger than its monitor is
# promoted to fullscreen forever and can no longer be moved).
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class P { [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f); }
"@
$cli = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$targets = (& $cli query windows | ConvertFrom-Json).data.windows |
  Where-Object { $_.state.type -eq "fullscreen" }
"stuck fullscreen: " + (($targets | % { "$($_.processName) '$($_.title)'" }) -join ", ")
& $cli command wm-exit | Out-Null
Start-Sleep 4
$i = 0
foreach ($t in $targets) {
  $h = [IntPtr]$t.handle
  $x = 150 + 60 * $i; $y = 80 + 60 * $i; $i++
  [void][P]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, 1200, 900, 0x10)
  Start-Sleep -Milliseconds 400
  $r = [W]::Rect($h)
  "  $($t.processName) -> [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)]"
}
& "$env:TEMP\perf\glazewm-verbose.ps1"
Start-Sleep 3
(& $cli query windows | ConvertFrom-Json).data.windows | % { "  $($_.processName) state=$($_.state.type) [$($_.x),$($_.y) $($_.width)x$($_.height)]" }
