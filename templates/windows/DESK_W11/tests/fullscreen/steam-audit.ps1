. "$env:TEMP\perf\win32.ps1"
$ids = (Get-Process steam, steamwebhelper -EA SilentlyContinue).Id
$h = [W]::GetTopWindow([IntPtr]::Zero)
while ($h -ne [IntPtr]::Zero) {
  if ($ids -contains [W]::Pid($h)) {
    $st = [W]::GetWindowLong($h, -16); $r = [W]::Rect($h)
    $f = @(); if ($st -band 0x10000000) { $f += "visible-style" }; if ([W]::IsWindowVisible($h)) { $f += "visible" }
    if ([W]::IsIconic($h)) { $f += "MINIMISED" }; if ([W]::IsZoomed($h)) { $f += "maximised" }
    if ([W]::Cloak($h)) { $f += "CLOAKED=$([W]::Cloak($h))" }
    if (($r.Rt - $r.L) -gt 100 -or [W]::IsWindowVisible($h)) {
      "hwnd=$h pid=$([W]::Pid($h)) cls=$([W]::Cls($h)) [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)] $($f -join ',') title='$([W]::Txt($h))'"
    }
  }
  $h = [W]::GetWindow($h, 2)
}
