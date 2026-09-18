# Private-repo documentation sites, published from git without a system rebuild.
#
# One instance per site, declared in `docsSites`. Today: babydocs (Irenka, IRIN)
# and homedocs (the house, HOME) — same procedure, same tooling, separate repos
# and separate boundaries.
#
# A timer pulls github.com/akunito/babydocs (private) with a read-only deploy
# key, unlocks git-crypt, generates the Starlight content tree from the markdown
# in the repo, builds it with node, and swaps the result in atomically.
#
# WHY A TIMER AND NOT A PUSH: both parents run Claude Code against the repo, on
# different machines, and Aga's laptop must never hold a credential for this
# host. Git is the only transport: whoever writes, pushes; the VPS notices.
#
#   /var/lib/babydocs/repo          the checkout (0700, babydocs user)
#   /var/lib/babydocs/published.rev the revision currently live
#   /var/www/baby/releases/<rev>    one directory per built revision (0750, group nginx)
#   /var/www/baby/current           symlink to the live release — nginx's root
#
# The swap has to happen INSIDE a directory this service owns: /var/www is root's,
# so a symlink directly at /var/www/baby could not be replaced (verified — the
# first publish failed exactly there).
#
# A failed build changes nothing: the symlink still points at the last good
# release, and the failure is announced once through infra-notify.
#
# Secrets (deployed by hand, see docs/akunito/infrastructure/services/babydocs-site.md):
#   /etc/secrets/babydocs-deploy-key   read-only GitHub deploy key for the repo
#   /etc/secrets/babydocs-git-crypt    git-crypt key (private/ and journal/)
#
# Flags: docsSites (attrset), e.g.
#
#   docsSites = {
#     babydocs = { repo = "git@github.com:akunito/babydocs.git"; webroot = "/var/www/baby"; };
#     homedocs = { repo = "git@github.com:akunito/homedocs.git"; webroot = "/var/www/home"; };
#   };
#
# Per site: repo, webroot, interval (default 5min), deployKey, cryptKey, encryptedDirs
# (the directories whose plaintext is asserted before publishing). The unit is
# `<name>-publish`, the user `<name>`, the state dir /var/lib/<name>.
# Serve each with nginxLocalServices.<x> = { rootPath = "<webroot>/current"; };
#
# The same git-crypt key file can serve several repositories: `git-crypt unlock`
# installs whatever key you hand it (verified 2026-09-18), so both sites point at
# /etc/secrets/babydocs-git-crypt. A deploy key, by contrast, must be unique per
# repository on GitHub — each site needs its own.

{ config, lib, pkgs, systemSettings, ... }:

