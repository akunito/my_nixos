# Life of a fullscreen game window: minimize/restore, un-maximize/maximize (what
# Alt+drag does), and another window opening on top of it. After every step the
# window must be back in GlazeWM's fullscreen state and reach the screen
# directly (Independent Flip); while a window is on top, composition is expected.
param([string]$Mode = "startmax")
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class C {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$d = "$env:TEMP\perf"

# One re-measure when a reading is not direct: DWM grants a swapchain its
# independent flip a variable moment after a window operation, and the 4 s
# window landed on that moment on a different step of every run (0/470
# frames on step 1, 2, or 3-4, 2026-09-23 12:10) while the window manager
# had touched nothing over the game. A composition that persists fails the
# second reading just the same; both readings are reported.
function Modes($name, $seconds = 4) {
  $first = MeasureOnce $name $seconds
  if ($first -match '^(\d+)% direct' -and [int]$Matches[1] -ge 90) { return $first }
  Start-Sleep -Milliseconds 700
  $second = MeasureOnce "$name-again" $seconds
  "$second, first reading $first"
}
function MeasureOnce($name, $seconds = 4) {
  Remove-Item "$d\$name.csv" -EA SilentlyContinue
  & "$d\PresentMon.exe" --process_name fliptest.exe --output_file "$d\$name.csv" --v2_metrics --timed $seconds --terminate_after_timed --stop_existing_session --session_name AkuCycle --no_console_stats *> $null
  if (-not (Test-Path "$d\$name.csv")) { return "no frames" }
  $rows = @(Import-Csv "$d\$name.csv")
  if (-not $rows.Count) { return "no frames" }
  $direct = @($rows | ? PresentMode -match "Independent Flip").Count
  "{0}% direct ({1}/{2} frames)" -f [math]::Round(100 * $direct / $rows.Count), $direct, $rows.Count
}
function GameWin {
  $x = [W]::GetTopWindow([IntPtr]::Zero)
  while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { return $x }; $x = [W]::GetWindow($x, 2) }
  [IntPtr]::Zero
}
function Rect2 {
  $h = GameWin
  if ($h -eq [IntPtr]::Zero) { return "no window" }
  $r = [W]::Rect($h); "[$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)]"
}
function Pills2 {
  $ids = (Get-Process zebar -EA SilentlyContinue).Id
  $o = @(); $x = [W]::GetTopWindow([IntPtr]::Zero)
  while ($x -ne [IntPtr]::Zero) {
    if ($ids -contains [W]::Pid($x) -and [W]::Cls($x) -eq "Tauri Window") { $r = [W]::Rect($x); if (($r.Rt-$r.L) -gt 100) { $o += "$($r.L)=$(if ([W]::IsWindowVisible($x)) { 'VIS' } else { 'hid' })" } }
    $x = [W]::GetWindow($x, 2)
  }
  $o -join ","
}
function State {
  $w = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest" | Sort-Object width -Descending)[0]
  if ($w) { "$($w.state.type)" } else { "unmanaged" }
}

ParkCursorOnPrimary
Get-Process fliptest, charmap -EA SilentlyContinue | Stop-Process -Force
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($mon.children | ? isDisplayed).name | Out-Null
Start-Sleep 1
$p = StartAsUser "$d\fliptest.exe" "75 0 $Mode"
Start-Sleep 4
$h = GameWin
if ($h -eq [IntPtr]::Zero) { "no game window"; exit 1 }

"1 start           state=$(State) rect=$(Rect2) pills=$(Pills2) $(Modes cyc1)"

[void][C]::ShowWindow($h, 6)       # SW_MINIMIZE
Start-Sleep 2
$minState = State
[void][C]::ShowWindow($h, 9)       # SW_RESTORE
[void][C]::SetForegroundWindow($h)
Start-Sleep 3
"2 minimize+restore minimized=$minState state=$(State) rect=$(Rect2) pills=$(Pills2) $(Modes cyc2)"

[void][C]::ShowWindow($h, 9)       # restore down to a window
Start-Sleep 1
[void][C]::SetWindowPos($h, [IntPtr]::Zero, 300, 200, 1400, 900, 0x10)
Start-Sleep 2
$smallState = State
[void][C]::ShowWindow($h, 3)       # SW_MAXIMIZE
[void][C]::SetForegroundWindow($h)
Start-Sleep 3
"3 windowed+max    windowed=$smallState state=$(State) rect=$(Rect2) pills=$(Pills2) $(Modes cyc3)"

$cm = StartAsUser "$env:SystemRoot\system32\charmap.exe" ""
Start-Sleep 3
$ch = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Pid($x) -eq $cm.Id -and [W]::IsWindowVisible($x)) { $ch = $x; break }; $x = [W]::GetWindow($x, 2) }
if ($ch -ne [IntPtr]::Zero) {
  [void][C]::SetWindowPos($ch, [IntPtr]::Zero, 600, 400, 800, 600, 0x10)
  [void][C]::SetForegroundWindow($ch)
}
Start-Sleep 2
# Is it really above the game? (otherwise the check below proves nothing)
$aboveGame = $false; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero -and $x -ne $h) { if ($x -eq $ch) { $aboveGame = $true; break }; $x = [W]::GetWindow($x, 2) }
"4 window on top   over-game=$aboveGame state=$(State) rect=$(Rect2) pills=$(Pills2) $(Modes cyc4)"

Stop-Process -Id $cm.Id -Force -EA SilentlyContinue
Start-Sleep 1
[void][C]::SetForegroundWindow($h)
Start-Sleep 1
# Windows refuses a foreground change from a background process; a window that
# is not in front is composed no matter what, so make sure it really is.
if ([W]::GetForegroundWindow() -ne $h) {
  [void][C]::ShowWindow($h, 6)     # SW_MINIMIZE
  Start-Sleep 1
  [void][C]::ShowWindow($h, 9)     # SW_RESTORE gives it the foreground
  [void][C]::SetForegroundWindow($h)
}
Start-Sleep 2
"5 on top closed   state=$(State) rect=$(Rect2) pills=$(Pills2) $(Modes cyc5)"

Stop-Process -Id $p.Id -Force -EA SilentlyContinue
