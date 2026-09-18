. "$env:TEMP\perf\win32.ps1"
function PName($p) { $x = Get-Process -Id $p -EA SilentlyContinue; if ($x) { $x.ProcessName } else { "?" } }
Add-Type -AssemblyName System.Windows.Forms
foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) {
  $b = $sc.Bounds
  "monitor [$($b.Left),$($b.Top) $($b.Width)x$($b.Height)]:"
  $h = [W]::GetTopWindow([IntPtr]::Zero)
  while ($h -ne [IntPtr]::Zero) {
    if ([W]::IsWindowVisible($h) -and -not [W]::IsIconic($h) -and -not [W]::Cloak($h)) {
      $r = [W]::Rect($h)
      if ($r.L -le $b.Left -and $r.T -le $b.Top -and $r.Rt -ge $b.Right -and $r.B -ge $b.Bottom) {
        "   covered by $(PName ([W]::Pid($h)))/$([W]::Cls($h)) [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)] title='$([W]::Txt($h))'"
      }
    }
    $h = [W]::GetWindow($h, 2)
  }
}
