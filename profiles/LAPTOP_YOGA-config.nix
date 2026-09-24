# LAPTOP_YOGA Profile Configuration (nixosyogaaga)
# Lenovo ThinkPad X380 Yoga, Aga's second laptop.
#
# Inherits ALL of LAPTOP_A (software, services, backups, updates, Plasma power
# management, Claude/Plane setup) so the two machines behave the same and cannot
# drift apart. This file holds ONLY what differs: the hardware, and the machine's
# identity (hostname, IPs, metrics label). A software change for Aga's laptops
# goes into LAPTOP_A-config.nix and reaches both.
#
# Pending until the machine has joined the tailnet (its 100.64.x IP is assigned
# by Headscale on first login, it cannot be known before):
#   - NAS_PROD export of /mnt/ssdpool/workstation_backups for its tailnet IP
#     (home backup to NAS fails until then), and ~/myScripts/restic.key on it
#   - DESK exports of the two Games shares (ro) for its tailnet IP
#   - prometheus-nas-backup.nix: add nixosyogaaga/home.restic only AFTER the
#     first backup landed (nas_backup_status == 0 alerts on a missing repo)

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
    # LUKS UUID of encrypted swap partition (from: sudo cryptsetup luksDump /dev/nvme0n1p2)
    hibernateSwapLuksUUID = "1fbdeb58-e07a-4c7b-81db-d72067ae12cb";
  };
}
