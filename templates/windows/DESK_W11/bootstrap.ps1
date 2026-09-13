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
  Step "winget packages"
  $pkgs = @(
    'Microsoft.WindowsTerminal',
    'Microsoft.PowerShell',
    'Git.Git',
    'Microsoft.VisualStudioCode',
    'Zen-Team.Zen-Browser',
    'Vivaldi.Vivaldi',
    'Nextcloud.NextcloudDesktop',
    'Tailscale.Tailscale',
    'AutoHotkey.AutoHotkey',
    'Bitwarden.Bitwarden',
    'Obsidian.Obsidian',
    'Telegram.TelegramDesktop',
    'Element.Element',
    'Spotify.Spotify',
    'dbeaver.dbeaver',
    'Microsoft.PowerToys',
    'DEVCOM.JetBrainsMonoNerdFont',
    'Anthropic.ClaudeCode'
  )
  foreach ($p in $pkgs) {
    if (winget list --id $p --exact --accept-source-agreements 2>$null | Select-String $p) {
      Write-Host "  ok   $p"
    } else {
      Write-Host "  add  $p"
      winget install --id $p --exact --silent --accept-package-agreements --accept-source-agreements
    }
  }
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
  $ws = New-Object -ComObject WScript.Shell
  $s = $ws.CreateShortcut($lnk); $s.TargetPath = $uia; $s.Arguments = "`"$ahk`""; $s.WorkingDirectory = $PSScriptRoot; $s.Save()
}
Write-Host "  VirtualDesktopAccessor.dll must sit next to the .ahk: https://github.com/Ciantic/VirtualDesktopAccessor/releases"

Step "done — reboot once, then continue with the runbook (WSL section)"
