# Take the sticky windows out of the way for the duration of a suite, and put
# them back afterwards. A sticky window (Telegram, by rule) follows every
# workspace of its monitor, so it lands in the middle of every case that
# measures what is on screen or what the pointer is over.
#   sticky-park.ps1 off   -> remember them and unset the flag
#   sticky-park.ps1 on    -> set it again on the same windows
param([ValidateSet("off", "on")] [string] $mode = "off")
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$file = "$env:TEMP\perf\sticky-parked.txt"

if ($mode -eq "off") {
  $ids = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.sticky } | % { $_.id })
  if ($ids.Count) { $ids | Set-Content $file } else { Remove-Item $file -EA SilentlyContinue }
  foreach ($id in $ids) { & $glaze command --id $id unset-sticky | Out-Null }
  "parked $($ids.Count) sticky window(s)"
} else {
  if (-not (Test-Path $file)) { "nothing parked"; return }
  $ids = @(Get-Content $file)
  $live = @((& $glaze query windows | ConvertFrom-Json).data.windows | % { $_.id })
  foreach ($id in $ids) { if ($live -contains $id) { & $glaze command --id $id set-sticky | Out-Null } }
  Remove-Item $file -EA SilentlyContinue
  "restored $($ids.Count) sticky window(s)"
}
