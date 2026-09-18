. "$env:TEMP\perf\win32.ps1"
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
"--- monitors (Win32):"
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class M {
  public delegate bool Cb(IntPtr h, IntPtr dc, IntPtr r, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, Cb c, IntPtr d);
  [StructLayout(LayoutKind.Sequential)] public struct MI { public int cb; public int l,t,r,b; public int wl,wt,wr,wb; public uint f; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfoW(IntPtr h, ref MI mi);
  [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr h, int t, out uint x, out uint y);
}
"@
[M]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, {
  param($h, $dc, $r, $d)
  $mi = New-Object M+MI; $mi.cb = [Runtime.InteropServices.Marshal]::SizeOf($mi)
  [void][M]::GetMonitorInfoW($h, [ref]$mi); $dx = 0; $dy = 0; [void][M]::GetDpiForMonitor($h, 0, [ref]$dx, [ref]$dy)
  "  mon [$($mi.l),$($mi.t) $($mi.r-$mi.l)x$($mi.b-$mi.t)] work [$($mi.wl),$($mi.wt) $($mi.wr-$mi.wl)x$($mi.wb-$mi.wt)] dpi=$dx primary=$([bool]($mi.f -band 1))"
  return $true
}, [IntPtr]::Zero) | Out-Null
"--- GlazeWM monitors/workspaces:"
$mons = (& $glaze query monitors | ConvertFrom-Json).data.monitors
foreach ($m in $mons) { "  monitor $($m.deviceName) [$($m.x),$($m.y) $($m.width)x$($m.height)] dpi=$($m.dpi) ws: " + (($m.children | % { $_.name + $(if ($_.isDisplayed) { '*' } else { '' }) }) -join ',') }
"--- windows GlazeWM knows:"
foreach ($w in (& $glaze query windows | ConvertFrom-Json).data.windows) {
  $h = [IntPtr]$w.handle
  $r = [W]::Rect($h)
  "  {0,-18} ws={1,-3} state={2,-10} disp={3,-8} glaze[{4},{5} {6}x{7}] real[{8},{9} {10}x{11}] cloaked={12} vis={13} min={14} title='{15}'" -f $w.processName, $w.parentId.Substring(0,3), $w.state.type, $w.displayState, $w.x, $w.y, $w.width, $w.height, $r.L, $r.T, ($r.Rt-$r.L), ($r.B-$r.T), [W]::Cloak($h), [W]::IsWindowVisible($h), [W]::IsIconic($h), $w.title.Substring(0, [Math]::Min(25, $w.title.Length))
}
