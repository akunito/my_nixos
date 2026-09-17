. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
"checker elevated=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) target=$h"
& "$d\proc-token.ps1" -Name fliptest
"--- SetWindowPos (what GlazeWM does first):"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class SWP { [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f); }
"@
$ok = [SWP]::SetWindowPos($h, [IntPtr]::Zero, 100, 100, 1200, 800, 0x4000 -bor 0x10 -bor 0x400 -bor 0x4)
"SetWindowPos ok=$ok err=$([ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message)"
"--- SetCloak only:"
& "$d\cloaktest.exe" $([int64]$h) 1
"visible=$([W]::IsWindowVisible($h)) cloaked=$([W]::Cloak($h))"
& "$d\cloaktest.exe" $([int64]$h) 0
