# Focus follows the mouse: a fullscreen window must keep the focus while the
# pointer is over it, lose it when the pointer rests on the other monitor, and
# get it (and the direct path to the screen) back when the pointer returns.
. "$env:TEMP\perf\win32.ps1"
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$d = "$env:TEMP\perf"
# One capture can come back empty right after another process with the same
# name has exited (the trace session latches onto the dying one), so a blank
# result is retried once before it is believed.
# By pid: every stand-in here is another fliptest, and PresentMon's
# --process_name would count their frames as this window's.
function Capture($name) {
  Remove-Item "$d\$name.csv" -EA SilentlyContinue
  $target = if ($script:gamePid) { $script:gamePid } else { 0 }
  if ($target) {
    & "$d\PresentMon.exe" --process_id $target --output_file "$d\$name.csv" --v2_metrics --timed 4 --terminate_after_timed --stop_existing_session --session_name AkuFfm --no_console_stats *> $null
  } else {
    & "$d\PresentMon.exe" --process_name fliptest.exe --output_file "$d\$name.csv" --v2_metrics --timed 4 --terminate_after_timed --stop_existing_session --session_name AkuFfm --no_console_stats *> $null
  }
  if (-not (Test-Path "$d\$name.csv")) { return @() }
  @(Import-Csv "$d\$name.csv")
}
function Modes($name) {
  $rows = Capture $name
  if (-not $rows.Count) {
    Start-Sleep 2
    $rows = Capture "$name-retry"
    if (-not $rows.Count) { return "no frames" }
  }
  "{0}% direct" -f [math]::Round(100 * @($rows | ? PresentMode -match "Independent Flip").Count / $rows.Count)
}
ParkCursorOnPrimary
Get-Process fliptest, charmap -EA SilentlyContinue | Stop-Process -Force

# 0. The feature itself, with two ordinary windows GlazeWM manages (charmap is a
# dialog and GlazeWM leaves it alone, so it proves nothing).
$a = Start-Process "$d\fliptest.exe" -ArgumentList "22 0 300 200 900 700" -PassThru
Start-Sleep 3
$app = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Pid($x) -eq $a.Id -and [W]::Cls($x) -eq "FlipTestWnd") { $app = $x; break }; $x = [W]::GetWindow($x, 2) }
ParkCursorOnSecondary
Start-Sleep 2
"0a pointer parked away fg=$([W]::Cls([W]::GetForegroundWindow())) app-focused=$([W]::GetForegroundWindow() -eq $app)"
ParkCursorOn ([W]::Rect($app))
Start-Sleep 2
"0b hovering the app    app-focused=$([W]::GetForegroundWindow() -eq $app) fg=$([W]::Cls([W]::GetForegroundWindow()))"
Stop-Process -Id $a.Id -Force -EA SilentlyContinue
Start-Sleep 2

$primary = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($primary.children | ? isDisplayed).name | Out-Null
Start-Sleep 1
$p = Start-Process "$d\fliptest.exe" -ArgumentList "75 0 gamelike" -PassThru
$script:gamePid = $p.Id
Start-Sleep 5
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
ParkCursorOnPrimary
Start-Sleep 2
"1 pointer over it     focused=$([W]::GetForegroundWindow() -eq $h) $(Modes ffm1)"

# The workspace round trip comes BEFORE the second window: a second fullscreen
# D3D window (even on the other monitor) stalls this one's presents until it is
# hidden and shown again, so any present-mode measurement after that one reads
# "no frames" for ~10 s. The pointer stays over the window throughout.
$wsMap = @{}
foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $wsMap[$ws.id] = $ws.name }
$win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
$homeWs = $wsMap[$win.parentId]
"   window lives on workspace $homeWs"
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.children.name -contains $homeWs }
$other = @($mon.children | ? { $_.name -ne $homeWs } | % name)[0]
if (-not $other) { $other = if ($homeWs -eq "19") { "18" } else { [string]([int]$homeWs + 1) } }
function Displayed { ((& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name) -join "," }
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 2
"   after leaving to ${other}: displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
& $glaze command focus --workspace $homeWs | Out-Null
Start-Sleep 2
"   after returning to ${homeWs}: displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
ParkCursorOnPrimary
Start-Sleep 2
"2 after workspace trip focused=$([W]::GetForegroundWindow() -eq $h) cloaked=$([W]::Cloak($h)) $(Modes ffm2)"

# Hovering the other monitor must hand the focus to the window under the
# pointer -- with a window actually there. Parking on an empty desktop proves
# nothing: Windows leaves the focus where it was, so the case used to pass or
# fail depending on what happened to be open on that monitor.
$s = Start-Process "$d\fliptest.exe" -ArgumentList "25 1 now" -PassThru
Start-Sleep 3
$side = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Pid($x) -eq $s.Id -and [W]::Cls($x) -eq "FlipTestWnd") { $side = $x; break }; $x = [W]::GetWindow($x, 2) }
if ($side -ne [IntPtr]::Zero) { ParkCursorOn ([W]::Rect($side)) } else { ParkCursorOnSecondary }
Start-Sleep 2
"3 pointer on monitor2 focused=$([W]::GetForegroundWindow() -eq $h) other-focused=$([W]::GetForegroundWindow() -eq $side) fg=$([W]::Cls([W]::GetForegroundWindow()))"
Stop-Process -Id $s.Id -Force -EA SilentlyContinue
Start-Sleep 3
ParkCursorOnPrimary
Start-Sleep 2
# Focus only: see the note above, the presents of this window are stalled for a
# few seconds by the one that just exited.
"4 pointer back        focused=$([W]::GetForegroundWindow() -eq $h)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
