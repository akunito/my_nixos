# The pill of the monitor with a fullscreen window must stay hidden even when the
# focus goes to a window on the OTHER monitor (clicking PowerShell there put it
# back over the game).
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class FG { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
function Pills {
  $ids = (Get-Process zebar -EA SilentlyContinue).Id
  $out = @(); $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) {
    if ($ids -contains [W]::Pid($h) -and [W]::Cls($h) -eq "Tauri Window") {
      $r = [W]::Rect($h)
      if (($r.Rt - $r.L) -gt 100 -and ($r.B - $r.T) -lt 100) { $out += "mon@$($r.L),$($r.T)=$(if ([W]::IsWindowVisible($h)) { 'VISIBLE' } else { 'hidden' })" }
    }
    $h = [W]::GetWindow($h, 2)
  }
  $out -join " "
}
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
$p = Start-Process "$d\fliptest.exe" -ArgumentList "14 0 gamelike" -PassThru
Start-Sleep 6
"with the game focused:      $(Pills)"
# Focus a window on the other monitor, like clicking the terminal there.
$other = [IntPtr]::Zero; $h = [W]::GetTopWindow([IntPtr]::Zero)
while ($h -ne [IntPtr]::Zero) {
  if ([W]::IsWindowVisible($h) -and -not [W]::Cloak($h) -and [W]::Cls($h) -notin @("FlipTestWnd", "Tauri Window", "Shell_SecondaryTrayWnd", "Shell_TrayWnd")) {
    $r = [W]::Rect($h)
    if ($r.L -gt 2000 -and ($r.Rt - $r.L) -gt 300) { $other = $h; break }
  }
  $h = [W]::GetWindow($h, 2)
}
[void][FG]::SetForegroundWindow($other)
Start-Sleep 2
"focus on other monitor ($([W]::Cls($other))): $(Pills)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
Start-Sleep 2
Start-Sleep 1
"after the game closes:      $(Pills)"
