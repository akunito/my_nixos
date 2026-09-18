# A window parked on a hidden workspace must still be reachable: focusing it
# through GlazeWM (what Hyper+<letter> now does) switches to its workspace and
# uncloaks it. Activating it with SetForegroundWindow does not (Windows cannot
# show a cloaked window) — that is how Telegram got trapped behind a game.
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class R { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$d = "$env:TEMP\perf"
function Displayed { ((& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name) -join "," }
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
$other = @($primary.children | ? { $_.name -ne $homeWs } | % name)[0]
"window on $homeWs, leaving to $other"
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 2
"hidden:            displayed=$(Displayed) cloaked=$([W]::Cloak($h))"
[void][R]::SetForegroundWindow($h)
Start-Sleep 2
"after activate:    displayed=$(Displayed) cloaked=$([W]::Cloak($h))  (expected: still hidden)"
& $glaze command focus --container-id $w.id | Out-Null
Start-Sleep 2
"after glaze focus: displayed=$(Displayed) cloaked=$([W]::Cloak($h))  (expected: $homeWs, 0)"
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
