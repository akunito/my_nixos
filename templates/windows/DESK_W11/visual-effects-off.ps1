# Turn every Windows animation off (Settings > Accessibility > Visual effects >
# "Animation effects", plus the taskbar/window ones that toggle hides), so Start,
# tray flyouts and windows appear instantly like on Sway. Per-user, no admin,
# applies immediately. Re-run after a Windows feature update if it comes back.
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class Spi {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint f);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint b, ref ANIMATIONINFO c, uint f);
  [StructLayout(LayoutKind.Sequential)] public struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
}
"@
$SPIF = 3  # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
$off = @{
  0x1003 = 'menu animation';        0x1005 = 'combo box animation'
  0x1007 = 'listbox smooth scroll'; 0x1013 = 'menu fade'
  0x1015 = 'selection fade';        0x1017 = 'tooltip animation'
  0x1019 = 'cursor shadow';         0x1043 = 'client area animation (Start, flyouts, UWP)'
}
foreach ($k in $off.Keys) {
  $ok = [Spi]::SystemParametersInfo([uint32]$k, 0, [IntPtr]::Zero, $SPIF)
  "{0,-48} {1}" -f $off[$k], ($(if ($ok) {'off'} else {'FAILED'}))
}
$ai = New-Object Spi+ANIMATIONINFO; $ai.cbSize = 8; $ai.iMinAnimate = 0
"{0,-48} {1}" -f 'window minimise/maximise animation', ($(if ([Spi]::SystemParametersInfo(0x0049, 8, [ref]$ai, $SPIF)) {'off'} else {'FAILED'}))
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarAnimations -Value 0 -Type DWord
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name DragFullWindows -Value '1'
"{0,-48} {1}" -f 'taskbar animations (registry)', 'off'
