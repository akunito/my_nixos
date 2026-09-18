. "$env:TEMP\perf\win32.ps1"
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class H {
  [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out UIntPtr r);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int t, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
$ids = (Get-Process notepad++).Id
$h = [W]::GetTopWindow([IntPtr]::Zero)
while ($h -ne [IntPtr]::Zero) {
  if ($ids -contains [W]::Pid($h) -and [W]::IsWindowVisible($h) -and [W]::Cls($h) -eq "Notepad++") { break }
  $h = [W]::GetWindow($h, 2)
}
$r = New-Object UIntPtr
$ok = [H]::SendMessageTimeout($h, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$r)
"hwnd=$h hung=$([H]::IsHungAppWindow($h)) pingOk=$($ok -ne [IntPtr]::Zero)"
"SetWindowPos sync: $([H]::SetWindowPos($h, [IntPtr]::Zero, 300, 150, 1100, 800, 0x10)) err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
Start-Sleep 1
$rc = [W]::Rect($h); "rect now [$($rc.L),$($rc.T) $($rc.Rt-$rc.L)x$($rc.B-$rc.T)]"
