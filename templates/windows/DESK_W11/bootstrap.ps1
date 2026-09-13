# DESK_W11 — Windows 11 side bootstrap. Run in an ELEVATED PowerShell.
# Idempotent: every step checks before acting. Read it before running it.
# Companion: docs/akunito/infrastructure/desk-w11-wsl.md (the runbook)
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\bootstrap.ps1            # everything
#   .\bootstrap.ps1 -SkipApps  # only system settings

param(
  [switch]$SkipApps,
  [switch]$SkipWsl
)
$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# ---------------------------------------------------------------- dual boot
Step "Fast Startup / hibernation OFF (NTFS partitions stay clean for Linux)"
powercfg /h off
# belt and braces: the Control Panel checkbox reads this value
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
  -Name HiberbootEnabled -PropertyType DWord -Value 0 -Force | Out-Null

Step "Hardware clock in UTC (NixOS on the other partition keeps the RTC in UTC)"
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' `
  -Name RealTimeIsUniversal -PropertyType DWord -Value 1 -Force | Out-Null

Step "Power plan: High performance"
$hp = (powercfg /list | Select-String 'High performance|Alto rendimiento' | ForEach-Object { ($_ -split '\s+')[3] })
if ($hp) { powercfg /setactive $hp }

# ---------------------------------------------------------------- apps
if (-not $SkipApps) {
  Step "winget import (declarative list: winget-packages.json — already-installed packages are skipped)"
  winget source update
  winget import -i "$PSScriptRoot\winget-packages.json" --accept-package-agreements --accept-source-agreements --ignore-unavailable --disable-interactivity
  Step "Claude Code (native, for the PowerShell side only — the real one lives in WSL)"
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { irm https://claude.ai/install.ps1 | iex }
  Write-Host "  not on winget, install by hand: AMD Adrenalin driver, Aion 2 (NCSoft/Purple launcher), Lineage2Dex launcher, Equalizer APO (EasyEffects stand-in)"
  Write-Warning "Spotify is elevationProhibited: winget import ALWAYS fails on it from this elevated shell. Install it afterwards from a NORMAL (non-elevated) PowerShell: winget install --id Spotify.Spotify --exact --source winget"
}

# ---------------------------------------------------------------- WSL
if (-not $SkipWsl) {
  Step "WSL2 platform (no default distro)"
  wsl --install --no-distribution
  wsl --update
  Step ".wslconfig (mirrored networking, dnsTunneling, memory cap)"
  Copy-Item -Force "$PSScriptRoot\.wslconfig" "$env:USERPROFILE\.wslconfig"
  Write-Host "  next: download nixos.wsl from https://github.com/nix-community/NixOS-WSL/releases/latest"
  Write-Host "        wsl --install --from-file .\nixos.wsl   (WSL >= 2.4.4)"
}

# ---------------------------------------------------------------- shortcuts
Step "AutoHotkey Hyper shortcuts at logon"
$ahk = "$PSScriptRoot\hyper-desktops.ahk"
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'hyper-desktops.lnk'
if (-not (Test-Path $lnk)) {
  $uia = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64_UIA.exe"   # UI Access build: drives elevated windows without admin
  if (-not (Test-Path $uia)) { $uia = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"; Write-Warning "UIA binary missing — elevated windows will ignore the hotkeys" }
  if (Test-Path $uia) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk); $s.TargetPath = $uia; $s.Arguments = "`"$ahk`""; $s.WorkingDirectory = $PSScriptRoot; $s.Save()
  } else { Write-Warning "AutoHotkey v2 not installed yet - shortcut skipped. Re-run without -SkipApps: a shortcut created now would point nowhere and no later run would repair it." }
}
Write-Host "  VirtualDesktopAccessor.dll must sit next to the .ahk: https://github.com/Ciantic/VirtualDesktopAccessor/releases"

Step "done — reboot once, then continue with the runbook (WSL section)"
