. "$env:TEMP\perf\win32.ps1"
$ids = (Get-Process steamwebhelper,steam -EA SilentlyContinue).Id
$h = [W]::GetTopWindow([IntPtr]::Zero)
while ($h -ne [IntPtr]::Zero) {
  if ($ids -contains [W]::Pid($h) -and [W]::IsWindowVisible($h)) {
    $st = [W]::GetWindowLong($h, -16); $ex = [W]::GetWindowLong($h, -20); $r = [W]::Rect($h)
    $f = @(); if ($st -band 0x80000000) { $f += "POPUP" }; if ($st -band 0x00C00000) { $f += "caption" }
    if ($st -band 0x00040000) { $f += "sizebox" }; if ($ex -band 0x8) { $f += "TOPMOST" }
    if ([W]::IsZoomed($h)) { $f += "maximised" }
    "hwnd=$h cls=$([W]::Cls($h)) [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)] style=0x$($st.ToString('x')) $($f -join ',') title='$([W]::Txt($h))'"
  }
  $h = [W]::GetWindow($h, 2)
}
