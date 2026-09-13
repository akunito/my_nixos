# claude-sync package builder — shared by claude-code.nix (hooks need the
# store path) and claude-sync.nix (packages, wrapper, timer).
#
# Returns { enable, package, wrapper, machine }.
{ pkgs, pkgs-unstable, lib, systemSettings, userSettings }:

let
  enable = systemSettings.claudeSyncEnable or false;
  isDesktop = (systemSettings.developmentToolsEnable or false)
    && (systemSettings.gpuType or "none") != "none";
  machine = systemSettings.envProfile or systemSettings.hostname;
  hubUser = systemSettings.claudeSyncHubUser or "akunito";
  hubHost = systemSettings.claudeSyncHubHost or "100.64.0.6";
  hubPort = toString (systemSettings.claudeSyncHubPort or 56777);
  hubDir = systemSettings.claudeSyncHubDir or "claude-sync";
  retentionDays = toString (systemSettings.claudeSyncRetentionDays or 90);
  realClaude = "${pkgs-unstable.claude-code}/bin/claude";

  package = pkgs.writeShellApplication {
    name = "claude-sync";
    runtimeInputs = with pkgs; [
      coreutils gnused gnugrep findutils gawk
      git openssh rsync jq util-linux # flock, setsid
    ] ++ lib.optional isDesktop pkgs.libnotify;
    # the script handles its own error paths; -e would abort hooks mid-way
    bashOptions = [ "nounset" "pipefail" ];
    text = ''
      # ---- configuration (claude-sync-pkg.nix) ----
      HUB_USER="${hubUser}"
      HUB_HOST="${hubHost}"
      HUB_PORT="${hubPort}"
      HUB_DIR="${hubDir}"
      MACHINE="${machine}"
      REAL_CLAUDE="${realClaude}"
      RETENTION_DAYS="${retentionDays}"
      export HUB_USER HUB_HOST HUB_PORT HUB_DIR MACHINE REAL_CLAUDE RETENTION_DAYS
      # ---- script ----
    '' + builtins.readFile ./claude-sync.sh;
  };

  # `claude` → pull first, fork foreign sessions, exec the real binary.
  # hiPrio wins the bin/claude collision against pkgs-unstable.claude-code.
  wrapper = lib.hiPrio (pkgs.writeShellScriptBin "claude" ''
    exec ${package}/bin/claude-sync wrap "$@"
  '');
in
{
  inherit enable package wrapper machine;
}
