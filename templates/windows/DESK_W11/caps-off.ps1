# Forces Caps Lock off from any shell (WSL included: `powershell.exe -File`),
# for when the hotkey script is not running to answer Hyper+CapsLock.
# SendKeys("{CAPSLOCK}") does nothing from a WSL-spawned PowerShell (no
# foreground window of its own, 2026-09-30); keybd_event does.
$sig = '[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);'
$k = Add-Type -MemberDefinition $sig -Name KB -Namespace W -PassThru
if ([Console]::CapsLock) {
    $k::keybd_event(0x14, 0x3A, 0, [UIntPtr]::Zero)
    $k::keybd_event(0x14, 0x3A, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
"CapsLock=$([Console]::CapsLock)"
