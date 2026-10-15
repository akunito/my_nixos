# Safe debloat for the win11 VM (DESK libvirt guest). Telemetry + consumer apps + idle services. Keeps Defender, Store, Edge/WebView2, Terminal, winget, Windows Update.
$ErrorActionPreference='SilentlyContinue'
Start-Transcript -Path C:\vmdebloat.log -Append | Out-Null
"== telemetry policy"
$dc='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; New-Item $dc -Force|Out-Null
Set-ItemProperty $dc AllowTelemetry 0 -Type DWord; Set-ItemProperty $dc DoNotShowFeedbackNotifications 1 -Type DWord
Set-ItemProperty $dc LimitDiagnosticLogCollection 1 -Type DWord; Set-ItemProperty $dc DisableOneSettingsDownloads 1 -Type DWord
$ai='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; New-Item $ai -Force|Out-Null; Set-ItemProperty $ai DisabledByGroupPolicy 1 -Type DWord
$cdm='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($k in 'ContentDeliveryAllowed','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled','SilentInstalledAppsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled') { Set-ItemProperty $cdm $k 0 -Type DWord }
$cp='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; New-Item $cp -Force|Out-Null; Set-ItemProperty $cp DisableWindowsConsumerFeatures 1 -Type DWord; Set-ItemProperty $cp DisableConsumerAccountStateContent 1 -Type DWord
$ws='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Set-ItemProperty $ws BingSearchEnabled 0 -Type DWord; Set-ItemProperty $ws CortanaConsent 0 -Type DWord
$ex='HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; New-Item $ex -Force|Out-Null; Set-ItemProperty $ex DisableSearchBoxSuggestions 1 -Type DWord
$dsh='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; New-Item $dsh -Force|Out-Null; Set-ItemProperty $dsh AllowNewsAndInterests 0 -Type DWord
$cop='HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; New-Item $cop -Force|Out-Null; Set-ItemProperty $cop TurnOffWindowsCopilot 1 -Type DWord
$gd='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; New-Item $gd -Force|Out-Null; Set-ItemProperty $gd AllowGameDVR 0 -Type DWord
Set-ItemProperty 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarDa 0 -Type DWord   # widgets button
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ShowCopilotButton 0 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Start_IrisRecommendations 0 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' TailoredExperiencesWithDiagnosticDataEnabled 0 -Type DWord
"== scheduled tasks"
foreach ($t in '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Application Experience\StartupAppTask','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector','\Microsoft\Windows\Feedback\Siuf\DmClient','\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload','\Microsoft\Windows\Windows Error Reporting\QueueReporting','\Microsoft\Windows\Maps\MapsUpdateTask','\Microsoft\Windows\Maps\MapsToastTask') { schtasks /Change /TN $t /Disable 2>$null | Out-Null; $t }
"== services"
foreach ($s in 'DiagTrack','dmwappushservice','MapsBroker','RetailDemo','Spooler','SysMain','WSearch','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','PhoneSvc','WMPNetworkSvc','WerSvc','wisvc','lfsvc','TabletInputService','RemoteRegistry','diagnosticshub.standardcollector.service','SSDPSRV','fdPHost','FDResPub','WpnService','MessagingService','CDPSvc','CDPUserSvc','OneSyncSvc','PimIndexMaintenanceSvc','UnistoreSvc','UserDataSvc') { Get-Service -Name "$s*" | % { Stop-Service $_ -Force; Set-Service $_ -StartupType Disabled; "$($_.Name): disabled" } }
"== appx"
foreach ($a in 'Microsoft.Copilot','Microsoft.365Copilot','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.BingSearch','Clipchamp.Clipchamp','Microsoft.GamingApp','Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay','Microsoft.XboxSpeechToTextOverlay','Microsoft.Xbox.TCUI','Microsoft.XboxIdentityProvider','Microsoft.Edge.GameAssist','Microsoft.YourPhone','Microsoft.People','Microsoft.Todos','Microsoft.WindowsFeedbackHub','Microsoft.GetHelp','Microsoft.MicrosoftSolitaireCollection','Microsoft.PowerAutomateDesktop','MSTeams','MicrosoftTeams','Microsoft.OutlookForWindows','microsoft.windowscommunicationsapps','Microsoft.ZuneMusic','Microsoft.ZuneVideo','Microsoft.WindowsMaps','Microsoft.MicrosoftStickyNotes','MicrosoftWindows.Client.WebExperience','Microsoft.Windows.DevHome','MicrosoftWindows.CrossDevice','Microsoft.OneDriveSync','MicrosoftCorporationII.QuickAssist','Microsoft.WindowsCamera','Microsoft.WindowsSoundRecorder','Microsoft.WindowsAlarms','Microsoft.MicrosoftOfficeHub','Microsoft.Windows.Ai.Copilot.Provider','Microsoft.WidgetsPlatformRuntime') {
  Get-AppxPackage -AllUsers -Name $a | Remove-AppxPackage -AllUsers; Get-AppxProvisionedPackage -Online | ? DisplayName -eq $a | Remove-AppxProvisionedPackage -Online -AllUsers | Out-Null; "${a}: removed"
}
"== OneDrive"
Stop-Process -Name OneDrive -Force; $od = "$env:SystemRoot\System32\OneDriveSetup.exe"; if (Test-Path $od) { Start-Process -Wait $od '/uninstall' }
winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements --disable-interactivity | Out-Null
Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' OneDrive
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' OneDriveSetup; Remove-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' OneDriveSetup
"== power / visual"
powercfg /h off; powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; powercfg /change monitor-timeout-ac 0; powercfg /change standby-timeout-ac 0
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 2 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0 -Type DWord
Set-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate 0
"== winget baseline"
winget source update --disable-interactivity | Out-Null
"DEBLOAT DONE"
Stop-Transcript | Out-Null
