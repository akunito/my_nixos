# Plan: Migrate EmulatorJS to RomM on TrueNAS

## Context

The current `linuxserver/emulatorjs` (v1.9.2) is **deprecated** (archived July 2025), has no search/filter UI (unusable with 10,000+ ROMs), and arcade games are stuck at "Loading Bios: 100%" due to a corrupt `samples.zip` BIOS download. Migration to a modern, actively maintained alternative is needed.

**Chosen alternative: [RomM](https://github.com/rommapp/romm)** (ROM Manager)
- Actively maintained (last update: Feb 2026)
- Excellent search/filter UI with smart collections
- 400+ platform support including arcade/MAME
- Built-in EmulatorJS integration for browser-based play
- Official TrueNAS support with documentation
- Multi-source metadata enrichment (IGDB, MobyGames, ScreenScraper)

## Current State

- **Container**: `emulatorjs` in `/mnt/ssdpool/docker/compose/homelab/docker-compose.yml`
- **ROM data**: `/mnt/ssdpool/emulators/EmulatorsData/` (55 GB, 29 platform dirs)
- **Container config**: `/mnt/ssdpool/docker/emulatorjs/`
- **Ports**: 3000 (frontend), 3002 (management)
- **NPM domain**: `emulatorjs.local.akunito.com` -> port 3000
- **Startup script**: `scripts/truenas-docker-startup.sh` (starts `emulatorjs` explicitly)
- **Disk space**: 2.8 TB available on ssdpool (1% used)

## ROM Directory Restructuring

RomM expects: `library/roms/{platform}/{game_files}` and `library/bios/{platform}/`

**Platforms with actual ROMs** (13 platforms, focus of migration):

| Current (EmulatorJS) | RomM Platform Name | ROMs | Rename Needed? |
|---------------------|-------------------|------|----------------|
| `arcade/roms/` | `arcade` | 10,344 | No |
| `nes/roms/` | `nes` | 1,244 | No |
| `snes/roms/` | `snes` | 1,041 | No |
| `gba/roms/` | `gba` | 927 | No |
| `gbc/roms/` | `gbc` | 529 | No |
| `n64/roms/` | `n64` | 459 | No |
| `segaGG/roms/` | `game-gear` | 369 | **Yes** |
| `segaMS/roms/` | `master-system` | 319 | **Yes** |
| `atari5200/roms/` | `atari-5200` | 202 | **Yes** |
| `ngp/roms/` | `neo-geo-pocket` | 182 | **Yes** |
| `jaguar/roms/` | `jaguar` | 139 | No |
| `nds/roms/` | `nds` | 101 | No |
| `segaSG/roms/` | `sg-1000` | 81 | **Yes** |

**Strategy**: Create new `romm-library/` tree with `mv` operations (instant rename, same ZFS dataset, no data copy). Preserve old EmulatorsData structure as-is (just create new symlinks or moves for the roms/ subdirs).

---

## Implementation Steps

### Step 1: Create RomM library structure (on TrueNAS)

Run a migration script on TrueNAS that:
1. Creates `/mnt/ssdpool/emulators/romm-library/roms/` and `/mnt/ssdpool/emulators/romm-library/bios/`
2. For each platform: creates `romm-library/roms/{romm-platform-name}/`
3. Moves (or symlinks) the ROM files from `EmulatorsData/{platform}/roms/*` into the new structure
4. Moves BIOS files similarly

Using symlinks to the original `roms/` directories to avoid data duplication:
```bash
ln -s /mnt/ssdpool/emulators/EmulatorsData/arcade/roms /mnt/ssdpool/emulators/romm-library/roms/arcade
ln -s /mnt/ssdpool/emulators/EmulatorsData/segaGG/roms /mnt/ssdpool/emulators/romm-library/roms/game-gear
# etc.
```

### Step 2: Create RomM data directories

```bash
sudo mkdir -p /mnt/ssdpool/docker/romm/{resources,assets,config}
sudo mkdir -p /mnt/ssdpool/docker/romm-db
```

### Step 3: Add RomM + MariaDB to homelab docker-compose.yml

Add `romm-db` (MariaDB 10) and `romm` (rommapp/romm:latest) services:
- RomM on port `8085:8080`
- MariaDB with health check
- Volumes: romm-library mounted at `/romm/library`
- Generate DB password and auth secret key
- IGDB metadata: configure `IGDB_CLIENT_ID` and `IGDB_CLIENT_SECRET` (user will provide Twitch Developer API credentials)
- Memory limits: 512M for MariaDB, 2G for RomM

### Step 4: Start RomM and verify basic functionality

```bash
cd /mnt/ssdpool/docker/compose/homelab
sudo docker compose up -d romm-db romm
```
Access `http://192.168.20.200:8085`, create admin account, configure IGDB credentials, trigger ROM scan.

### Step 5: Update NPM proxy

Repoint `emulatorjs.local.akunito.com` -> `romm:8080` (reuse existing domain, no DNS changes needed).

### Step 6: Update startup script

Edit `scripts/truenas-docker-startup.sh`:
- Replace `emulatorjs` with `romm romm-db` in the homelab startup section

### Step 7: Test arcade ROMs in RomM

After scan, test arcade games. If they still fail (MAME ROM set compatibility), debug separately — the issue may be the ROM set version, not the BIOS.

### Step 8: Decommission old EmulatorJS (after validation)

Once RomM is confirmed working:
1. `sudo docker compose stop emulatorjs`
2. Comment out or remove emulatorjs service from compose
3. Keep EmulatorsData as archive/backup

---

## Files to Modify

| File | Change |
|------|--------|
| `/mnt/ssdpool/docker/compose/homelab/docker-compose.yml` | Add romm + romm-db services |
| `scripts/truenas-docker-startup.sh` | Replace emulatorjs with romm + romm-db |
| NPM web UI | Update/create proxy host for romm |
| `docs/akunito/infrastructure/services/truenas-services.md` | Update service inventory |

## Verification

1. RomM UI accessible at `http://192.168.20.200:8085`
2. ROM scan discovers all 13 platforms with ROMs
3. Search/filter works across 15,000+ ROM library
4. Console game plays in browser (e.g., SNES game)
5. Arcade game test (e.g., Ms. Pac-Man) — may still fail if ROM set issue
6. `sudo docker logs romm --tail 50` shows no errors

## Rollback

- Original `EmulatorsData/` preserved (symlinks only, no data moved)
- EmulatorJS container still in compose (just stopped)
- Config backup at `arcade.json.bak`
- Remove romm containers + romm-library symlinks to revert
