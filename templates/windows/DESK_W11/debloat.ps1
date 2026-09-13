# DESK_W11 — conservative Windows 11 debloat. ELEVATED PowerShell. Reboot after.
# Everything here is reversible with the mirror line in the comment. Nothing
# touches Defender, Windows Update, Xbox/Game services, audio, Bluetooth,
# printing or Explorer basics. Companion: docs/akunito/infrastructure/desk-w11-wsl.md
$ErrorActionPreference = 'Continue'
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Reg($path, $name, $value, $type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
}

Step "Copilot, Recall, Windows AI"                       # undo: delete the values
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' DisableAIDataAnalysis 1   # Recall
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' DisableAIDataAnalysis 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' AllowRecallEnablement 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' DisableClickToDo 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowCopilotButton 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HubsSidebarEnabled 0                     # Edge Copilot sidebar
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' CopilotPageContext 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1 # Bing/Copilot in Start search
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' DisableImageCreator 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint' DisableGenerativeFill 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Notepad' DisableAIFeatures 1
Get-AppxPackage -AllUsers *Copilot* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Step "Telemetry, ads, suggestions, Spotlight, widgets"    # undo: set to 1 / delete
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' AllowTelemetry 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' DisabledByGroupPolicy 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SubscribedContent-338388Enabled 0 # Start suggestions
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SubscribedContent-338389Enabled 0 # tips
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SubscribedContent-353694Enabled 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SubscribedContent-353696Enabled 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SilentInstalledAppsEnabled 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' RotatingLockScreenOverlayEnabled 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Start_IrisRecommendations 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarDa 0            # widgets button
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowTaskViewButton 1   # keep: Hyper+Tab
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' HideFileExt 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Hidden 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' TailoredExperiencesWithDiagnosticDataEnabled 0
Reg 'HKCU:\Software\Microsoft\Input\TIPC' Enabled 0                                              # typing telemetry
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' DisableWindowsConsumerFeatures 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' DisableCloudOptimizedContent 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' EnableActivityFeed 0                     # timeline upload
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' PublishUserActivities 0

Step "Delivery Optimization: no P2P uploads"              # undo: DODownloadMode 1
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode 0

Step "Services safe to disable"                           # undo: Set-Service -StartupType Manual
$svc = @(
  'DiagTrack',            # Connected User Experiences and Telemetry
  'dmwappushservice',     # WAP push (telemetry routing)
  'RemoteRegistry',
  'Fax',
  'MapsBroker',           # offline maps
  'RetailDemo',
  'WMPNetworkSvc',        # Media Player network sharing
  'lfsvc',                # Geolocation (no GPS on a desktop)
  'PcaSvc',               # Program Compatibility Assistant nagging
  'WerSvc'                # Windows Error Reporting uploads
)
foreach ($s in $svc) {
  if (Get-Service $s -ErrorAction SilentlyContinue) {
    Stop-Service $s -Force -ErrorAction SilentlyContinue
    Set-Service $s -StartupType Disabled
    Write-Host "  disabled $s"
  }
}
# Kept ON on purpose: SysMain (fine on NVMe), WSearch (Explorer search; index only Users), Spooler (printers),
# XblAuthManager/XboxNetApiSvc/GamingServices (Game Pass + controllers), BthAvctpSvc (headset), WinDefend.

Step "Remove store apps nobody asked for"                 # undo: reinstall from Microsoft Store
$apps = @(
  'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Microsoft.GetHelp','Microsoft.Getstarted',
  'Microsoft.MicrosoftOfficeHub','Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.PowerAutomateDesktop',
  'Microsoft.Todos','Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.ZuneVideo','Microsoft.ZuneMusic',
  'Microsoft.YourPhone','MicrosoftTeams','MSTeams','Microsoft.OutlookForWindows','Clipchamp.Clipchamp','Microsoft.549981C3F5F10',
  'MicrosoftCorporationII.QuickAssist','Microsoft.Windows.DevHome','Microsoft.MicrosoftStickyNotes','Microsoft.WindowsAlarms',
  'Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.OneDrive'
)
foreach ($a in $apps) {
  Get-AppxPackage -AllUsers $a -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
  Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $a | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}
# OneDrive: Nextcloud replaces it
$od = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"; if (Test-Path $od) { & $od /uninstall }
# Kept: Calculator, Photos, Snipping Tool, Terminal, Store, Xbox, Notepad, Paint.

Step "Edge: no background/prelaunch, not the default"      # undo: delete the values
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' BackgroundModeEnabled 0
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' HideFirstRunExperience 1

Step "Gaming: Game Mode on, no Game Bar popups, HAGS on"
Reg 'HKCU:\Software\Microsoft\GameBar' AutoGameModeEnabled 1
Reg 'HKCU:\Software\Microsoft\GameBar' ShowStartupPanel 0
Reg 'HKCU:\Software\Microsoft\GameBar' UseNexusForGameBarEnabled 0
Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 2                        # hardware GPU scheduling
Reg 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0                                             # background recording off

Step "Explorer: open This PC, no recent files in Home"
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' LaunchTo 1
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' ShowRecent 0
Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' ShowFrequent 0

Write-Host "`nNot touched (decide yourself): Core Isolation / Memory Integrity (Settings > Windows Security > Device security) — off gives ~5% more FPS, on keeps kernel driver isolation. Startup apps: Settings > Apps > Startup — leave only Nextcloud, Tailscale, AutoHotkey, Bitwarden." -ForegroundColor Yellow
Write-Host "Reboot now." -ForegroundColor Green
