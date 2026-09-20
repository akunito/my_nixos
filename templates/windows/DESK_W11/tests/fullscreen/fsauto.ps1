# Does GlazeWM classify a window that covers the whole monitor as fullscreen by
# itself (no set-fullscreen), and does the taskbar drop below it?
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
# Run it on the workspace of the primary monitor, like a game.
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
$ws = ($mon.children | ? isDisplayed).name
& $glaze command focus --workspace $ws | Out-Null
Start-Sleep 1
ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$p = Start-Process "$d\fliptest.exe" -ArgumentList "34 0" -PassThru
Start-Sleep 6
$w = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest" | Sort-Object width -Descending)[0]
"workspace $ws -> state=$($w.state.type) display=$($w.displayState) glazeRect=$($w.x),$($w.y) $($w.width)x$($w.height)"
"monitor bounds=$($mon.x),$($mon.y) $($mon.width)x$($mon.height) work=$($mon.workingArea | ConvertTo-Json -Compress)"
$h = [IntPtr]$w.handle
$above = @(); $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero -and $x -ne $h) { if ([W]::IsWindowVisible($x) -and -not [W]::Cloak($x)) { $r = [W]::Rect($x); if (($r.Rt-$r.L) -gt 0 -and $r.T -lt 1400) { $above += [W]::Cls($x) } }; $x = [W]::GetWindow($x, 2) }
"above: $($above -join ',')"
# PresentMon writes nothing when another fullscreen D3D window has just
# exited: the presents of this one stall for several seconds (measured
# 2026-09-20, by pid as well as by name, with the window visible and
# focused). Three tries with a real pause between them, and by pid so the
# frames of any other fliptest are not mixed in.
$modes = ""
foreach ($try in 1..3) {
  Remove-Item "$d\fsauto.csv" -EA SilentlyContinue
  & "$d\PresentMon.exe" --process_id $p.Id --output_file "$d\fsauto.csv" --v2_metrics --timed 5 --terminate_after_timed --stop_existing_session --session_name AkuFs --no_console_stats *> $null
  if (Test-Path "$d\fsauto.csv") {
    $modes = ((Import-Csv "$d\fsauto.csv" | Group-Object PresentMode | % { "$($_.Name)=$($_.Count)" }) -join ", ")
    if ($modes) { break }
  }
  Start-Sleep 5
}
if (-not $modes) { $modes = "no frames captured" }
$modes
