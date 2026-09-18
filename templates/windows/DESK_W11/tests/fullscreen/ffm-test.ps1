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
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
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
"2 pointer on monitor2 focused=$([W]::GetForegroundWindow() -eq $h) fg=$([W]::Cls([W]::GetForegroundWindow()))"
ParkCursorOnPrimary
Start-Sleep 2
"3 pointer back        focused=$([W]::GetForegroundWindow() -eq $h) $(Modes ffm3)"
# And after a workspace round trip, with the pointer over the window.
$homeWs = ($primary.children | ? isDisplayed).name
$other = @($primary.children | ? { $_.name -ne $homeWs } | % name)[0]
if (-not $other) { $other = if ($homeWs -eq "19") { "18" } else { [string]([int]$homeWs + 1) } }
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 2
& $glaze command focus --workspace $homeWs | Out-Null
Start-Sleep 2
ParkCursorOnPrimary
Start-Sleep 2
"4 after workspace trip focused=$([W]::GetForegroundWindow() -eq $h) cloaked=$([W]::Cloak($h)) $(Modes ffm4)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
