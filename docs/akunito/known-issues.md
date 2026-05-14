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

## ~~NAS backup monitoring: status=0 for all datasets~~ — FIXED 2026-05-14

**Resolved by commits `65a9f09` + `6b9776c`** (drop sudo + use restic SSH key).

**Original symptom**: `nas_backup_status` was `0` for all 5 datasets; the alert
`NasBackupMissing` was firing.

**Actual root cause** (revealed once the script's outer `2>/dev/null` was
removed): the SSH command had no `-i` keyfile and the systemd service runs
without an SSH agent, so authentication to the NAS failed with
`Permission denied (publickey,keyboard-interactive)`. The mistaken initial
diagnosis (sudo) was wrong; restic repos are owned `akunito:users` on the NAS
and don't need sudo at all.

**Fix applied**:
1. Drop `sudo` from `find`/`du` in `prometheus-nas-backup.nix:73-74`
2. Add `-i /home/akunito/.ssh/id_ed25519_restic` to `SSH_OPTS` (reusing the key
   already authorized for `restic-backup-nas.nix`)
3. Remove the outermost `2>/dev/null` so future SSH failures surface in the
   service journal

**Verified**: all 5 datasets now report `status=1` with real ages + sizes.
`NasBackupMissing` resolved from `firing` to `inactive`.

## vps_nextcloud backup is unhealthy — tiny repo + 3.5d stale (NEW 2026-05-14)

**Found**: 2026-05-14, immediately after the NasBackupMissing fix
(commit `6b9776c`) made monitoring functional.

**Symptom**: `backup_repo_size_bytes{dataset="vps_nextcloud",direction="vps_to_nas"} 4955`
— a 5 KB restic repo. By contrast, `vps_databases` is 10 GB, `vps_services`
is 272 GB. And `nas_backup_age_seconds{dataset="vps_nextcloud"}` is ~84 h
(3.5 days), already over the 36 h threshold of `NasVpsBackupStale`.

**Effect**: Nextcloud data backup to NAS is either broken, silently failing,
or the wrong path is being read. Alert `NasVpsBackupStale` will fire critical
once its 1 h `for` countdown elapses (~09:50 today).

**Hypothesis**: One of:
1. The nextcloud restic push timer on VPS isn't actually running (or its
   `vpsResticBackupEnable`-derived service is failing silently).
2. The snapshot path on the NAS for nextcloud changed and the monitor reads
   the wrong dir, returning age but missing real snapshot files.
3. Nextcloud data is being excluded from the backup by some filter / exclude
   rule that bypasses the actual data dirs.

**Repro**:
```bash
ssh -A -p 56777 akunito@100.64.0.6 'systemctl list-timers --no-pager | grep -i nextcloud'
ssh -A -p 56777 akunito@100.64.0.6 'systemctl status vps-restic-nextcloud.service 2>&1 | head -20'
ssh -A akunito@192.168.20.200 'ls -la /mnt/extpool/vps-backups/nextcloud.restic/snapshots/ && du -sh /mnt/extpool/vps-backups/nextcloud.restic'
```

**Recommendation**: Investigate the nextcloud push service on VPS_PROD. The
restic-backup-vps.nix module + its vpsResticTargets list. Compare to the
working `vps_databases` and `vps_services` flows.

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

## Deploy-time evaluation warnings (collected during AINF deploys)

Warnings surfaced by `nix eval` / `nixos-rebuild` during deploys. Each lives
in upstream code that has since changed but our config still calls the old
names/options. None blocks builds — fix opportunistically.

### `'claude-code-bin' has been merged into 'claude-code'`

**Seen on**: LAPTOP_X13 deploy 2026-05-14.

**Cause**: nixpkgs deprecated the `claude-code-bin` package in favour of
unified `claude-code`. Our config still references `claude-code-bin` somewhere
(likely `user/app/claude-code/` or `user/packages/`).

**Recommendation**: grep the repo for `claude-code-bin`, replace with
`claude-code`. Confirm with `nix eval` that the warning is gone.

### `xdg.userDirs.setSessionVariables` default changed from `true` to `false`

**Seen on**: LAPTOP_X13 deploy 2026-05-14, NAS_PROD deploy 2026-05-14.

**Cause**: Home Manager option default flipped. Our config implicitly relied
on the old `true` default; under the new default, session env vars like
`XDG_DOCUMENTS_DIR` won't be exported to children.

**Recommendation**: explicitly set `xdg.userDirs.setSessionVariables = true;`
in the relevant Home Manager module (search for `xdg.userDirs` to find where
we already configure it) to keep the legacy behaviour. Or migrate consumers
to read `.config/user-dirs.dirs` directly.

## Stylix theming forces large source rebuilds on every deploy

**Found**: 2026-05-14, during LAPTOP_X13 deploy.

**Symptom**: Each `install.sh` on a desktop/laptop profile rebuilds
Thunderbird, Bitwarden, KDE libs (kio, kwallet, gcr, gnupg-gnupg-gnome-keyring),
Cursor IDE, RetroArch, and any other theme-able package from source —
dozens of minutes of CPU. Server profiles (VPS_PROD, NAS_PROD) don't suffer
because they don't pull theme-able GUI packages.

**Cause**: `stylixEnable = true` in `LAPTOP-base.nix:18` (and DESK's profile)
adds a system overlay that re-themes packages with our local Base16 color
scheme. The overlay changes the build inputs, so the store hash differs from
what Hydra published → no binary cache → source build.

**Trade-off**: this is by design — system-wide colour consistency vs. fast
deploys. Disabling Stylix would speed up deploys dramatically.

**Recommendation (if deploy time becomes painful)**: Two options:
1. Set up a **private nix binary cache** (e.g. via `nix-serve` on NAS_PROD or
   VPS_PROD) — first deploy to one host populates it, subsequent deploys to
   other hosts pull from it. Avoids re-themeing every host.
2. **Scope Stylix to user-level only** (Home Manager Stylix instead of NixOS
   Stylix). Cuts the system-overlay rebuild explosion, theming still applies
   to GTK/Qt via env vars and ~/.config files.

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
