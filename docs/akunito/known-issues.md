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

## ~~vps_nextcloud backup is unhealthy — tiny repo + 3.5d stale~~ — FIXED 2026-05-14

**Resolved by commit `b813ad2`** (anchor exclude patterns to source root) + the
imperative ACL grant on `/var/lib/nextcloud-data`.

**Actual root cause** (took a long triage to find): hypothesis #3 from the
original entry — exclude pattern misconfiguration. The Nextcloud excludes
in `restic-backup-vps.nix` were unanchored:

```nix
excludes = [
  "*/3rdparty/*" "*/apps/*" "*/core/*" "*/dist/*"
  "*/lib/*"        # <-- THIS pattern
  "*/themes/*" ...
];
```

Restic's glob `*` does not cross `/`, so `*/lib/*` matches any 3-segment path
of shape `*/lib/*`. The literal path `/var/lib/nextcloud-data` IS such a path
(`/var/lib/nextcloud-data` = `/<*>/lib/<*>`). So restic excluded the entire
source dir before walking into it, producing 0-byte snapshots since the
backup was first set up — months of empty offsite backups for ~150 GB of
real Nextcloud user data.

**Sequence of discovery** (so we know what NOT to repeat):
1. Saw 5 KB repo size + 0-files restic output and assumed permission issue.
2. Tried `AmbientCapabilities=CAP_DAC_READ_SEARCH` — didn't help because
   restic uses `access(2)` for permission probing, which by POSIX ignores
   capabilities for non-root users (restic issues #2447, #2563).
3. Bypassed the `/run/wrappers/bin/restic` wrapper (it's a "privileged file"
   and clears ambient caps) — still 0 files.
4. Applied a real DAC ACL on the source dir (`setfacl -R -m u:akunito:rX`) —
   `find`/`du`/`test -r` from akunito now all worked, but restic STILL
   reported 0 files.
5. Tried `--no-scan` — also didn't fix it on its own.
6. Ran `restic backup /var/lib/nextcloud-data/data` (different path) — found
   120k files. Then ran `restic backup /var/lib/nextcloud-data --no-scan`
   (verbose=2) and saw real files. Both succeeded because the offending
   exclude only collided with the parent path string `/var/lib/nextcloud-data`.
7. Re-read the deployed script and spotted `--exclude "*/lib/*"`. End of
   triage.

**What stayed in place after the fix**:
- ACL grant on `/var/lib/nextcloud-data` is still required and useful — without
  it, akunito couldn't enter `data/` (mode 770 owned UID 100032), and even
  with the exclude-fix the user data wouldn't be backed up. ACL was applied
  imperatively; xattrs persist on disk.

**Lessons for future restic exclude rules**:
- Always anchor exclude patterns to the absolute source path (e.g.
  `/var/lib/nextcloud-data/foo/*` not `*/foo/*`).
- Add a smoke test: any non-trivial backup config should be tagged-tested
  against expected file count before going to production.
- `--verbose=2` in restic prints per-file decisions and would have revealed
  the empty walk much faster than the default `--verbose` summary.

**Verified result**: 90,832 files / 95.208 GiB processed; 74.214 GiB added to
the repo (72.730 GiB stored after restic dedup). `nas_backup_status=1`,
`nas_backup_age_seconds=23s` post-fix.

**Follow-up** (low priority): add a `systemd.tmpfiles.rules` entry for the
ACL so it's declaratively reinforced. Currently applied imperatively only.

## ~~nas-backup-data: silent rsync "permission denied" on UID-mapped paths~~ — FIXED 2026-05-14

**Resolved by commits `db34ef2` + `14ebcec`**.

1. Enabled POSIX ACLs on the ZFS dataset (`zfs set acltype=posixacl ssdpool/docker`)
   — was `acltype=off`, prevented any `setfacl` operations.
2. Granted akunito read access on the LetsEncrypt cert tree:
   `setfacl -R -m u:akunito:rX + default ACL on /mnt/ssdpool/docker/compose/npm/letsencrypt`.
   Cert tree now backed up (verified: 27 files / 184 K in the staging tree).
3. Added explicit excludes for container-internal regenerable junk in the
   `mediarr` rsync call: calibre `.XDG/.cache/.dbus/pulse`, calibre fonts +
   plugins config, and the full `qbittorrent/qBittorrent/logs/` dir.
4. Added a metric `nas_offsite_backup_rsync_warnings{job}` that counts
   non-fatal rsync errors per run, plus a Prometheus alert
   `NasOffsiteBackupRsyncWarnings` that fires on `> 0` for 15m. Future
   silent coverage gaps will now surface in alerting.

**Verified**: post-fix run reports `rsync warning count: 0`. LetsEncrypt
cert tree confirmed present in the restic staging dir.

## ~~Declarative ACL re-application (was an open follow-up)~~ — FIXED 2026-05-14

**Resolved by commit `62e1178`**. Two idempotent oneshot systemd services
re-apply the POSIX ACL grants on every boot, so backup pipelines survive
container teardown + recreate cycles:

- `vps-backup-source-acls.service` (VPS_PROD, in `restic-backup-vps.nix`)
  applies `setfacl -R u:akunito:rX + default ACL` on `/var/lib/nextcloud-data`.
  Wired as a `Before=vps-restic-nextcloud.service` dependency so the ACL
  is always in place before the weekly backup fires.
- `nas-backup-source-acls.service` (NAS_PROD, in `nas-services.nix`) ensures
  ZFS `acltype=posixacl` on `ssdpool/docker`, then applies the same ACL
  pattern on `/mnt/ssdpool/docker/compose/npm/letsencrypt`.

Disaster-recovery test verified: stripping the VPS ACL with `setfacl -b`,
then restarting the service, restores the grant fully. Both services run
unconditionally at boot via `wantedBy = [ "multi-user.target" ]`.

## ~~NAS API port (9443) likely dead after NixOS migration~~ — FIXED 2026-05-14

**Resolved by commit `1125709`**. Verified port 9443 is not listening on the
NixOS NAS, then removed the entire config-export block from
`restic-backup-nas.nix` plus the now-unreferenced `nasResticBackupApiKeyFile`
and `nasResticBackupApiPort` defaults.

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

## ~~`prometheus-graphite.nix` is dormant — could be archived~~ — FIXED 2026-05-14

**Resolved by commit `1125709`**. File moved to `system/app/archived/`; the
two gated import lines in `profiles/vps/base.nix` and `profiles/proxmox-lxc/base.nix`
removed.

## ~~Stale `servers_truenas_*` series in Prometheus TSDB~~ — FIXED 2026-05-14

**Resolved** by `delete_series` admin API call + `clean_tombstones`. All 43
stale `servers_truenas_*` series purged (Prometheus admin API was already
enabled via `--web.enable-admin-api`).

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

### ~~`'claude-code-bin' has been merged into 'claude-code'`~~ — FIXED 2026-05-14

**Resolved by commit `8baa676`**. Renamed all 9 references across 6 profile
configs + 3 modules. Eval output confirmed no longer warns.

### ~~`xdg.userDirs.setSessionVariables` default changed from `true` to `false`~~ — FIXED 2026-05-14

**Resolved by commit `8baa676`**. Set `xdg.userDirs.setSessionVariables = true;`
explicitly in `profiles/work/home.nix` (which is imported by personal too).

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

## ~~LAPTOP_A profile eval fails locally on DESK~~ — FIXED 2026-05-14

**Resolved by commit `1125709`**. Wrapped the cert path in
`if builtins.pathExists ... then [...] else []`. LAPTOP_A now evals cleanly
from DESK.
