# babydocs site — baby.local.akunito.com, published from git without a rebuild.
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
# Flags: babydocsSiteEnable, babydocsSiteRepo, babydocsSiteInterval,
#        babydocsSiteRoot, babydocsSiteDeployKey, babydocsSiteCryptKey.
# Serve it with nginxLocalServices.baby = { rootPath = "/var/www/baby"; };

{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.babydocsSiteEnable or false;
  repoUrl = systemSettings.babydocsSiteRepo or "git@github.com:akunito/babydocs.git";
  interval = systemSettings.babydocsSiteInterval or "5min";
  webroot = systemSettings.babydocsSiteRoot or "/var/www/baby";
  liveLink = "${webroot}/current";
  releases = "${webroot}/releases";
  deployKey = systemSettings.babydocsSiteDeployKey or "/etc/secrets/babydocs-deploy-key";
  cryptKey = systemSettings.babydocsSiteCryptKey or "/etc/secrets/babydocs-git-crypt";

  state = "/var/lib/babydocs";

  publisher = pkgs.writeShellApplication {
    name = "babydocs-publish";
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
        logger -t babydocs-publish "FAILED: $*"
        # announce a new failure once, not on every tick
        if [ "$(cat "$STATE/last-failure" 2>/dev/null || true)" != "$1" ]; then
          printf '%s' "$1" >"$STATE/last-failure"
          [ -x "$NOTIFY" ] && "$NOTIFY" send "👶 <b>babydocs</b>: publish failed — $1
The site still serves the last good build." || true
        fi
        exit 1
      }

      [ -r "${deployKey}" ] || fail "deploy key missing at ${deployKey}"
      [ -r "${cryptKey}" ] || fail "git-crypt key missing at ${cryptKey}"

      if [ ! -d "$REPO/.git" ]; then
        git clone --quiet "${repoUrl}" "$REPO" || fail "clone"
        git -C "$REPO" config user.email "babydocs@vps-prod"
        git -C "$REPO" config user.name "babydocs publisher"
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
          fail "git-crypt still locked — private/ and journal/ would publish as ciphertext"
        fi
      done < <(find private journal -type f ! -name '.gitkeep' 2>/dev/null)

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
      chmod -R a-w "$target"

      ln -sfn "$target" "$LIVE.new"
      mv -Tf "$LIVE.new" "$LIVE" || fail "symlink swap"
      printf '%s' "$rev" >"$STATE/published.rev"
      rm -f "$STATE/last-failure"
      logger -t babydocs-publish "published $rev"

      # keep the three most recent releases
      find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -rn | tail -n +4 | cut -d' ' -f2- | while read -r old; do chmod -R u+w "$old"; rm -rf "$old"; done
    '';
  };
in
lib.mkIf enabled {
  users.users.babydocs = {
    isSystemUser = true;
    group = "babydocs";
    home = state;
    description = "babydocs site publisher";
  };
  users.groups.babydocs = { };

  systemd.tmpfiles.rules = [
    "d ${state} 0700 babydocs babydocs -"
    # group nginx so the web server can traverse and read; owned by the publisher
    # so it can replace the `current` symlink without touching root-owned /var/www
    "d ${webroot} 0750 babydocs nginx -"
    "d ${releases} 0750 babydocs nginx -"
  ];

  systemd.services.babydocs-publish = {
    description = "babydocs: pull, build and publish baby.local";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "babydocs";
      Group = "babydocs";
      SupplementaryGroups = [ "nginx" ];
      ExecStart = "${publisher}/bin/babydocs-publish";
      # the checkout holds clinical material: no other service needs to see it
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
      UMask = "0027";
    };
  };

  systemd.timers.babydocs-publish = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = interval;
      RandomizedDelaySec = "30s";
    };
  };
}
