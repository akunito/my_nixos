# DESK_W11 — Windows Update policy (Windows 11 Pro group policies, ELEVATED).
# Security/quality updates keep installing on their own; feature updates (version
# jumps) never land unattended; no reboot under a logged-on session; drivers do
# not come from Windows Update. AINF-396. Undo: delete the values.
# Raise the version pin by hand when we decide to move (TargetReleaseVersionInfo).
$ErrorActionPreference = 'Continue'
function Reg($path, $name, $value, $type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
  "  $name = $value"
}
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = "$wu\AU"
"== Pin the release (quality updates for it keep flowing)"
Reg $wu TargetReleaseVersion 1
Reg $wu ProductVersion 'Windows 11' 'String'
Reg $wu TargetReleaseVersionInfo '25H2' 'String'
"== Defer feature updates 365 days (belt and braces), quality updates 7 days"
Reg $wu DeferFeatureUpdates 1
Reg $wu DeferFeatureUpdatesPeriodInDays 365
Reg $wu DeferQualityUpdates 1
Reg $wu DeferQualityUpdatesPeriodInDays 7
"== No preview/insider builds"
Reg $wu ManagePreviewBuilds 1
Reg $wu ManagePreviewBuildsPolicyValue 0
"== Drivers come from vendor installers, not WU"
Reg $wu ExcludeWUDriversInQualityUpdate 1
"== Active hours 08-23, never auto-reboot with a user logged on"
Reg $wu SetActiveHours 1
Reg $wu ActiveHoursStart 8
Reg $wu ActiveHoursEnd 23
Reg $au NoAutoUpdate 0
Reg $au AUOptions 4                 # auto download + scheduled install
Reg $au NoAutoRebootWithLoggedOnUsers 1
"== current state"
Get-ItemProperty $wu | Select-Object TargetReleaseVersionInfo, DeferFeatureUpdatesPeriodInDays, DeferQualityUpdatesPeriodInDays, ExcludeWUDriversInQualityUpdate, ActiveHoursStart, ActiveHoursEnd | Format-List | Out-String
"DONE"