let
  sites = systemSettings.docsSites or { };
  enabled = sites != { };

  mkPublisher = name: cfg:
  let
    repoUrl = cfg.repo;
    webroot = cfg.webroot;
    liveLink = "${webroot}/current";
    releases = "${webroot}/releases";
    deployKey = cfg.deployKey or "/etc/secrets/${name}-deploy-key";
    cryptKey = cfg.cryptKey or "/etc/secrets/babydocs-git-crypt";
    encryptedDirs = cfg.encryptedDirs or [ "private" "journal" ];
    state = "/var/lib/${name}";
  in
  pkgs.writeShellApplication {
    name = "${name}-publish";
    # bash is not decoration: npm runs a package's install scripts through
    # `spawn sh`, and writeShellApplication gives the unit ONLY these paths — no
    # /run/current-system/sw/bin. Without it esbuild's postinstall dies with
    # `spawn sh ENOENT` and npm ci fails, while the same command works by hand
    # because an interactive shell has sh on its PATH.
    runtimeInputs = with pkgs; [
      git git-crypt openssh nodejs_22 python3 rsync bash coreutils findutils gnugrep util-linux
    ];
    bashOptions = [ "nounset" "pipefail" ];
    text = ''
      STATE="${state}"
      REPO="$STATE/repo"
      RELEASES="${releases}"
      LIVE="${liveLink}"
      NOTIFY=/run/current-system/sw/bin/infra-notify
      export HOME="$STATE"
      export GIT_SSH_COMMAND="ssh -i ${deployKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$STATE/known_hosts"

      fail() {
        logger -t ${name}-publish "FAILED: $*"
        # announce a new failure once, not on every tick
        if [ "$(cat "$STATE/last-failure" 2>/dev/null || true)" != "$1" ]; then
          printf '%s' "$1" >"$STATE/last-failure"
          [ -x "$NOTIFY" ] && "$NOTIFY" send "📄 <b>${name}</b>: publish failed — $1
The site still serves the last good build." || true
        fi
        exit 1
      }

      [ -r "${deployKey}" ] || fail "deploy key missing at ${deployKey}"
      [ -r "${cryptKey}" ] || fail "git-crypt key missing at ${cryptKey}"

      if [ ! -d "$REPO/.git" ]; then
        git clone --quiet "${repoUrl}" "$REPO" || fail "clone"
        git -C "$REPO" config user.email "${name}@vps-prod"
        git -C "$REPO" config user.name "${name} publisher"
        (cd "$REPO" && git-crypt unlock "${cryptKey}") || fail "git-crypt unlock"
      fi

      cd "$REPO" || fail "cd repo"
      git fetch --quiet origin main || fail "fetch"
      rev=$(git rev-parse origin/main)
      published=$(cat "$STATE/published.rev" 2>/dev/null || true)
      [ "$rev" = "$published" ] && exit 0

      git reset --quiet --hard origin/main || fail "reset"
      # keep node_modules (expensive) but drop every other untracked artefact
      git clean -qfd -e site/node_modules || true

      # git-crypt must really be unlocked, or we would publish ciphertext. Test the
      # bytes, not `git-crypt status`: status reports what the .gitattributes say,
      # not whether this checkout can read it. Encrypted blobs start \0GITCRYPT.
      while IFS= read -r f; do
        if head -c 9 "$f" 2>/dev/null | grep -qa GITCRYPT; then
          fail "git-crypt still locked — ${lib.concatStringsSep "/, " encryptedDirs}/ would publish as ciphertext"
        fi
      done < <(find ${lib.concatStringsSep " " encryptedDirs} -type f ! -name '.gitkeep' 2>/dev/null)

      python3 tools/build-site.py || fail "content generation"

      cd "$REPO/site" || fail "cd site"
      if [ -f package-lock.json ]; then
        npm ci --no-audit --no-fund --silent || fail "npm ci"
      else
        npm install --no-audit --no-fund --silent || fail "npm install"
      fi
      npm run build --silent || fail "astro build"

      target="$RELEASES/$rev"
      rm -rf "$target"
      mkdir -p "$target"
      rsync -a --delete "$REPO/site/dist/" "$target/" || fail "rsync into release"
      # rsync preserves the repo's ownership (babydocs:babydocs, 0640) and the unit's
      # UMask makes the directory 0750 — nginx would get 403 on every request. Hand
      # the tree to the nginx group, read-only: the publisher owns it, the web server
      # reads it, nobody writes it.
      chgrp -R nginx "$target" || fail "chgrp release to nginx"
      chmod -R u=rX,g=rX,o= "$target" || fail "chmod release"

      ln -sfn "$target" "$LIVE.new"
      mv -Tf "$LIVE.new" "$LIVE" || fail "symlink swap"
      printf '%s' "$rev" >"$STATE/published.rev"
      rm -f "$STATE/last-failure"
      logger -t ${name}-publish "published $rev"

      # keep the three most recent releases
      find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -rn | tail -n +4 | cut -d' ' -f2- | while read -r old; do chmod -R u+w "$old"; rm -rf "$old"; done
    '';
  };

  publishers = lib.mapAttrs mkPublisher sites;
in
lib.mkIf enabled {
  users.users = lib.mapAttrs (name: _: {
    isSystemUser = true;
    group = name;
    home = "/var/lib/${name}";
    description = "${name} site publisher";
  }) sites;
  users.groups = lib.mapAttrs (_: _: { }) sites;

  systemd.tmpfiles.rules = lib.flatten (lib.mapAttrsToList (name: cfg: [
    "d /var/lib/${name} 0700 ${name} ${name} -"
    # group nginx so the web server can traverse and read; owned by the publisher
    # so it can replace the `current` symlink without touching root-owned /var/www
    "d ${cfg.webroot} 0750 ${name} nginx -"
    "d ${cfg.webroot}/releases 0750 ${name} nginx -"
  ]) sites);

  systemd.services = lib.mapAttrs' (name: cfg: lib.nameValuePair "${name}-publish" {
    description = "${name}: pull, build and publish ${cfg.webroot}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = name;
      Group = name;
      SupplementaryGroups = [ "nginx" ];
      ExecStart = "${publishers.${name}}/bin/${name}-publish";
      # the checkout holds private material: no other service needs to see it
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
      UMask = "0027";
    };
  }) sites;

  systemd.timers = lib.mapAttrs' (name: cfg: lib.nameValuePair "${name}-publish" {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = cfg.interval or "5min";
      RandomizedDelaySec = "30s";
    };
  }) sites;
}
