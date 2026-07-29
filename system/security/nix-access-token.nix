# Nix access-tokens without leaking the PAT into the world-readable Nix store.
#
# WHY THIS EXISTS
# ---------------
# The obvious way to set a GitHub PAT for flake-input fetches is:
#
#   nix.extraOptions = "access-tokens = github.com=${systemSettings.githubAccessToken}";
#
# but `nix.extraOptions` is rendered into /etc/nix/nix.conf, which is a
# /nix/store file with mode 0444. The store is world-readable, so that puts the
# PAT in plain sight of every local user and every process on the machine.
#
# Instead we never interpolate the token value into anything Nix builds. The
# activation script below reads it at RUNTIME out of the (git-crypt'd)
# secrets/domains.nix that already lives on disk, and writes it to per-user
# nix.conf files with mode 0600:
#
#   /root/.config/nix/nix.conf          -> used by `sudo nixos-rebuild` / install.sh
#   /home/<user>/.config/nix/nix.conf   -> used by the user's own `nix` commands
#
# Nix merges ~/.config/nix/nix.conf over /etc/nix/nix.conf, so behaviour is
# unchanged — only the storage location and permissions differ.
#
# The token only lifts GitHub's anonymous rate limit; anonymous fetches still
# work. If the secrets file is missing or locked (e.g. a partner's laptop with
# git-crypt locked) the script is a no-op and the machine simply fetches
# anonymously.
#
# Gating on `githubAccessToken != ""` is safe: mkIf only tests the value, it
# never emits it into a store path.
{
  config,
  lib,
  systemSettings,
  userSettings,
  ...
}:

let
  enabled = (systemSettings.githubAccessToken or "") != "";

  username = userSettings.username;
  dotfilesDir = userSettings.dotfilesDir;
  secretsFile = "${dotfilesDir}/secrets/domains.nix";

  nixBin = "${config.nix.package}/bin/nix";

  # Written to each target as 0600. Kept minimal on purpose: this file exists
  # only to carry the secret, everything else stays in /etc/nix/nix.conf.
  writeTokenFor = { dir, owner, group }: ''
    install -d -m 0700 -o ${owner} -g ${group} ${dir}
    umask 077
    printf 'access-tokens = github.com=%s\n' "$token" > ${dir}/nix.conf.tmp
    chown ${owner}:${group} ${dir}/nix.conf.tmp
    chmod 0600 ${dir}/nix.conf.tmp
    mv -f ${dir}/nix.conf.tmp ${dir}/nix.conf
  '';

  removeTokenFor = dir: ''
    rm -f ${dir}/nix.conf
  '';

  targets = [
    { dir = "/root/.config/nix"; owner = "root"; group = "root"; }
    { dir = "/home/${username}/.config/nix"; owner = username; group = "users"; }
  ];
in
{
  system.activationScripts.nixAccessToken = lib.mkIf enabled {
    text = ''
      # Read the PAT at runtime so it never lands in a store path.
      token=""
      if [ -r ${secretsFile} ]; then
        token="$(${nixBin} eval --impure --raw \
          --expr '(import ${secretsFile}).githubAccessToken or ""' 2>/dev/null || true)"
      fi

      if [ -n "$token" ]; then
        ${lib.concatMapStringsSep "\n" writeTokenFor targets}
      else
        # No token available (locked repo / rotated to empty): make sure we
        # don't leave a stale one behind.
        ${lib.concatMapStringsSep "\n" (t: removeTokenFor t.dir) targets}
      fi
      unset token
    '';
  };
}
