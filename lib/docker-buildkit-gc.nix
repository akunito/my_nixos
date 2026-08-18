# Shared BuildKit build-cache GC policy for daemon.settings.
#
# WHY THIS EXISTS
# Left unconfigured, dockerd's default GC policy lets the build cache grow to
# roughly 10% of the filesystem holding the docker root before it collects
# anything. That is ~100 GB on VPS_PROD's 1 TB root, ~45 GB on nas-aku's 457 GB
# cryptroot and ~49 GB on DESK's 489 GB root — so "it will clean itself up" is
# true only in a sense nobody wants. VPS_PROD had reached 79 GB of build cache
# by 2026-08-18, which is what prompted this.
#
# `docker system prune` (what virtualisation.docker.autoPrune runs) only drops
# *dangling* cache, so it never touches the in-use records that make up the
# bulk. A size cap is the only thing that bounds them.
#
# maxUsedSpace caps the total; reservedSpace is the floor GC will not prune
# below, so everyday rebuilds still hit a warm cache.
#
# VERIFIED 2026-08-18: `reservedSpace`/`maxUsedSpace`/`minFreeSpace` are the
# current field names (`keepStorage` is the deprecated one) — confirmed present
# in the moby 29.6.2 binary, and the generated JSON accepted by
# `dockerd --validate`. Note that --validate only rejects unknown *top-level*
# daemon.json keys; it silently accepts garbage inside a gc policy entry, so
# check field names against the binary, not against a passing validation.
#
# Usage — merge into a daemon.settings attrset:
#   (import ../../lib/docker-buildkit-gc.nix { })
#   (import ../../lib/docker-buildkit-gc.nix { max = "40GB"; reserved = "10GB"; })

{ max ? "20GB", reserved ? "5GB" }:

{
  "builder" = {
    "gc" = {
      "enabled" = true;
      "policy" = [
        { "all" = true; "reservedSpace" = reserved; "maxUsedSpace" = max; }
      ];
    };
  };
}
