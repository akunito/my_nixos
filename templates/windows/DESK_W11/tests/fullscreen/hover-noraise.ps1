# Linux-style focus: hovering a window focuses it WITHOUT lifting it; only a
# click raises it. And after a window comes back from a hidden workspace,
# hovering must keep working without having to click first.
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Clk {
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
}
"@
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$d = "$env:TEMP\perf"

function Above($a, $b) {   # is $a above $b in the z-order?
  $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) {
    if ($h -eq $a) { return $true }
    if ($h -eq $b) { return $false }
    $h = [W]::GetWindow($h, 2)
  }
  $false
}
function WinOfPid($procId) {
  $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) {
    if ([W]::Pid($h) -eq $procId -and [W]::Cls($h) -eq "FlipTestWnd") { return $h }
    $h = [W]::GetWindow($h, 2)
  }
  [IntPtr]::Zero
}
function Click { [Clk]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 80; [Clk]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 500 }

ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 1
# Two overlapping windows on the primary monitor: A on the left, B on top of it.
$pa = Start-Process "$d\fliptest.exe" -ArgumentList "60 0 200 300 1600 1200" -PassThru
Start-Sleep 2
$pb = Start-Process "$d\fliptest.exe" -ArgumentList "60 0 900 300 1600 1200" -PassThru
Start-Sleep 3
$a = WinOfPid $pa.Id
$b = WinOfPid $pb.Id
if ($a -eq [IntPtr]::Zero -or $b -eq [IntPtr]::Zero) { "windows missing"; exit 1 }
# Make sure both are on the workspace that is on screen: with focus following
# the pointer, the focused workspace can change while the windows are starting.
$wsMap0 = @{}
foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $wsMap0[$ws.id] = $ws.name }
$winA = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$a }
$wsName = $wsMap0[$winA.parentId]
# Only if it is not already on screen: with toggle_workspace_on_refocus, asking
# for the workspace you are on switches to the previous one and hides everything.
$displayed = (& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name
if ($displayed -notcontains $wsName) {
  & $glaze command focus --workspace $wsName | Out-Null
  Start-Sleep 2
}
"on screen        A-cloaked=$([W]::Cloak($a)) B-cloaked=$([W]::Cloak($b)) workspace=$wsName"
"rects            A=$([W]::Rect($a).L),$([W]::Rect($a).T) $(([W]::Rect($a)).Rt - ([W]::Rect($a)).L)x$(([W]::Rect($a)).B - ([W]::Rect($a)).T)  B=$([W]::Rect($b).L),$([W]::Rect($b).T)"
"start            B-above-A=$(Above $b $a) fg=$(if ([W]::GetForegroundWindow() -eq $b) { 'B' } elseif ([W]::GetForegroundWindow() -eq $a) { 'A' } else { 'other' })"

# Hover the part of A that B does not cover (A starts at x=200, B at x=900).
WalkCursorTo 400 900
$okA = WaitForFocus $a
"hover A          A-focused=$okA fg=$([W]::Cls([W]::GetForegroundWindow())) B-still-above-A=$(Above $b $a)"

Click
"click on A       A-focused=$([W]::GetForegroundWindow() -eq $a) A-now-above-B=$(Above $a $b)"

# Send them to a hidden workspace and back, then hover without clicking.
$wsMap = @{}
foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $wsMap[$ws.id] = $ws.name }
$win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$a }
$homeWs = $wsMap[$win.parentId]
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.children.name -contains $homeWs }
$other = @($mon.children | ? { $_.name -ne $homeWs } | % name)[0]
if (-not $other) { $other = if ($homeWs -eq "19") { "18" } else { [string]([int]$homeWs + 1) } }
& $glaze command focus --workspace $other | Out-Null
Start-Sleep 2
$displayed = (& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name
if ($displayed -notcontains $homeWs) { & $glaze command focus --workspace $homeWs | Out-Null }
Start-Sleep 2
WalkCursorTo 2100 900          # over the part of B that A does not cover
$okB = WaitForFocus $b
"after unhide     B-focused=$okB (hover only, no click)"
WalkCursorTo 400 900           # back over A
"hover A again    A-focused=$(WaitForFocus $a)"

Stop-Process -Id $pa.Id, $pb.Id -Force -EA SilentlyContinue
