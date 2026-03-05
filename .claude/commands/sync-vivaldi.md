---
name: sync-vivaldi
description: Sync Vivaldi browser config between DESK and LAPTOP_X13
allowed-tools: Bash, AskUserQuestion
---

# Sync Vivaldi Config

Syncs the Vivaldi browser profile (extensions, sidebar, workspaces, settings) between machines using rsync.

## Usage

```bash
/sync-vivaldi [direction]
```

## Parameters

- `direction` (optional): `desk-to-laptop` (default) or `laptop-to-desk`

## Prerequisites

- **Close Vivaldi on BOTH machines** before syncing
- Both machines must be on the same network
- SSH access between machines

## Machine Details

| Machine | Profile | Ethernet IP | WiFi IP |
|---------|---------|-------------|---------|
| DESK | DESK | 192.168.8.96 | — |
| LAPTOP_X13 | LAPTOP_X13 | 192.168.8.92 | 192.168.8.91 |

## Implementation

When invoked:

1. **Ask the user** to confirm Vivaldi is closed on both machines
2. **Determine direction** from argument (default: DESK → LAPTOP_X13)
3. **Verify connectivity** — try ethernet IP first (.92), fall back to wifi (.91) for laptop
4. **Run rsync** with the following excludes (caches that regenerate automatically):
   - `Service Worker/`, `IndexedDB/`, `GPUCache/`, `DawnGraphiteCache/`, `DawnWebGPUCache/`
   - `CdmStorage*`, `Cache/`, `Code Cache/`, `blob_storage/`
   - `*-journal`, `DIPS*`, `Cookies*`, `*.log`

### DESK → LAPTOP_X13

```bash
LAPTOP_IP="192.168.8.92"  # or .91 if .92 unreachable
rsync -avz \
  --exclude='Service Worker/' --exclude='IndexedDB/' \
  --exclude='GPUCache/' --exclude='DawnGraphiteCache/' \
  --exclude='DawnWebGPUCache/' --exclude='CdmStorage*' \
  --exclude='Cache/' --exclude='Code Cache/' \
  --exclude='blob_storage/' --exclude='*-journal' \
  --exclude='DIPS*' --exclude='Cookies*' --exclude='*.log' \
  ~/.config/vivaldi/Default/ \
  akunito@${LAPTOP_IP}:~/.config/vivaldi/Default/
```

### LAPTOP_X13 → DESK

```bash
LAPTOP_IP="192.168.8.92"  # or .91 if .92 unreachable
rsync -avz \
  --exclude='Service Worker/' --exclude='IndexedDB/' \
  --exclude='GPUCache/' --exclude='DawnGraphiteCache/' \
  --exclude='DawnWebGPUCache/' --exclude='CdmStorage*' \
  --exclude='Cache/' --exclude='Code Cache/' \
  --exclude='blob_storage/' --exclude='*-journal' \
  --exclude='DIPS*' --exclude='Cookies*' --exclude='*.log' \
  akunito@${LAPTOP_IP}:~/.config/vivaldi/Default/ \
  ~/.config/vivaldi/Default/
```

5. **Report** number of files transferred and total size

## Notes

- This overwrites the destination with the source — it does NOT merge
- Cookies and sessions are excluded to avoid login conflicts
- Extensions and their data are included (~160 MB)
- Bookmarks, settings, sidebar config, workspaces, and web panels are all included
- The backup directory `Default.BAK.*` on the laptop can be cleaned up manually if the sync works well
