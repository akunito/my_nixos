# The fork fix for the workspaces mixed between monitors: every monitor
# reclaims the workspaces bound to it on a display-settings change, not only a
# monitor that was just added.
#
# The damage is set up by hand (a workspace moved to the wrong monitor, which
# is what a sleep cycle leaves behind) and the event is fired by re-applying
# the current display mode -- nothing changes on screen, but Windows sends
# WM_DISPLAYCHANGE and GlazeWM re-evaluates its monitors. Unplugging a monitor
# for real would be the only stronger test, and it cannot be done safely from
# a script.
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
Add-Type @"
using System;using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
public struct DEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
  public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
  public int dmFields;
  public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
  public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
  public short dmLogPixels;
  public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
  public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
}
public class D {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr h, int flags, IntPtr p);
}
"@
function Layout {
  $m = (& $glaze query monitors | ConvertFrom-Json).data.monitors
  $out = @{}
  foreach ($x in $m) { foreach ($c in $x.children) { $out[$c.name] = $x.deviceName } }
  $out
}
function Show($tag, $map) { "$tag " + (($map.Keys | Sort-Object | % { "$_=$($map[$_])" }) -join " ") }

$before = Layout
Show "before" $before
# Misplace a workspace: move the displayed one of the main monitor to the
# right. It needs a window in it -- GlazeWM destroys an empty workspace as soon
# as it stops being displayed, and there would be nothing left to restore.
$main = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
$ws = ($main.children | ? isDisplayed)
if (-not $ws.children.Count) {
  Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "120 0 600 400 900 700 now"
  Start-Sleep 4
  $main = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
  $ws = ($main.children | ? isDisplayed)
}
"misplacing workspace $($ws.name) ($($ws.children.Count) window(s))"
& $glaze command --id $ws.id move-workspace --direction right | Out-Null
Start-Sleep 2
$mixed = Layout
Show "mixed " $mixed
if ($mixed[$ws.name] -eq $before[$ws.name]) { "workspace did not move, nothing to test"; return }

# Fire a real display-settings change: re-applying the SAME mode is a no-op
# and Windows broadcasts nothing (checked -- the AHK log stayed silent), so a
# different mode is applied for a few seconds on the OTHER monitor and then
# put back. The main monitor is left alone on purpose.
$other = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -ne 0 -or $_.y -ne 0 } | Select-Object -First 1
$dev = $other.deviceName
$cur = New-Object DEVMODE
$cur.dmSize = [int16]220
if (-not [D]::EnumDisplaySettings($dev, -1, [ref]$cur)) { "could not read the mode of $dev"; return }
"current mode of ${dev}: $($cur.dmPelsWidth)x$($cur.dmPelsHeight)@$($cur.dmDisplayFrequency)"
$alt = $null
for ($i = 0; $i -lt 120; $i++) {
  $m = New-Object DEVMODE
  $m.dmSize = [int16]220
  if (-not [D]::EnumDisplaySettings($dev, $i, [ref]$m)) { break }
  if ($m.dmPelsWidth -ne $cur.dmPelsWidth -and $m.dmPelsWidth -ge 1024 -and $m.dmBitsPerPel -eq 32) { $alt = $m; break }
}
if (-not $alt) { "no other mode available on $dev"; return }
"switching ${dev} to $($alt.dmPelsWidth)x$($alt.dmPelsHeight) for a moment"
$alt.dmFields = 0x80000 -bor 0x100000 -bor 0x40000          # width, height, bits
[void][D]::ChangeDisplaySettingsEx($dev, [ref]$alt, [IntPtr]::Zero, 0x00000001, [IntPtr]::Zero)
Start-Sleep 8
$cur.dmFields = 0x80000 -bor 0x100000 -bor 0x40000
[void][D]::ChangeDisplaySettingsEx($dev, [ref]$cur, [IntPtr]::Zero, 0x00000001, [IntPtr]::Zero)
"restored"
Start-Sleep 14
$after = Layout
Show "after " $after
"workspace $($ws.name): was $($before[$ws.name]), mixed to $($mixed[$ws.name]), now $($after[$ws.name])"
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
if ($after[$ws.name] -eq $before[$ws.name]) { "RESULT ok" } else { "RESULT not restored" }
