# Boot-safety guard: refuse to build a system whose fileSystems include Docker
# overlay mounts.
#
# THE FAILURE IT PREVENTS
# `nixos-generate-config --show-hardware-config` enumerates whatever is mounted
# *right now*. If Docker is running, its live `.../docker/overlay2/<id>/merged`
# mounts get written into hardware-configuration.nix as required boot
# filesystems. At cold boot Docker is down, so `overlay: missing 'lowerdir'`
# fails local-fs.target and the machine drops to emergency mode. A running
# system never notices — `nixos-rebuild switch` finds the mounts already
# mounted — so only a real reboot exposes the brick. DESK hit this on
# 2026-08-04 (generations 849-851) and nas-aku on the same outage.
#
# WHY A MODULE AND NOT ANOTHER SCRIPT CHECK
# install.sh already strips these blocks and aborts if any survive (b485e7c,
# 50bd268), but that only guards the install.sh path. autoSystemUpdate.sh
# regenerates the file too and its scrub only covered autofs/NFS — which is
# exactly how nas-aku got re-poisoned into generations 56 and 57 by a weekly
# autoupdate, after being cleaned in August. A bare `nixos-rebuild switch` had
# no guard at all.
#
# Living in the evaluated config means EVERY path — install.sh,
# autoSystemUpdate.sh, autoupgrade, a hand-run nixos-rebuild — fails loudly
# before anything is built. Imported for every profile from lib/flake-base.nix.
#
# IF THIS FIRES
# The named entries are in system/hardware-configuration.nix. Either
# regenerate through install.sh (which strips them), or delete the
# `fileSystems."/var/lib/docker/..."` blocks by hand and rebuild. Never
# work around it by deleting this module.

{ config, lib, ... }:

let
  # Deliberately narrow: only mount points inside a Docker data root, so a
  # profile that legitimately uses an overlay filesystem elsewhere (impermanence,
  # a live ISO's /nix/.rw-store) is unaffected.
  isDockerMount =
    mountPoint:
    lib.hasPrefix "/var/lib/docker/" mountPoint # root daemon
    || lib.hasInfix "/docker/overlay2/" mountPoint # rootless daemon, any $HOME
    || lib.hasInfix "/docker/containers/" mountPoint;

  offenders = lib.filter isDockerMount (lib.attrNames config.fileSystems);
in
{
  assertions = [
    {
      assertion = offenders == [ ];
      message = ''
        hardware-configuration.nix contains ${toString (lib.length offenders)} Docker
        overlay mount(s) in fileSystems. Building this would produce a generation
        that cannot boot (overlay: missing 'lowerdir' -> emergency mode).

        Offending mount points:
        ${lib.concatMapStringsSep "\n" (m: "  - ${m}") offenders}

        This happens when nixos-generate-config runs while Docker is up. Fix by
        redeploying through install.sh (it strips these and re-validates), or by
        deleting those fileSystems blocks from system/hardware-configuration.nix
        by hand. See system/security/hwconfig-guard.nix.
      '';
    }
  ];
}
