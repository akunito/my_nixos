# Launch an app while a fullscreen game has focus (Hyper+L -> Telegram): the new
# window must stay on the same workspace, behind the game, and still be reachable
# afterwards (after leaving the workspace and coming back, and once the game is
# minimized).
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class B {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
# Hiding is asynchronous (the WM waits for the OS event), and a busy desktop can
# take a moment: wait for it instead of measuring blind.
function WaitForCloak($hwnd, $want, $timeoutMs = 4000) {
  $deadline = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $deadline) {
    if ((([W]::Cloak($hwnd)) -ne 0) -eq $want) { return }
    Start-Sleep -Milliseconds 250
  }
}
$d = "$env:TEMP\perf"

function WinOf($cls) {
  $x = [W]::GetTopWindow([IntPtr]::Zero)
  while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq $cls) { return $x }; $x = [W]::GetWindow($x, 2) }
  [IntPtr]::Zero
}
function WsOf($h) {
  $map = @{}
  foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $map[$ws.id] = $ws.name }
  $w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
  if (-not $w) { return "unmanaged" }
  "$($map[$w.parentId])/$($w.state.type)/$($w.displayState)"
}
function Report($tag, $game, $app) {
  $ga = [W]::Rect($game); $aa = [W]::Rect($app)
  # Is the app behind the game in z-order?
  $behind = $true; $x = [W]::GetTopWindow([IntPtr]::Zero)
  while ($x -ne [IntPtr]::Zero) { if ($x -eq $app) { $behind = $false; break }; if ($x -eq $game) { break }; $x = [W]::GetWindow($x, 2) }
  "{0,-22} game[ws={1} cloaked={2} iconic={3}] app[ws={4} cloaked={5} visible={6} rect={7},{8} behind={9}]" -f `
    $tag, (WsOf $game), [W]::Cloak($game), [W]::IsIconic($game), (WsOf $app), [W]::Cloak($app), [W]::IsWindowVisible($app), $aa.L, $aa.T, $behind
}

ParkCursorOnPrimary
Get-Process fliptest, charmap -EA SilentlyContinue | Stop-Process -Force
# Start on the workspace of the primary monitor: GlazeWM puts new windows on the
# FOCUSED workspace, which may belong to the other monitor.
$primary = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($primary.children | ? isDisplayed).name | Out-Null
Start-Sleep 2
$p = Start-Process "$d\fliptest.exe" -ArgumentList "60 0 gamelike" -PassThru
Start-Sleep 5
$game = WinOf "FlipTestWnd"
if ($game -eq [IntPtr]::Zero) { "no game window"; exit 1 }
$homeWs = (WsOf $game).Split("/")[0]
"game on workspace $homeWs"

# The launcher: a normal app started while the game holds the foreground.
$cm = Start-Process charmap.exe -PassThru
Start-Sleep 3
$app = WinOf "ClassicCharmap"
if ($app -eq [IntPtr]::Zero) { $app = WinOf "#32770" }
if ($app -eq [IntPtr]::Zero) { "no app window"; Stop-Process -Id $p.Id -Force; exit 1 }
Report "1 app launched" $game $app

# Leave the workspace and come back, like Hyper+Q/W.
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.children.name -contains $homeWs }
$other = @($mon.children | ? { $_.name -ne $homeWs } | % name)[0]
if (-not $other) { $other = if ($homeWs -eq "19") { "18" } else { [string]([int]$homeWs + 1) } }
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 1
WaitForCloak $game $true
WaitForCloak $app $true
Report "2 other workspace" $game $app
& $glaze command focus --workspace $homeWs | Out-Null
Start-Sleep 1
WaitForCloak $game $false
Report "3 back home" $game $app

# Minimize the game to get to the app, as a user would.
[void][B]::ShowWindow($game, 6)
Start-Sleep 2
Start-Sleep 1
# Reachable = it is the top visible window now that the game is minimized
# (SetForegroundWindow from a background process is refused by Windows).
$top = ""; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) {
  if ([W]::IsWindowVisible($x) -and -not [W]::Cloak($x) -and -not [W]::IsIconic($x)) {
    $r = [W]::Rect($x)
    if (($r.Rt - $r.L) -gt 200 -and [W]::Cls($x) -notmatch "Shell_TrayWnd|Tauri Window|Progman|WorkerW") { $top = $x; break }
  }
  $x = [W]::GetWindow($x, 2)
}
Report "4 game minimized" $game $app
"   app is the top window: $($top -eq $app) (top is $([W]::Cls($top)))"

# Bring the game back.
[void][B]::ShowWindow($game, 9)
[void][B]::SetForegroundWindow($game)
Start-Sleep 3
Report "5 game restored" $game $app

Stop-Process -Id $cm.Id, $p.Id -Force -EA SilentlyContinue
