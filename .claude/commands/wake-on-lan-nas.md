# Wake-on-LAN NAS

Wake NAS from sleep or check its status. Also supports suspending NAS with scheduled RTC wake.

## Instructions

When this command is invoked, run the WOL script from the dotfiles repo:

```bash
bash /home/akunito/.dotfiles/scripts/nas-wol.sh
```

### Arguments

- If the user wants to **wake** NAS (default): no args
- If the user wants to **check** if NAS is reachable: pass `--check`
- If the user wants to **suspend** NAS until 11:00 tomorrow: pass `--suspend`
- If the user wants to **suspend for N seconds** (testing): pass `--suspend-for <seconds>`

### How WOL Works

1. Sends a Wake-on-LAN magic packet to NAS RTL8125B NIC (MAC: `10:ff:e0:02:ad:9a`)
2. Tries multiple methods: `wakeonlan` tool, pfSense `wol` command, `etherwake`
3. Retries 3 times with 5-second intervals
4. Verifies NAS responds to ping

### Known Limitation: WOL from S3 is Unreliable

The Linux `r8169` kernel driver for RTL8125B does NOT reliably support WOL from S3 (suspend-to-RAM).
The driver takes the NIC link down during suspend, preventing magic packet reception.

**Reliable wake methods:**
- **RTC alarm** (scheduled wake via `rtcwake`) — always works
- **Physical power button** — always works
- **WOL from S5** (full power-off) — may work, untested

The `--suspend` command uses `rtcwake` for guaranteed wake at 11:00 the next day.
WOL is provided as a best-effort on-demand wake mechanism.

### Network Topology

| Component | Detail |
|-----------|--------|
| WOL NIC | RTL8125B (enp10s0), MAC: `10:ff:e0:02:ad:9a` |
| Switch port | USW-24-G2 port 23, LAN VLAN (192.168.8.x) |
| Primary NIC | bond0 (Intel X520 SFP+), IP: 192.168.20.200 |
| WOL broadcast | 192.168.8.255 (LAN broadcast) |
| pfSense WOL | `ssh admin@192.168.8.1 "wol -i 192.168.8.255 10:ff:e0:02:ad:9a"` |

### Prerequisites

- Must be on the same LAN as NAS (or have SSH access to pfSense)
- `wakeonlan` tool available (via `nix-shell -p wakeonlan` or system package)
- SSH access to pfSense (`admin@192.168.8.1`) for relay WOL

### NAS Sleep Schedule (Phase 8)

NAS follows a sleep schedule:
- **Awake**: 11:00 - 23:00 daily
- **Suspended**: 23:00 - 11:00 (S3 suspend-to-RAM, RTC alarm wake)
- Pools remain unlocked in RAM during S3 (no re-unlock needed)
- Docker services resume automatically after wake

### Post-Wake Verification

After NAS wakes, verify services:
```bash
ssh akunito@192.168.20.200 "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

Expected: 19 containers running (tailscale, cloudflared, npm, media stack, homelab, exporters, uptime-kuma).

### Related

- [Unlock NAS](./unlock-truenas.md) - Only needed after full reboot, not after S3 resume
- [Docker Startup NAS](./docker-startup-truenas.md) - Start Docker services (auto-resume after S3)
- [Manage NAS](./manage-truenas.md) - General NAS management
