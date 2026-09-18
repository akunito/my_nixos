# Windows left DWM-cloaked by a workspace switch (GlazeWM ignores cloaked windows
# when it starts, so a restart can orphan them): show them again.
. "$env:TEMP\perf\win32.ps1"
$h = [W]::GetTopWindow([IntPtr]::Zero); $n = 0
while ($h -ne [IntPtr]::Zero) {
  if ([W]::IsWindowVisible($h) -and [W]::Cloak($h) -ne 0 -and ([W]::GetWindowLong($h, -16) -band 0x00C00000)) {
    $r = [W]::Rect($h)
    if (($r.Rt - $r.L) -gt 200) {
      "uncloaking $([W]::Cls($h)) '$([W]::Txt($h))' [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)] cloak=$([W]::Cloak($h))"
      & "$env:TEMP\perf\cloaktest.exe" $([int64]$h) 0 | Select-String "SetCloak|cloaked-after"
      $n++
    }
  }
  $h = [W]::GetWindow($h, 2)
}
"uncloaked $n window(s)"
