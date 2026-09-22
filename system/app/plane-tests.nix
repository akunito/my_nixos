# Plane regression suite + `plane-deploy` (APLANE-7 / APLANE-14) — VPS_PROD only.
#
# Installs two commands for the user who owns the Plane stacks:
#   plane-deploy [--ref REF] [--dev-only] [--config-only] [--rollback prod|dev] [--no-test-check]
#   plane-tests  refresh|safety|drift|seed|seed-check|l2|api|config|smoke|unit|build|e2e [args]
#
# `plane-deploy` is the ONLY way Plane changes, the way install.sh is for NixOS: it builds the
# bundle from the fork, runs the whole suite on dev, deploys to prod, smokes it read-only and
# rolls back on red, reporting to the infra-bot's Telegram relay.
#
# The scripts come from the store copy of system/app/plane-tests/remote, so a deploy always runs
# the committed version. `run.sh` still rsyncs that directory to ~/.cache/plane-tests for
# iteration; PLANE_TESTS_DIR points either command at that copy while a script is being written.
#
# Gated by systemSettings.planeTestsEnable (needs the plane + plane-dev stacks in the user's
# ~/.homelab, rootless docker, and the nix flake for Playwright's browsers).

{ lib, pkgs, systemSettings, userSettings, ... }:

let
  enabled = systemSettings.planeTestsEnable or false;
  username = userSettings.username;

  scripts = pkgs.runCommand "plane-tests-scripts" { } ''
    mkdir -p $out
    cp -r ${./plane-tests/remote}/* $out/
    chmod +x $out/*.sh
  '';

  # Rootless docker: the socket lives in the user's runtime dir, and nix-built wrappers get no
  # login shell, so DOCKER_HOST and PATH have to be set here (learned the hard way with
  # systemd-run --user: without DOCKER_HOST every container "is not running").
  wrapper = name: entry: pkgs.writeShellApplication {
    inherit name;
    # docker and psql are deliberately NOT here: `docker` comes from the host (packaging it
    # would drag in the insecure-pinned build this repo permits only for the daemon) and psql
    # always runs inside a container via `docker exec`.
    runtimeInputs = with pkgs; [ bash coreutils curl git gnugrep gnused gawk jq openssh python3 rsync ];
    text = ''
      [ "$(id -un)" = "${username}" ] || { echo "${name}: run as ${username} (it owns the Plane stacks)" >&2; exit 2; }
      export DOCKER_HOST=''${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}
      dir=''${PLANE_TESTS_DIR:-${scripts}}
      exec ${pkgs.bash}/bin/bash "$dir/${entry}" "$@"
    '';
  };

  planeDeploy = wrapper "plane-deploy" "deploy.sh";

  # One entry point for the individual layers; the script names stay an implementation detail.
  planeTests = pkgs.writeShellApplication {
    name = "plane-tests";
    runtimeInputs = [ planeDeploy pkgs.bash pkgs.coreutils ];
    text = ''
      cmd=''${1:-}; shift || true
      dir=''${PLANE_TESTS_DIR:-${scripts}}
      export DOCKER_HOST=''${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}
      case "$cmd" in
        refresh)    script=refresh.sh ;;
        safety)     script=l3_00_dev_safety.sh ;;
        drift)      script=l3_15_drift.sh ;;
        seed)       script=seed-qa.sh ;;
        seed-check) script=seed_check.sh ;;
        api)        script=l4-api.sh ;;
        l2)         script=l2_pytest.sh ;;
        config)     script=l3_config.sh ;;
        smoke)      script=l7_smoke.sh ;;
        smoke-user) script=smoke-user.sh ;;
        setup-dev)  script=setup-dev.sh ;;
        unit|build|e2e) set -- "$cmd" "$@"; script=fork-suite.sh ;;
        deploy)     exec ${planeDeploy}/bin/plane-deploy "$@" ;;
        *) echo "usage: plane-tests refresh|safety|drift|seed|seed-check|l2|api|config prod|dev|smoke prod|dev|unit|build|e2e|deploy" >&2; exit 2 ;;
      esac
      exec ${pkgs.bash}/bin/bash "$dir/$script" "$@"
    '';
  };
in
lib.mkIf enabled {
  environment.systemPackages = [ planeDeploy planeTests ];
}
