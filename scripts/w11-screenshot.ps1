# Capture a Windows monitor at native resolution from WSL on DESK_W11:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w scripts/w11-screenshot.ps1)" "$(wslpath -w /tmp/x.png)" [screenIndex]
# Without the DPI-awareness call the process is DPI-unaware: at 150 % scaling Screen.Bounds
# reports 2560x1440 for the 3840x2160 monitor and CopyFromScreen copies only its top-left
# two thirds (measured 2026-10-06, the right edge of game UIs was silently cut off).
param([string]$out, [int]$index = -1)
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class Dpi{[DllImport("user32.dll")]public static extern bool SetProcessDpiAwarenessContext(IntPtr v);}'
[Dpi]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null   # PER_MONITOR_AWARE_V2
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$s = if ($index -ge 0) { [System.Windows.Forms.Screen]::AllScreens[$index] } else { [System.Windows.Forms.Screen]::PrimaryScreen }
$b = $s.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($out)
Write-Output "$($s.DeviceName) $($b.Width)x$($b.Height)"
