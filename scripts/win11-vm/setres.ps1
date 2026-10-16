# Set the primary display mode (runs in the interactive session via run-interactive.ps1). Usage: setres.ps1 2560 1440
param([int]$W = 2560, [int]$H = 1440)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class DM {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll")] public static extern bool EnumDisplaySettings(string n, int i, ref DEVMODE d);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE d, int flags);
}
"@
$d = New-Object DM+DEVMODE; $d.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf($d)
[DM]::EnumDisplaySettings($null, -1, [ref]$d) | Out-Null
$d.dmPelsWidth = $W; $d.dmPelsHeight = $H; $d.dmFields = 0x80000 -bor 0x100000   # DM_PELSWIDTH | DM_PELSHEIGHT
$r = [DM]::ChangeDisplaySettings([ref]$d, 1)   # CDS_UPDATEREGISTRY -> persists
"ChangeDisplaySettings($W x $H) = $r" | Out-File C:\Users\Public\setres.txt
