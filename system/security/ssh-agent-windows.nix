# sshAgentWindowsBridge (NixOS-WSL only): SSH_AUTH_SOCK -> the Windows OpenSSH
# agent, through npiperelay over the named pipe //./pipe/openssh-ssh-agent.
#
# WHY. gpg-agent holds unlocked ssh keys in RAM only; no cache-ttl survives the
# agent dying, and the agent dies with the WSL VM (`wsl --shutdown`, a Windows
# restart, or WSL reclaiming an idle VM). So a 400-day ttl still means one
# passphrase prompt per WSL boot. The Windows agent stores keys ON DISK sealed
# with DPAPI against the Windows account, so it survives a full PC restart.
#
# COST, recorded deliberately (decision 2026-09-21): there is no prompt any more,
# so every process running as the Windows user can sign with the key silently.
# The protection left is the Windows login, not a passphrase.
#
# gpg-agent keeps serving gpg itself; only enableSSHSupport is turned off, since
# /etc/set-environment guards its export with `if [ -z "$SSH_AUTH_SOCK" ]` and
# environment.sessionVariables is exported earlier in the same file — leaving
# both on would work by ordering alone, which is too fragile to rely on.
{ config, lib, pkgs, systemSettings ? {}, userSettings ? {}, ... }:

let
  enabled = systemSettings.sshAgentWindowsBridge or false;
  user = userSettings.username;
  winUser = systemSettings.wslWindowsUser or "";
  sock = "/home/${user}/.ssh/agent/windows.sock";

  # winget drops the exe in Packages/<id>_<source>/; its Links/ alias is an
  # app-exec-link reparse point that WSL cannot execute. Probed at start rather
  # than hardcoded: the Packages directory name carries the winget source id and
  # changes if the package is ever re-sourced.
  relayCandidates = [
    "/mnt/c/Users/${winUser}/AppData/Local/Microsoft/WinGet/Packages/albertony.npiperelay_Microsoft.Winget.Source_8wekyb3d8bbwe/npiperelay.exe"
    "/mnt/c/Users/${winUser}/AppData/Local/Microsoft/WinGet/Packages/jstarks.npiperelay_Microsoft.Winget.Source_8wekyb3d8bbwe/npiperelay.exe"
    "/mnt/c/Users/${winUser}/npiperelay.exe"
  ];

  start = pkgs.writeShellScript "ssh-agent-windows-bridge" ''
    relay=""
    for c in ${lib.escapeShellArgs relayCandidates}; do
      [ -x "$c" ] && { relay="$c"; break; }
    done
    if [ -z "$relay" ]; then
      echo "npiperelay.exe not found (winget install --id albertony.npiperelay)" >&2
      exit 1
    fi
    rm -f ${lib.escapeShellArg sock}
    exec ${pkgs.socat}/bin/socat \
      UNIX-LISTEN:${lib.escapeShellArg sock},fork,unlink-early,mode=600 \
      EXEC:"$relay -ei -s //./pipe/openssh-ssh-agent",nofork
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [{
      assertion = winUser != "";
      message = "sshAgentWindowsBridge needs wslWindowsUser to locate npiperelay.exe";
    }];

    programs.gnupg.agent.enableSSHSupport = lib.mkForce false;

    environment.systemPackages = [ pkgs.socat ];
    environment.sessionVariables.SSH_AUTH_SOCK = sock;

    systemd.user.services.ssh-agent-windows = {
      description = "SSH_AUTH_SOCK bridge to the Windows OpenSSH agent (npiperelay)";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = user;
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/${user}/.ssh/agent";
        ExecStart = "${start}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
