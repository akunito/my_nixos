# Take the sticky windows out of the way for the duration of a suite, and put
# them back afterwards. A sticky window (Telegram, by rule) follows every
# workspace of its monitor, so it lands in the middle of every case that
# measures what is on screen or what the pointer is over.
#   sticky-park.ps1 off   -> remember them and unset the flag
#   sticky-park.ps1 on    -> set it again on the same windows
param([ValidateSet("off", "on")] [string] $mode = "off")
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$file = "$env:TEMP\perf\sticky-parked.txt"

if ($mode -eq "off") {
  $ids = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.sticky } | % { $_.id })
  # Never overwrite a list that is still parked: a second "off" would see
  # nothing sticky (they are already parked) and wipe the only record of what
  # to restore -- which is exactly how Telegram and the terminals lost the flag.
  $prev = if (Test-Path $file) { @(Get-Content $file) } else { @() }
  $all = @($prev + $ids | Select-Object -Unique | ? { $_ })
  if ($all.Count) { $all | Set-Content $file }
  # Minimize them too, not just unstick: they float and are kept on top, so a
  # terminal sitting over the middle of the main monitor is composited over
  # every fullscreen window the cases measure (case 1 read "Composed: Flip"
  # with alacritty on top of it, 2026-09-20).
  foreach ($id in $ids) {
    & $glaze command --id $id unset-sticky | Out-Null
    & $glaze command --id $id set-minimized | Out-Null
  }
  "parked $($ids.Count) sticky window(s)"
} else {
  if (-not (Test-Path $file)) { "nothing parked"; return }
  $ids = @(Get-Content $file)
  $windows = @((& $glaze query windows | ConvertFrom-Json).data.windows)
  $done = 0
  foreach ($id in $ids) {
    $w = $windows | ? { $_.id -eq $id } | Select-Object -First 1
    if (-not $w) { continue }
    # toggle-minimized, not set-floating: a window on the taskbar has to come
    # OFF it first. AkuWM ignored set-floating on a minimised window until
    # 2026-09-21 and this script deleted the record anyway, so three windows
    # stayed parked for hours with nothing left saying they had been.
    if ($w.state.type -eq "minimized") { & $glaze command --id $id toggle-minimized | Out-Null }
    & $glaze command --id $id set-sticky | Out-Null
    $done++
  }
  # Only once every one of them is off the taskbar: the record of what was
  # parked is the only way back, so it outlives a restore that did not take.
  $after = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? { $ids -contains $_.id -and $_.state.type -eq "minimized" })
  if ($after.Count) {
    "WARNING: $($after.Count) still minimised ($($after.processName -join ', ')); $file kept"
  } else {
    Remove-Item $file -EA SilentlyContinue
  }
  "restored $done sticky window(s)"
}
