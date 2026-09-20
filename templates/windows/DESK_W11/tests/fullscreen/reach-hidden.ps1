# A window parked on a hidden workspace must still be reachable: focusing it
# through GlazeWM (what Hyper+<letter> now does) switches to its workspace and
# uncloaks it. Activating it with SetForegroundWindow does not (Windows cannot
# show a cloaked window) — that is how Telegram got trapped behind a game.
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class R { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
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
function Displayed { ((& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name) -join "," }
ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
$primary = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($primary.children | ? isDisplayed).name | Out-Null
Start-Sleep 1
$p = Start-Process "$d\fliptest.exe" -ArgumentList "25 0 gamelike" -PassThru
Start-Sleep 4
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
$map = @{}; foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $map[$ws.id] = $ws.name }
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
$homeWs = $map[$w.parentId]
# Take the other workspace from the monitor that owns the window: with focus
# following the pointer, a new window can land on the other monitor's workspace.
$ownMon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.children.name -contains $homeWs }
$other = @($ownMon.children | ? { $_.name -ne $homeWs } | % name)[0]
# GlazeWM's workspaces exist on demand, so the monitor may have only this one:
# fall back to another name from its range.
if (-not $other) { $other = if ($homeWs -eq "19") { "18" } else { [string]([int]$homeWs + 1) } }
"window on $homeWs, leaving to $other"
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 1
"   right after the switch: displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
WaitForCloak $h $true
"hidden:            displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
[void][R]::SetForegroundWindow($h)
Start-Sleep 2
"after activate:    displayed=$(Displayed) cloaked=$([W]::Cloak($h))  (expected: still hidden)"
& $glaze command focus --container-id $w.id | Out-Null
Start-Sleep 2
"after glaze focus: displayed=$(Displayed) cloaked=$([W]::Cloak($h))  (expected: $homeWs, 0)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
