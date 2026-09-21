# A floating window that is kept on top (sway's floating layer = HWND_TOPMOST
# here) shares the workspace with a fullscreen game: it must end up UNDER the
# game, and the game must keep its direct path to the screen. A window
# composited over a game costs it ~20 fps and 20 ms of latency (measured on
# Aion 2, 2026-09-17), so this is the case that guards the whole idea.
. "$env:TEMP\perf\win32.ps1"
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$d = "$env:TEMP\perf"

# By pid, not by process name: the chat-window stand-in is another fliptest,
# and its own (composed, as any small window is) frames would be counted as the
# game's -- which read as "52% direct" for a game that was in fact at 100%.
function Modes($name, $procId) {
  Remove-Item "$d\$name.csv" -EA SilentlyContinue
  & "$d\PresentMon.exe" --process_id $procId --output_file "$d\$name.csv" --v2_metrics --timed 4 --terminate_after_timed --stop_existing_session --session_name AkuSticky --no_console_stats *> $null
  if (-not (Test-Path "$d\$name.csv")) { return "no frames" }
  $rows = @(Import-Csv "$d\$name.csv")
  if (-not $rows.Count) { return "no frames" }
  $by = $rows | Group-Object PresentMode | % { "$($_.Name)=$($_.Count)" }
  "{0}% direct [{1}]" -f [math]::Round(100 * @($rows | ? PresentMode -match "Independent Flip").Count / $rows.Count), ($by -join ", ")
}
function WinOfPid($procId) {
  $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) { if ([W]::Pid($h) -eq $procId -and [W]::Cls($h) -eq "FlipTestWnd") { return $h }; $h = [W]::GetWindow($h, 2) }
  [IntPtr]::Zero
}
function Above($a, $b) {
  $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) { if ($h -eq $a) { return $true }; if ($h -eq $b) { return $false }; $h = [W]::GetWindow($h, 2) }
  $false
}
function IdOf($hwnd) {
  ((& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$hwnd }).id
}

ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 2
$primary = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($primary.children | ? isDisplayed).name | Out-Null
Start-Sleep 1

# The chat-window stand-in: floating, kept on top, sticky -- like Telegram.
# Started THROUGH EXPLORER so it runs with the normal user token: this script
# is elevated (PresentMon needs it) and GlazeWM, which is not, cannot set the
# z-order of an elevated window at all -- the stand-in would never be topmost,
# unlike the real Telegram.
[void](StartAsUser "$d\fliptest.exe" "")
Start-Sleep 4
$chatWin = [IntPtr]::Zero
$x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) {
  if ([W]::Cls($x) -eq "FlipTestWnd") { $chatWin = $x; break }
  $x = [W]::GetWindow($x, 2)
}
$chatId = IdOf $chatWin
& $glaze command --id $chatId set-floating | Out-Null
& $glaze command --id $chatId set-sticky | Out-Null
Start-Sleep 1
"chat floating+sticky topmost=$((([W]::GetWindowLong($chatWin, -20)) -band 0x8) -ne 0)"

# The game starts afterwards, on the same workspace -- THROUGH EXPLORER, for
# the same reason as the chat window above. Started from this elevated script
# it ran elevated, and a window manager running as the user cannot set the
# z-order of an elevated window at all: SetWindowPos silently did nothing, the
# game never entered the always-on-top band, and the case read
# game-topmost=False with the chat above it (2026-09-21). Diego's games run as
# the user, so elevated was never the thing to measure.
$game = StartAsUser "$d\fliptest.exe" "60 0 gamelike"
if (-not $game) { "FAIL: the game did not start"; return }
# Let the reordering settle before measuring: the first seconds after a
# fullscreen window appears are composed while the windows around it are being
# pushed under, and a capture started too early reads about half direct.
Start-Sleep 9
$gameWin = WinOfPid $game.Id
ParkCursorOnPrimary
Start-Sleep 2
$state = ((& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$gameWin }).state.type
"game state=$state chat-above-game=$(Above $chatWin $gameWin) chat-topmost=$((([W]::GetWindowLong($chatWin, -20)) -band 0x8) -ne 0) game-topmost=$((([W]::GetWindowLong($gameWin, -20)) -band 0x8) -ne 0)"
"present modes with the chat window on the same workspace: $(Modes stickygame $game.Id)"

Stop-Process -Id $game.Id -Force -EA SilentlyContinue
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
