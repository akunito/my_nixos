# Unlock TrueNAS Encrypted Datasets

Unlock encrypted ZFS datasets on TrueNAS after a reboot or when datasets are locked.

## Instructions

When this command is invoked, run the unlock script from the dotfiles repo:

```bash
bash /home/akunito/.dotfiles/scripts/truenas-unlock-pools.sh
```

### Arguments

- If the user specifies a pool name (e.g., `/unlock-truenas hddpool`), pass it: `--pool hddpool`
- If the user asks for status only, pass `--status`
- If the user asks for a dry run, pass `--dry-run`

### Prerequisites

- Must be run from a machine with access to VLAN 100 (storage network) — typically **DESK** (192.168.20.96)
- `secrets/truenas-api-key.txt` and `secrets/truenas-encryption-passphrase.txt` must be available (git-crypt unlocked)

### What It Does

1. Checks API connectivity and secrets availability
2. Queries all encrypted datasets for lock status
3. Unlocks locked datasets using the passphrase via TrueNAS API
4. Waits for unlock jobs to complete
5. Verifies and reports final status

### Manual Alternative (if script is unavailable)

```bash
# Check lock status via SSH
ssh truenas_admin@192.168.20.200 'midclt call pool.dataset.query' | python3 -c '
import json, sys
for ds in json.load(sys.stdin):
    if ds.get("encrypted"):
        print(f"{ds[\"id\"]}: locked={ds.get(\"locked\")}")
'

# Unlock via API (per pool)
API_KEY=$(cat secrets/truenas-api-key.txt | tr -d '\n')
PASSPHRASE=$(cat secrets/truenas-encryption-passphrase.txt | tr -d '\n')

curl -sk -X POST "https://192.168.20.200/api/v2.0/pool/dataset/unlock" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"hddpool\",
    \"unlock_options\": {
      \"recursive\": true,
      \"datasets\": [
        {\"name\": \"hddpool/media\", \"passphrase\": \"$PASSPHRASE\"},
        {\"name\": \"hddpool/proxmox_backups\", \"passphrase\": \"$PASSPHRASE\"},
        {\"name\": \"hddpool/ssd_data_backups\", \"passphrase\": \"$PASSPHRASE\"}
      ]
    }
  }"
```

### Deploying Script to TrueNAS (optional)

The script can also be deployed to TrueNAS for local execution:

```bash
scp scripts/truenas-unlock-pools.sh truenas_admin@192.168.20.200:/home/truenas_admin/
# Then on TrueNAS: bash /home/truenas_admin/truenas-unlock-pools.sh --status
```

Note: On TrueNAS the secrets paths won't exist, so the script is designed to run from DESK where the dotfiles repo has git-crypt unlocked.

### Related

- [TrueNAS Service Docs](../../docs/akunito/infrastructure/services/truenas.md)
- [Manage TrueNAS](./manage-truenas.md) - General TrueNAS management
- [ZFS Replication Script](../../scripts/truenas-zfs-replicate.sh)
