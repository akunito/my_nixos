# Fullscreen window vs GlazeWM workspace switch: is it hidden, does the taskbar stay above it?
param([string]$OtherWs = "", [int]$Monitor = 0)
. "$env:TEMP\perf\win32.ps1"
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
function Snap($tag, $h) {
  $r = [W]::Rect($h); $fg = [W]::GetForegroundWindow()
  $above = @(); $x = [W]::GetTopWindow([IntPtr]::Zero)
  while ($x -ne [IntPtr]::Zero -and $x -ne $h) {
    if ([W]::IsWindowVisible($x) -and -not [W]::Cloak($x)) { $q = [W]::Rect($x)
      if ($q.Rt -gt $r.L -and $q.L -lt $r.Rt -and $q.B -gt $r.T -and $q.T -lt $r.B -and $q.Rt -gt $q.L) { $above += [W]::Cls($x) } }
    $x = [W]::GetWindow($x, 2) }
  $ws = (& $glaze query workspaces | ConvertFrom-Json).data.workspaces | ? isDisplayed | % name
  "{0,-22} visible={1} cloaked={2} iconic={3} fg={4} displayedWS={5} above=[{6}]" -f $tag, [W]::IsWindowVisible($h), [W]::Cloak($h), [W]::IsIconic($h), ([W]::Cls($fg)), ($ws -join ','), ($above -join ',')
}
$children = (& $glaze query monitors | ConvertFrom-Json).data.monitors[$Monitor].children
$HomeWs = ($children | ? isDisplayed).name
if (-not $OtherWs -or $OtherWs -eq $HomeWs) {
  # Any other workspace of this monitor: switching to the one we are on is a no-op
  # (and with toggle_workspace_on_refocus it bounces back).
  $OtherWs = @($children | ? { $_.name -ne $HomeWs } | % name)[0]
  if (-not $OtherWs) { $OtherWs = if ($HomeWs -eq "19") { "18" } else { [string]([int]$HomeWs + 1) } }
}
"switching to $OtherWs"
"home workspace $HomeWs"
# Land on the primary monitor's workspace (a new window goes to the FOCUSED one).
$primary = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($primary.children | ? isDisplayed).name | Out-Null
Start-Sleep 2
$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "30 $Monitor" -PassThru
Start-Sleep 3
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Pid($x) -eq $p.Id -and [W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
if ($h -eq [IntPtr]::Zero) { "no window"; exit 1 }
$win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
# GlazeWM puts a new window on the FOCUSED workspace, which may not be the one
# that was displayed here. Take the window's own workspace as the home one and
# make sure it is displayed, instead of moving windows around.
$wsMap = @{}
foreach ($ws in (& $glaze query workspaces | ConvertFrom-Json).data.workspaces) { $wsMap[$ws.id] = $ws.name }
$HomeWs = $wsMap[$win.parentId]
"window is on workspace $HomeWs"
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.children.name -contains $HomeWs }
if (-not (($mon.children | ? isDisplayed).name -eq $HomeWs)) {
  & $glaze command focus --workspace $HomeWs | Out-Null
  Start-Sleep 2
}
$OtherWs = @($mon.children | ? { $_.name -ne $HomeWs } | % name)[0]
if (-not $OtherWs) {
  # Workspaces exist on demand; pick another name from the monitor's range.
  $OtherWs = if ($HomeWs -eq "19") { "18" } else { [string]([int]$HomeWs + 1) }
}
"switching away to $OtherWs"
# Match a game: GlazeWM only marks a window fullscreen for the taskbar when its
# state is fullscreen, and our test window is classified floating.
if ($env:WSTEST_FULLSCREEN -eq "1") {
  & $glaze command --id $win.id set-fullscreen "--maximized=false" | Out-Null
  Start-Sleep 2
  $win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
}
"glazewm: state=$($win.state.type) display=$($win.displayState)"
Snap "1 started" $h
& $glaze command focus --workspace $OtherWs | Out-Null; Start-Sleep 1.5
$win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
"glazewm: state=$($win.state.type) display=$($win.displayState)"
Snap "2 switched away" $h
& $glaze command focus --workspace $HomeWs | Out-Null; Start-Sleep 2
$win = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.handle -eq [int64]$h }
"glazewm: state=$($win.state.type) display=$($win.displayState)"
Snap "3 back home" $h
& $glaze command focus --container-id $win.id 2>$null | Out-Null; Start-Sleep 2
Snap "4 focused window" $h
# present mode while the window is back in front (taskbar/overlay above => Composed)
$d = "$env:TEMP\perf"; Remove-Item "$d\wscap.csv","$d\wscap.done" -EA SilentlyContinue
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($elev) { & "$d\PresentMon.exe" --process_name fliptest.exe --output_file "$d\wscap.csv" --v2_metrics --timed 4 --terminate_after_timed --stop_existing_session --session_name AkuWs --no_console_stats *> $null }
else { "4" | Set-Content "$d\wscap.req"; while (-not (Test-Path "$d\wscap.done")) { Start-Sleep -Milliseconds 300 } }
$m = Import-Csv "$d\wscap.csv" | Group-Object PresentMode | Sort-Object Count -Descending | % { "$($_.Name)=$($_.Count)" }
"5 present modes after return: $($m -join ', ')  (elevated=$elev)"
Stop-Process -Id $p.Id -Force
