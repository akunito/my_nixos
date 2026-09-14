# DESK_W11 — turn off Copilot and every built-in AI feature that has an off switch.
# ELEVATED PowerShell. Same policy set as the "Copilot, Recall, Windows AI" step of
# debloat.ps1, plus: the Copilot app itself, and the Office/Copilot key chord
# (Ctrl+Alt+Win+Shift+<key>), which otherwise fires on Hyper+Shift chords from
# hyper-desktops.ahk. Reversible: delete the values / reinstall from the Store.
$ErrorActionPreference = 'Continue'
function Reg($path, $name, $value, $type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
  "  $path\$name = $value"
}
"== Copilot"
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowCopilotButton 0
"== Recall / Click to Do"
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' DisableAIDataAnalysis 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' DisableAIDataAnalysis 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' AllowRecallEnablement 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' DisableClickToDo 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' DisableClickToDo 1
"== Search (Bing / Copilot suggestions in Start search)"
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
"== Edge Copilot sidebar"
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HubsSidebarEnabled 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' CopilotPageContext 0
"== Paint / Notepad AI"
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' DisableImageCreator 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' DisableGenerativeFill 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' DisableCocreator 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Notepad' DisableAIFeatures 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\Notepad' DisableAIFeatures 1
"== Office/Copilot key chord -> no-op (ms-officeapp protocol handler)"
Reg 'HKCU:\Software\Classes\ms-officeapp\Shell\Open\Command' '(default)' 'rundll32' 'String'
"== Copilot apps"
foreach ($n in 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'Microsoft.MicrosoftOfficeHub') {
  Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
  Get-AppxPackage -Name $n -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
  "  removed (if present): $n"
}
Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like '*Copilot*' } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
"DONE"
