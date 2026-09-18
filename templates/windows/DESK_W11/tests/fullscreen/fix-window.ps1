# Give one window a sane rect again (SW_RESTORE + explicit size).
param([int]$Hwnd, [int]$X = 200, [int]$Y = 150, [int]$W = 1600, [int]$H = 1000)
. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class F {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
$h = [IntPtr]$Hwnd
[void][F]::ShowWindow($h, 9)   # SW_RESTORE
Start-Sleep -Milliseconds 300
"SetWindowPos: $([F]::SetWindowPos($h, [IntPtr]::Zero, $X, $Y, $W, $H, 0x10))"
Start-Sleep 1
$r = [W]::Rect($h); "rect now [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)] iconic=$([W]::IsIconic($h))"
