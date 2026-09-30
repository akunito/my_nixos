# LAPTOP_YOGA Profile Configuration (nixosyogaaga)
# Lenovo ThinkPad X380 Yoga, Aga's second laptop.
#
# Inherits ALL of LAPTOP_A (software, services, backups, updates, Plasma power
# management, Claude/Plane setup) so the two machines behave the same and cannot
# drift apart. This file holds ONLY what differs: the hardware, and the machine's
# identity (hostname, IPs, metrics label). A software change for Aga's laptops
# goes into LAPTOP_A-config.nix and reaches both.
#
# Tailnet: 100.64.0.16 (Headscale user Yoga_Aga, in group:family). That IP is
# what NAS_PROD exports workstation_backups to.

let
  laptopA = import ./LAPTOP_A-config.nix;
in
{
  inherit (laptopA) useRustOverlay userSettings;

  systemSettings = laptopA.systemSettings // {
    # === Identity ===
    hostname = "nixosyogaaga";
    envProfile = "LAPTOP_YOGA"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_YOGA -s -u";
    ipAddress = "192.168.8.100"; # ethernet (pfSense DHCP reservation by MAC)
    wifiIpAddress = "192.168.8.101"; # wifi (pfSense DHCP reservation by MAC)
    infraNodeName = "laptop_yoga"; # Prometheus label + deploy announcements

    # === Hardware: ThinkPad X380 Yoga (i5-8250U, Intel UHD 620, Samsung NVMe) ===
    bootMode = "bios";
    grubDevice = "/dev/nvme0n1"; # BIOS boot on NVMe (Samsung MZVLB256HBHQ)
    grubEnableCryptodisk = true; # GRUB must unlock the LUKS disk
    thinkpadModel = "lenovo-thinkpad-x280"; # no x380-yoga module; X280 is the same generation
    thinkpadConvertible = true; # 2-in-1: auto-rotation in tablet mode
    thunderboltEnable = false; # X380 Yoga has no Thunderbolt 3
    # Measured 2026-09-30 (20LJ, BIOS R0SET47W 1.31, kernel 7.2.8): the EC does not
    # expose fan status — /proc/acpi/ibm/fan and hwmon fan1_input both return
    # ENXIO, although fan_control=Y and pwm1_enable=2 (firmware auto). thinkfan
    # refuses to start ("Fan_control seems disabled") and restart-loops every
    # 30 s. Firmware curve + thermald handle cooling on this model.
    thinkfanEnable = false;
    # Only the NAS backup share. LAPTOP_A's two DESK Games mounts are dropped:
    # nothing here uses them, and with DESK off (or in Windows) the KDE file
    # picker walks into the automount, waits 15 s per attempt and retries —
    # VS Code's "Open Folder" froze and xdg-desktop-portal-kde dumped core
    # (measured 2026-09-30).
    nfsMounts = builtins.filter (m: m.where == "/mnt/NFS_Backups") laptopA.systemSettings.nfsMounts;
    nfsAutoMounts = builtins.filter (m: m.where == "/mnt/NFS_Backups") laptopA.systemSettings.nfsAutoMounts;
    # No Minecraft here: UHD 620 + i5-8250U cannot run the AkuCraft packs at a
    # playable rate. Aga plays on DESK_A / LAPTOP_A.
    freesmLauncherEnable = false;
    # LUKS UUID of encrypted swap partition (from: sudo cryptsetup luksDump /dev/nvme0n1p2)
    hibernateSwapLuksUUID = "1fbdeb58-e07a-4c7b-81db-d72067ae12cb";
  };
}
