# Focus follows the mouse (Sway's focus_follows_mouse), the native Windows way:
# "Activate a window by hovering over it" without raising it (windows keep their
# z-order like sway's floating windows do), 0 ms delay. Per user, no admin.
# Undo: same calls with 1 / 0 swapped, or Ease of Access > Mouse.
# With GlazeWM running (focus_follows_cursor: true in its config) run this with -Off:
# two focus-follows-mouse implementations fight over overlapping floating windows.
param([switch]$Off)
$track = $(if ($Off) { 0 } else { 1 })
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class SpiF {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint f);
}
"@
$SPIF = 3
"active window tracking:   " + $(if ([SpiF]::SystemParametersInfo(0x1001, 0, [IntPtr]$track, $SPIF)) {$(if ($Off) {'off (GlazeWM does it)'} else {'on'})} else {'FAILED'})   # SPI_SETACTIVEWINDOWTRACKING
"raise on hover (z-order): " + $(if ([SpiF]::SystemParametersInfo(0x100D, 0, [IntPtr]0, $SPIF)) {'off'} else {'FAILED'})  # SPI_SETACTIVEWNDTRKZORDER
"hover delay ms:           " + $(if ([SpiF]::SystemParametersInfo(0x2003, 0, [IntPtr]0, $SPIF)) {'0'} else {'FAILED'})    # SPI_SETACTIVEWNDTRKTIMEOUT
