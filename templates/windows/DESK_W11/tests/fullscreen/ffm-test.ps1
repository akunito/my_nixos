# Focus follows the mouse: a fullscreen window must keep the focus while the
# pointer is over it, lose it when the pointer rests on the other monitor, and
# get it (and the direct path to the screen) back when the pointer returns.
. "$env:TEMP\perf\win32.ps1"
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$d = "$env:TEMP\perf"
function Modes($name) {
  Remove-Item "$d\$name.csv" -EA SilentlyContinue
  & "$d\PresentMon.exe" --process_name fliptest.exe --output_file "$d\$name.csv" --v2_metrics --timed 4 --terminate_after_timed --stop_existing_session --session_name AkuFfm --no_console_stats *> $null
  if (-not (Test-Path "$d\$name.csv")) { return "no frames" }
  $rows = @(Import-Csv "$d\$name.csv")
  if (-not $rows.Count) { return "no frames" }
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
$p = Start-Process "$d\fliptest.exe" -ArgumentList "40 0 gamelike" -PassThru
Start-Sleep 5
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
ParkCursorOnPrimary
Start-Sleep 2
"1 pointer over it     focused=$([W]::GetForegroundWindow() -eq $h) $(Modes ffm1)"
ParkCursorOnSecondary
Start-Sleep 2
# A fullscreen window keeps the focus when the pointer wanders off: GlazeWM
# does not hand the focus to whatever is under the pointer on another monitor
# while a game is running, which is what you want mid-game.
"2 pointer on monitor2 focused=$([W]::GetForegroundWindow() -eq $h) fg=$([W]::Cls([W]::GetForegroundWindow()))"
ParkCursorOnPrimary
Start-Sleep 2
"3 pointer back        focused=$([W]::GetForegroundWindow() -eq $h) $(Modes ffm3)"
# And after a workspace round trip, with the pointer over the window. The home
# workspace is the window's own: with focus following the mouse, the pointer can
# change the focused workspace between the command and the window appearing.
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
"   after parking the pointer: displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
"4 after workspace trip focused=$([W]::GetForegroundWindow() -eq $h) cloaked=$([W]::Cloak($h)) $(Modes ffm4)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
