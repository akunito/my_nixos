<#
.SYNOPSIS
  Default Windows Terminal profile on DESK_W11: land in NixOS (WSL) at ~/.dotfiles,
  or fall back to an interactive PowerShell in the same tab when WSL is broken.

.DESCRIPTION
  1. Probes the distro with a throwaway command (`wsl -d NixOS -e /bin/sh -c true`)
     under a timeout, so a WSL service that is missing, a distro that fails to
     register, or a VM that hangs on start never leaves a dead "process exited"
     tab.
  2. Probe OK  -> exec `wsl.exe -d NixOS --cd /home/akunito/.dotfiles`; when that
     shell exits the tab closes (its exit code is passed through).
  3. Probe KO  -> print why (wsl.exe's own message, decoded from UTF-16) plus the
     usual recovery commands, then start a normal interactive `pwsh` (with the
     user profile) in this tab.

  Windows Terminal profile (see windows-terminal.settings.json):
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.dotfiles\templates\windows\DESK_W11\wsl-or-pwsh.ps1"

.PARAMETER Test
  Print the decision (OK / FALLBACK + reason) and exit without starting any shell.
  `-Distro Nope -Test` exercises the fallback path, `-Timeout 0 -Test` the hang path.
#>
param(
    [string]$Distro   = 'NixOS',
    [string]$Dir      = '/home/akunito/.dotfiles',
    [int]   $Timeout  = 45,
    [int]   $Attempts = 3,
    [int]   $Pause    = 5,
    [switch]$Test
)

function Test-WslDistro {
    $out = Join-Path $env:TEMP "wsl-probe-$PID.out"
    $err = Join-Path $env:TEMP "wsl-probe-$PID.err"
    try {
        $p = Start-Process -FilePath 'wsl.exe' `
            -ArgumentList @('-d', $Distro, '-e', '/bin/sh', '-c', 'true') `
            -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($Timeout * 1000)) {
            try { $p.Kill() } catch {}
            return @{ ok = $false; why = "no answer from wsl.exe after $Timeout s (VM hung?)" }
        }
        if ($p.ExitCode -eq 0) { return @{ ok = $true } }
        # wsl.exe writes UTF-16LE when redirected
        $msg = (Get-Content $err, $out -Encoding Unicode -ErrorAction SilentlyContinue) -join ' '
        $msg = ($msg -replace "`0", '' -replace '\s+', ' ').Trim()
        return @{ ok = $false; why = "wsl.exe exit $($p.ExitCode): $msg" }
    } catch {
        return @{ ok = $false; why = "cannot start wsl.exe: $($_.Exception.Message)" }
    } finally {
        Remove-Item $out, $err -ErrorAction SilentlyContinue
    }
}

# Retried, because the first tab after a COLD BOOT is the one that loses. The
# WSL service and the distro take a few seconds to come up, the probe fails
# fast while they do, and the fallback fired -- so a reboot handed Diego a
# PowerShell prompt instead of his shell in ~/.dotfiles (2026-09-21). A hang is
# already covered by $Timeout, so only a quick refusal is worth retrying.
$r = $null
foreach ($attempt in 1..$Attempts) {
    $r = Test-WslDistro
    if ($r.ok -or $attempt -eq $Attempts) { break }
    if (-not $Test) {
        Write-Host "  WSL '$Distro' is not up yet ($($r.why)); retrying in $Pause s..." -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds $Pause
}

if ($Test) {
    if ($r.ok) { "OK: would run  wsl.exe -d $Distro --cd $Dir" } else { "FALLBACK: $($r.why)" }
    exit 0
}

if ($r.ok) {
    & wsl.exe -d $Distro --cd $Dir
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host "  WSL '$Distro' is not available: $($r.why)" -ForegroundColor Yellow
Write-Host "  Falling back to PowerShell in this tab." -ForegroundColor Yellow
Write-Host "  Diagnose: wsl --status ; wsl -l -v ; wsl --shutdown ; wsl -d $Distro" -ForegroundColor DarkGray
Write-Host ''
& pwsh.exe -NoLogo
exit $LASTEXITCODE
