# Local Nix binary cache (harmonia) — serve DESK's /nix/store to the other machines.
#
# WHY
# ---
# Every machine here builds the same closures independently. A laptop that has
# drifted a few dozen commits behind ends up compiling things like
# bitwarden-desktop or nextcloud-client from source on a mobile CPU, because
# cache.nixos.org has no binary for a locally-modified derivation. DESK has
# already built most of it. Pointing the fleet at DESK as an extra substituter
# turns those rebuilds into downloads.
#
# HOW IT FITS TOGETHER
#   server (this module, DESK):  nixBinaryCacheServeEnable = true
#   clients (every other host):  nixBinaryCacheSubstituters + nixBinaryCachePublicKeys
#
# SIGNING KEY
# Nix refuses unsigned paths from a substituter, so the cache needs a keypair.
# It is generated on first activation into /var/lib/harmonia (0400, root) and
# never passes through a derivation — same rule as the GitHub PAT and the DB
# credentials, see system/security/nix-access-token.nix. The PUBLIC half is
# printed to the journal and written next to it for copying into the client
# config; public keys are meant to be public (cache.nixos.org's ships in every
# nix.conf), so it is safe to commit.
#
# EXPOSURE
# Serving the store lets a peer fetch any store path whose hash it knows. Paths
# are not enumerable through harmonia, but this is still a read surface over the
# store — which is exactly where credentials used to leak from before the
# 2026-07-29 audit. Keep it on tailscale0 (and optionally trusted LAN links);
# do not expose it publicly.
#
# AVAILABILITY
# DESK suspends. Clients must never block on a sleeping cache — the client half
# sets fallback = true and a short connect-timeout so a miss degrades to
# cache.nixos.org / a local build instead of hanging the rebuild.
{
  config,
  lib,
  pkgs,
  systemSettings,
  ...
}:

let
  enabled = systemSettings.nixBinaryCacheServeEnable or false;
  port = systemSettings.nixBinaryCachePort or 5000;
  bindAddr = systemSettings.nixBinaryCacheBindAddress or "[::]";
  openTailscale = systemSettings.nixBinaryCacheOpenFirewallTailscale or true;
  lanInterfaces = systemSettings.nixBinaryCacheLanInterfaces or [ ];
  # Lower number = preferred. cache.nixos.org is 40, so 30 makes the LAN/mesh
  # copy win whenever it has the path.
  priority = systemSettings.nixBinaryCachePriority or 30;

  stateDir = "/var/lib/harmonia";
  privKey = "${stateDir}/cache-priv-key.pem";
  pubKey = "${stateDir}/cache-pub-key.pem";
in
{
  config = lib.mkIf enabled {
    # Generate the keypair once, outside the store.
    systemd.services.harmonia-keygen = {
      description = "Generate the local binary cache signing key";
      wantedBy = [ "multi-user.target" ];
      before = [ "harmonia.service" ];
      requiredBy = [ "harmonia.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0755 -o root -g root ${stateDir}
        if [ ! -s ${privKey} ]; then
          # Key name must be unique per cache; clients match on it.
          ${config.nix.package}/bin/nix-store --generate-binary-cache-key \
            "${systemSettings.hostname}-1" ${privKey} ${pubKey}
          chmod 0400 ${privKey}
          chmod 0444 ${pubKey}
        fi
        echo "local binary cache public key: $(cat ${pubKey})"
      '';
    };

    services.harmonia = {
      enable = true;
      signKeyPaths = [ privKey ];
      settings = {
        bind = "${bindAddr}:${toString port}";
        inherit priority;
      };
    };

    # harmonia runs under DynamicUser and needs to read the signing key.
    systemd.services.harmonia.serviceConfig.SupplementaryGroups = lib.mkAfter [ ];

    # Reachable over the mesh, and optionally over named LAN links (e.g. the
    # 10GbE bond) for full-speed pulls. One attribute, built from both sources —
    # assigning networking.firewall.interfaces twice in the same attrset is a
    # duplicate-definition error, not a merge.
    networking.firewall.interfaces = lib.mkMerge (
      (lib.optional openTailscale { tailscale0.allowedTCPPorts = [ port ]; })
      ++ (map (iface: { "${iface}".allowedTCPPorts = [ port ]; }) lanInterfaces)
    );

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "nix-cache-pubkey" ''
        # Print the public key to paste into nixBinaryCachePublicKeys.
        cat ${pubKey} 2>/dev/null || echo "cache key not generated yet — is harmonia-keygen.service up?"
      '')
    ];
  };
}
