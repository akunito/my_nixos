# Consume a local Nix binary cache (see system/app/nix-binary-cache.nix).
#
# Adds the extra substituter(s) and their public key(s) to nix.settings, and —
# critically — makes an unreachable cache a non-event.
#
# DESK, which hosts the cache, suspends on a schedule. Without the resilience
# settings below, every `nixos-rebuild` on a laptop would stall on TCP timeouts
# to a sleeping host before falling back to cache.nixos.org. With them, a dead
# cache costs a few seconds and the build proceeds normally.
{
  lib,
  systemSettings,
  ...
}:

let
  substituters = systemSettings.nixBinaryCacheSubstituters or [ ];
  publicKeys = systemSettings.nixBinaryCachePublicKeys or [ ];
  connectTimeout = systemSettings.nixBinaryCacheConnectTimeout or 5;
  enabled = substituters != [ ];
in
{
  config = lib.mkIf enabled {
    nix.settings = {
      # Appended to (not replacing) the defaults, so cache.nixos.org stays.
      extra-substituters = substituters;
      extra-trusted-public-keys = publicKeys;

      # Never let an offline or incomplete cache block a rebuild.
      #
      #  - fallback: if no substituter can supply a path, build it from source
      #    instead of failing the rebuild. This is the actual safety net.
      #  - connect-timeout: cap the wait on a sleeping host. The default lets
      #    curl decide, which is far too long for a machine that S3-suspends.
      #  - narinfo-cache-negative-ttl: a genuine miss (DESK simply doesn't have
      #    the path) is cached so we don't re-ask constantly. The default 3600
      #    is too long here though — it would keep ignoring DESK for an hour
      #    after it wakes up and gains the path. 60s balances both.
      fallback = true;
      connect-timeout = connectTimeout;
      narinfo-cache-negative-ttl = systemSettings.nixBinaryCacheNegativeTtl or 60;
    };
  };
}
