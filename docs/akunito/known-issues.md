---
id: akunito.known-issues
summary: Out-of-scope bugs and stale code surfaced during other work — to fix later
tags: [bugs, tech-debt, backlog]
date: 2026-05-14
status: published
---

# Known Issues & Tech Debt Backlog

Bugs and stale-code findings surfaced as side-effects of other work. Each item
notes when it was found and roughly how to reproduce. Triage and fix on its own
schedule — none are blocking.

## NAS backup monitoring: status=0 for all datasets (pre-existing)

**Found**: 2026-05-14, during the TrueNAS→NAS rename deploy prep.

**Symptom**: On VPS_PROD, the textfile `/var/lib/prometheus-node-exporter/textfile/nas_backup.prom`
(formerly `truenas_backup.prom`) reports `nas_backup_status{dataset=...} 0` for
all five datasets (`vps_databases`, `vps_services`, `vps_nextcloud`, `desk_home`,
`x13_home`). Only `backup_repo_size_bytes` reports non-zero values for
`offsite_configs` / `offsite_data`.

**Effect**: The Prometheus metric `nas_backup_age_seconds` returns zero series.
The `NasBackupMissing` alert in `grafana.nix` (`backup_alerts` group) would fire
critical on `nas_backup_status == 0` if it were not silenced (currently has
`for=15m` — check whether it's been firing).

**Likely root cause** in `system/app/prometheus-nas-backup.nix:73-85`:

```bash
RESULT=$(ssh ... "sudo find $REPO_PATH/snapshots/ -maxdepth 1 -type f -printf '%T@\n' ... ; sudo du -sb $REPO_PATH ...")
NEWEST_TS=$(echo "$RESULT" | grep '^NEWEST=' | cut -d= -f2)
```

`sudo find` and `sudo du` on the new NixOS NAS may be:
1. Failing on `akunito` lacking NOPASSWD sudo for those commands (sudoers
   currently only grants NOPASSWD for systemctl-suspend/hibernate/restic per
   `system/security/sudo.nix:4-20`)
2. Or `pam_ssh_agent_auth` not authenticating because the script's SSH command
   uses `-o BatchMode=yes` without `-A` agent forwarding
3. Or the snapshot path layout on the new NAS differs from TrueNAS (restic
   snapshot dirs may not be where the script expects)
4. Or the `2>/dev/null` mask is swallowing the error invisibly

**Repro**: On VPS_PROD, run the renamed script manually and watch for
errors:
```bash
ssh -A -p 56777 akunito@100.64.0.6 'sudo systemctl start prometheus-nas-backup.service && journalctl -u prometheus-nas-backup.service -n 50 --no-pager'
```

**Recommendation**: Drop the `2>/dev/null` muzzles from the script to surface
the real SSH/sudo failure. If sudo is the issue, add a NOPASSWD rule for
`/run/current-system/sw/bin/find /mnt/extpool/vps-backups/* /mnt/ssdpool/workstation_backups/*`
and `du` on those paths on `NAS_PROD`. Or — cleaner — move the snapshot-timestamp
producer to run on the NAS itself (like `nas-zfs-pool-metrics`) writing a
textfile, eliminating the SSH dependency entirely.

## NAS API port (9443) likely dead after NixOS migration

**Found**: 2026-05-14, during `restic-backup-nas.nix` audit.

**Symptom**: The configs-backup job calls
`POST https://${nasHost}:${nasApiPort}/api/v2.0/config/save` (`restic-backup-nas.nix:177-184`).
This is the TrueNAS SCALE web UI / API endpoint. NixOS NAS doesn't serve it.

**Effect**: Each daily run logs `WARNING: NAS config API call failed (non-fatal)`
and stops generating `truenas-config-YYYYMMDD.tar` files in the configs staging
directory. Rest of the configs job (rsync of `/mnt/ssdpool/docker/compose/`)
still runs, so the offsite backup still has docker-compose snapshots — but the
NAS system-config export is missing.

**Repro**: On VPS_PROD:
```bash
ssh -A -p 56777 akunito@100.64.0.6 'sudo ss -tlnp | grep :9443'
# Empty output = port not listening = feature is dead
```

**Recommendation**: Either remove the API-export block from `restic-backup-nas.nix`
and the corresponding flags (`nasResticBackupApiKeyFile`, `nasResticBackupApiPort`),
or replace it with a NixOS-native equivalent (e.g. `nixos-rebuild dry-build`
output capture, or just `nix flake archive` of the NAS profile).

## `docs/akunito/infrastructure/services/nas.md` monitoring section is broadly stale

**Found**: 2026-05-14, during the TrueNAS→NAS rename.

**Symptom**: The "Monitoring & Alerting" and "Manual Operations" sections of
`nas.md` describe the pre-AINF-336 TrueNAS SCALE deployment:
- `~/.local/bin/truenas-zfs-exporter.sh` user script + user timer
- `midclt call pool.scrub`, `midclt call service.restart`, `midclt call disk.query`
- TrueNAS API endpoints
- `secrets/truenas-api-key.txt`

None of those exist or work on the current NixOS NAS.

A STALE banner was added (commit `ff96887`) pointing readers at the current
state, but the operational sections weren't rewritten — those commands will
fail on the new NAS.

**Recommendation**: A focused rewrite pass on the Monitoring + Manual Operations
sections of `nas.md`. Replace `midclt`-based recipes with direct `zpool`/`zfs`
SSH commands. Drop the `~/.local/bin/truenas-zfs-exporter.sh` references — that
script never existed as a Nix-managed user script anyway.

## `prometheus-graphite.nix` is dormant — could be archived

**Found**: 2026-05-13, during TrueNAS naming cleanup.

**Status**: Gutted of TrueNAS-specific service/scrape/alerts in commit `f0ab8d4`.
The remaining ~155 lines are just a Graphite-exporter shell with TrueNAS-flavoured
mapping rules (e.g. line 121: `name = "truenas_zfspool_${2}"`). The file is
imported only on profiles with `prometheusGraphiteEnable = true`, and no current
profile sets that flag (only `profiles/archived/LXC_monitoring-config.nix` did,
and it's archived).

**Recommendation**: After a grace period, move `system/app/prometheus-graphite.nix`
to `system/app/archived/` (or delete outright) and drop the gated imports in
`profiles/vps/base.nix:36` and `profiles/proxmox-lxc/base.nix:37`. Resurrect from
git history if a future Graphite producer ever needs it.

## Stale `servers_truenas_*` series in Prometheus TSDB

**Found**: 2026-05-14, during pre-deploy snapshot.

**Symptom**: `curl 'localhost:9090/api/v1/label/__name__/values'` on VPS_PROD
still returns ~hundreds of `servers_truenas_smart_log_*`, `servers_truenas_truenas_*`,
`servers_truenas_zfs_*` metric names — produced by the long-gone TrueNAS SCALE
Graphite reporter.

**Effect**: Label-value autocomplete in Grafana is noisy; storage is wasted on
historical data nobody queries. No active scraper produces these, so no new
data is being ingested.

**Recommendation**: Either wait for Prometheus retention (default 15d) to age
them out naturally, or run a one-off `delete_series` admin API call to purge
matching series:
```bash
ssh -A -p 56777 akunito@100.64.0.6 \
  'curl -X POST -g "localhost:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~\"servers_truenas.*\"}"'
```
(Requires `--storage.tsdb.retention.time` admin API enabled.)

## Voxtype input pinned to old rev — upstream regression

**Found**: 2026-05-13, during OBS install Home Manager apply.

**Symptom**: After `nix flake update` bumped voxtype from
`adf0ea62c2310b90c55febdc6515cca9f264e25a` (2026-04-20) to
`ddc93de3d387a55982813ead3777a129285deaef` (2026-05-11), the build failed
with:

```
thread 'main' panicked at /build/cargo-vendor-dir/x11-2.21.0/build.rs:42:14:
called `Result::unwrap()` on an `Err` value: pkg-config exited with status code 1
The system library `x11` required by crate `x11` was not found.
```

**Workaround in repo**: `flake.nix` pins voxtype to the working
2026-04-20 rev:

```nix
voxtype = {
  url = "github:peteonrails/voxtype/adf0ea62c2310b90c55febdc6515cca9f264e25a";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Effect**: Voxtype works on DESK / any host with `voxtypeEnable = true`,
but stays frozen at the 2026-04-20 release until the upstream Rust build
inputs are fixed (likely needs `xorg.libX11` added to the package's
`buildInputs`/`nativeBuildInputs` via `pkg-config`).

**Recommendation**: Periodically check upstream
https://github.com/peteonrails/voxtype/commits/main for a fix that adds
`xorg.libX11` to the Nix package. When found:

```bash
cd ~/.dotfiles
# Remove the explicit rev from flake.nix voxtype input:
#   url = "github:peteonrails/voxtype";
nix flake update voxtype
# Test build, then commit
```

If upstream stays broken long-term, consider forking voxtype with the
fix patched in (low maintenance burden — single `buildInputs` addition).

## LAPTOP_A profile eval fails locally on DESK

**Found**: 2026-05-14, during pre-deploy multi-profile eval.

**Symptom**: `nix eval --impure '.#nixosConfigurations.LAPTOP_A.config.system.build.toplevel.drvPath'`
on DESK fails with `error: path '/home/aga/.certificates/ca.cert.pem' does not exist`.

**Effect**: Can't eval-check LAPTOP_A from DESK before deploying. Doesn't affect
LAPTOP_A's own builds (which run with `/home/aga` actually populated).

**Recommendation**: Wrap the cert path in `lib.optionalPath` or guard
`pkiCertificates` so missing files don't blow up eval on machines where the
profile doesn't apply. Pattern already used in `pkiCertificates` for DESK
(`profiles/DESK-config.nix:69`).
