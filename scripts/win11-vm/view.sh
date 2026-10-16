#!/usr/bin/env bash
# Open the win11 guest in virt-viewer. --auto-resize=never is required: the guest spice agent otherwise sets the
# display to viewer px × GTK scale 2 = 5096×2694 (measured 2026-10-16); with it the guest keeps the 2560×1440
# fixed by setres.ps1 and the viewer scales. The sway-apps rule r-125d3a18 sends app_id=virt-viewer to WS 13.
exec virt-viewer --connect qemu:///system --domain-name win11 --attach --auto-resize=never "$@"
