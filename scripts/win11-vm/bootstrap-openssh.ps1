$ErrorActionPreference='Continue'
Start-Transcript -Path C:\vmsetup.log -Append | Out-Null
"capability state: " + (Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select -Expand State)
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
  $d = 'C:\Program Files\OpenSSH'
  Invoke-WebRequest -Uri http://192.168.122.1:8765/dl/OpenSSH-Win64.zip -OutFile $env:TEMP\openssh.zip
  Expand-Archive -Path $env:TEMP\openssh.zip -DestinationPath $env:TEMP\openssh -Force
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  Copy-Item -Path "$env:TEMP\openssh\OpenSSH-Win64\*" -Destination $d -Recurse -Force
  powershell -ExecutionPolicy Bypass -File "$d\install-sshd.ps1"
  $env:Path += ";$d"; [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','Machine') + ";$d", 'Machine')
  New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null
}
Set-Service sshd -StartupType Automatic; Start-Service sshd
New-Item -Path HKLM:\SOFTWARE\OpenSSH -Force | Out-Null
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
$ak = 'C:\ProgramData\ssh\administrators_authorized_keys'
Set-Content -Path $ak -Value 'SSH_PUBKEY_HERE' -Encoding ascii
icacls $ak /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
Restart-Service sshd
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name ConsentPromptBehaviorAdmin -Value 0 -Type DWord; "UAC: admins elevate without prompt"
Get-Service sshd, QEMU-GA, spice-vdagent -ErrorAction SilentlyContinue | Format-Table -AutoSize
"SETUP2 DONE"
Stop-Transcript | Out-Null
